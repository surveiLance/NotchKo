import SwiftUI

/// What Claude Code and Codex have been doing today, read from the
/// transcripts they write locally.
struct AgentsView: View {
    @ObservedObject var agents: AgentsStore

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                agentCard(.claude)
                agentCard(.codex)
            }
            .frame(width: 210)

            sessions
        }
        .onAppear { agents.refreshIfStale() }
    }

    // MARK: Per-agent summary

    private func agentCard(_ agent: AgentsStore.Agent) -> some View {
        let s = agents.summary[agent] ?? .init()
        return HStack(spacing: 8) {
            Image(systemName: agent.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(agent == .claude ? Color.orange : Color.cyan)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.title)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                Text(s.sessionsToday == 0
                     ? (s.limits.isEmpty ? "Nothing today" : "Nothing today · last window below")
                     : "\(AgentsStore.format(s.tokensToday)) · \(s.sessionsToday) session\(s.sessionsToday == 1 ? "" : "s")")
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)

            // Only Codex reports plan windows.
            if !s.limits.isEmpty {
                HStack(spacing: 6) {
                    ForEach(s.limits, id: \.label) { limit in
                        LimitDial(limit: limit, stale: s.limitsAreStale)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.09), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(agent.title), \(AgentsStore.format(s.tokensToday)) tokens today")
    }

    // MARK: Session list

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(agents.liveCount > 0 ? "\(agents.liveCount) WORKING" : "TODAY")
                    .font(.system(size: 8, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(agents.liveCount > 0 ? .green : .white.opacity(0.4))
                Spacer(minLength: 0)
                Button { agents.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh")
            }

            if agents.sessions.isEmpty {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    if agents.loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("No agent sessions today")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(agents.sessions.prefix(12)) { SessionRow(session: $0) }
                    }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: AgentsStore.Session
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(session.isLive ? Color.green : .white.opacity(0.22))
                .frame(width: 6, height: 6)
            Text(session.project)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            if let model = session.model {
                Text(short(model))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(AgentsStore.format(session.tokens))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.65))
            Text(ago(session.lastActivity))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(hovering ? 0.07 : 0)))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.project), \(AgentsStore.format(session.tokens)) tokens, \(ago(session.lastActivity)) ago\(session.isLive ? ", working" : "")")
    }

    /// "claude-opus-5" → "opus-5", "gpt-5.6-sol" → "gpt-5.6-sol".
    private func short(_ model: String) -> String {
        model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
    }

    private func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

/// Small ring showing how much of a usage window is gone.
private struct LimitDial: View {
    let limit: AgentsStore.Limit
    var stale = false

    private var tint: Color {
        switch limit.usedPercent {
        case 85...: return .red
        case 60...: return .orange
        default: return .green
        }
    }

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                Circle().stroke(.white.opacity(0.14), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(limit.usedPercent / 100, 1))
                    .stroke(tint.opacity(stale ? 0.55 : 1), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(limit.usedPercent))")
                    .font(.system(size: 8, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 26, height: 26)
            Text(limit.label == "Weekly" ? "wk" : "5h")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .help(resetHint)
        .accessibilityLabel("\(limit.label) usage \(Int(limit.usedPercent)) percent")
    }

    private var resetHint: String {
        let prefix = stale ? "\(limit.label) (last session)" : limit.label
        guard let resets = limit.resetsAt else { return "\(prefix) window" }
        let mins = Int(resets.timeIntervalSinceNow / 60)
        if mins <= 0 { return "\(prefix) — window has reset" }
        return mins < 60 ? "\(prefix) — resets in \(mins)m"
                         : "\(prefix) — resets in \(mins / 60)h"
    }
}
