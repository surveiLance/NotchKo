import Foundation
import Combine

/// Live view of the coding agents running on this Mac, read from the
/// transcripts they already write to disk — Claude Code under
/// `~/.claude/projects`, Codex under `~/.codex/sessions`. Nothing is sent
/// anywhere; scanning only happens when the tab is open.
@MainActor
final class AgentsStore: ObservableObject {
    enum Agent: String, CaseIterable, Identifiable {
        case claude, codex
        var id: String { rawValue }
        var title: String { self == .claude ? "Claude Code" : "Codex" }
        var symbol: String { self == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right" }
    }

    struct Session: Identifiable, Equatable {
        let id: String
        let agent: Agent
        let project: String
        let model: String?
        let tokens: Int
        /// The last thing asked of it, so you can tell sessions apart.
        let activity: String?
        let lastActivity: Date
        /// Touched in the last couple of minutes — i.e. probably still working.
        var isLive: Bool { Date().timeIntervalSince(lastActivity) < 120 }
    }

    /// A usage window Codex reports (5-hourly and weekly).
    struct Limit: Equatable {
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
    }

    struct Summary: Equatable {
        var tokensToday = 0
        var sessionsToday = 0
        var limits: [Limit] = []
        /// Limits carried over from an earlier day's session.
        var limitsAreStale = false
        var models: [String] = []
    }

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var summary: [Agent: Summary] = [:]
    @Published private(set) var loading = false

    private var task: Task<Void, Never>?
    private var lastScan = Date.distantPast
    /// Parsed totals keyed by path, so unchanged transcripts aren't re-read.
    private var cache: [String: (mtime: Date, size: Int, result: FileScan)] = [:]

    func refreshIfStale(_ maxAge: TimeInterval = 20) {
        if sessions.isEmpty || Date().timeIntervalSince(lastScan) > maxAge { refresh() }
    }

    func refresh() {
        task?.cancel()
        loading = sessions.isEmpty
        lastScan = Date()
        let known = cache
        task = Task { [weak self] in
            let scanned = await Self.scan(cache: known)
            guard !Task.isCancelled, let self else { return }
            self.cache = scanned.cache
            self.sessions = scanned.sessions.sorted { $0.lastActivity > $1.lastActivity }
            self.summary = scanned.summary
            self.loading = false
        }
    }

    var liveCount: Int { sessions.filter(\.isLive).count }

    static func format(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000...: return String(format: "%.1fM", Double(tokens) / 1_000_000)
        case 1_000...:     return String(format: "%.0fK", Double(tokens) / 1_000)
        default:           return "\(tokens)"
        }
    }

    // MARK: - Scanning

    struct FileScan {
        var tokens = 0
        var model: String?
        var project = ""
        var activity: String?
        var limits: [Limit] = []
    }

    private struct ScanResult {
        var sessions: [Session] = []
        var summary: [Agent: Summary] = [:]
        var cache: [String: (mtime: Date, size: Int, result: FileScan)] = [:]
    }

    private static func scan(cache: [String: (mtime: Date, size: Int, result: FileScan)]) async -> ScanResult {
        await Task.detached(priority: .utility) {
            var out = ScanResult()
            var cache = cache
            let since = Calendar.current.startOfDay(for: Date())
            let fm = FileManager.default

            func transcripts(_ root: URL) -> [URL] {
                guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return [] }
                return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
            }

            let home = fm.homeDirectoryForCurrentUser
            let sources: [(Agent, URL)] = [
                (.claude, home.appendingPathComponent(".claude/projects")),
                (.codex, home.appendingPathComponent(".codex/sessions"))
            ]

            for (agent, root) in sources {
                var summary = Summary()
                var models = Set<String>()
                for url in transcripts(root) {
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    guard let modified = values?.contentModificationDate, modified >= since else { continue }
                    let size = values?.fileSize ?? 0

                    let scan: FileScan
                    if let hit = cache[url.path], hit.mtime == modified, hit.size == size {
                        scan = hit.result
                    } else {
                        scan = agent == .claude ? scanClaude(url) : scanCodex(url)
                        cache[url.path] = (modified, size, scan)
                    }
                    out.cache[url.path] = (modified, size, scan)

                    guard scan.tokens > 0 || !scan.project.isEmpty else { continue }
                    summary.tokensToday += scan.tokens
                    summary.sessionsToday += 1
                    if let m = scan.model { models.insert(m) }
                    if !scan.limits.isEmpty { summary.limits = scan.limits }

                    out.sessions.append(Session(
                        id: url.path, agent: agent,
                        project: scan.project.isEmpty ? url.deletingLastPathComponent().lastPathComponent : scan.project,
                        model: scan.model, tokens: scan.tokens, activity: scan.activity,
                        lastActivity: modified))
                }
                summary.models = models.sorted()
                // Plan windows are worth seeing even on a day you haven't run
                // Codex, so fall back to the most recent session's figures.
                if agent == .codex, summary.limits.isEmpty,
                   let newest = transcripts(root).max(by: { a, b in
                       let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                       let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                       return da < db
                   }) {
                    summary.limits = scanCodex(newest).limits
                    summary.limitsAreStale = true
                }
                out.summary[agent] = summary
            }
            return out
        }.value
    }

    /// Claude Code: one JSON object per line; assistant lines carry usage.
    /// Splits a memory-mapped file into lines without building Swift Strings
    /// for all of it — transcripts run to tens of MB and String's Unicode
    /// handling makes that take seconds.
    private nonisolated static func lines(of url: URL) -> [Data]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var out: [Data] = []
        out.reserveCapacity(4096)
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            if end > start { out.append(data[start..<end]) }
            start = end < data.endIndex ? data.index(after: end) : data.endIndex
        }
        return out
    }

    private nonisolated static func scanClaude(_ url: URL) -> FileScan {
        var scan = FileScan()
        guard let lines = lines(of: url) else { return scan }
        let usageKey = Data("\"usage\":{".utf8)
        let userKey = Data("\"type\":\"user\"".utf8)

        func json(_ line: Data) -> [String: Any]? {
            try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        }

        for line in lines where line.range(of: usageKey) != nil {
            guard let obj = json(line), let message = obj["message"] as? [String: Any] else { continue }
            if let model = message["model"] as? String { scan.model = model }
            if let usage = message["usage"] as? [String: Any] {
                // Cache reads are excluded — they're the cheap part and would
                // dwarf everything else.
                let input = usage["input_tokens"] as? Int ?? 0
                let created = usage["cache_creation_input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                scan.tokens += input + created + output
            }
        }

        // Not every line carries cwd, so check a handful rather than just the
        // first — otherwise the encoded folder name leaks into the UI.
        for line in lines.prefix(50) {
            if let obj = json(line), let cwd = obj["cwd"] as? String {
                scan.project = (cwd as NSString).lastPathComponent
                break
            }
        }

        // Latest prompt: walk back and stop at the first readable one.
        for line in lines.reversed() where line.range(of: userKey) != nil {
            guard let obj = json(line), let message = obj["message"] as? [String: Any],
                  let p = prompt(from: message["content"]) else { continue }
            scan.activity = p
            break
        }
        return scan
    }

    /// First readable line of a user turn, skipping system reminders and
    /// tool results, trimmed to something that fits a row.
    private nonisolated static func prompt(from content: Any?) -> String? {
        var candidates: [String] = []
        if let s = content as? String {
            candidates = [s]
        } else if let blocks = content as? [[String: Any]] {
            candidates = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        }
        for raw in candidates {
            // Strip attachment markers the CLIs splice in, then take the first
            // real line of what was actually typed.
            var t = raw
            while let r = t.range(of: #"\[Image:[^\]]*\]"#, options: .regularExpression) {
                t.removeSubrange(r)
            }
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !t.hasPrefix("<"), !t.hasPrefix("#"),
                  !t.contains("TRANSCRIPT START"), !t.hasPrefix("Caveat:") else { continue }
            if let firstLine = t.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                t = String(firstLine).trimmingCharacters(in: .whitespaces)
            }
            guard !t.isEmpty else { continue }
            return t.count > 110 ? String(t.prefix(110)) + "…" : t
        }
        return nil
    }

    /// Codex: rollout files with session_meta plus token_count events that
    /// carry running totals and the plan's rate limits.
    private nonisolated static func scanCodex(_ url: URL) -> FileScan {
        var scan = FileScan()
        guard let lines = lines(of: url) else { return scan }
        for line in lines {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any] else { continue }
            if let cwd = payload["cwd"] as? String, scan.project.isEmpty {
                scan.project = (cwd as NSString).lastPathComponent
            }
            if let model = payload["model"] as? String { scan.model = model }
            if payload["role"] as? String == "user", let p = prompt(from: payload["content"]) {
                scan.activity = p
            }
            if let info = payload["info"] as? [String: Any],
               let total = info["total_token_usage"] as? [String: Any] {
                // Running total, so take the latest rather than summing.
                let input = total["input_tokens"] as? Int ?? 0
                let cached = total["cached_input_tokens"] as? Int ?? 0
                let output = total["output_tokens"] as? Int ?? 0
                scan.tokens = max(0, input - cached) + output
            }
            if let limits = payload["rate_limits"] as? [String: Any] {
                scan.limits = [("primary", "5-hourly"), ("secondary", "Weekly")].compactMap { key, label in
                    guard let w = limits[key] as? [String: Any],
                          let used = w["used_percent"] as? Double else { return nil }
                    let resets = (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                    return Limit(label: label, usedPercent: used, resetsAt: resets)
                }
            }
        }
        return scan
    }
}
