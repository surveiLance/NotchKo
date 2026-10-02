import SwiftUI

/// What Claude Code and Codex are doing, read from the transcripts they
/// already write locally.
struct AgentsView: View {
    @ObservedObject var agents: AgentsStore
    /// Called after a row sends you to its app, so the notch can tuck away.
    var onOpen: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                agentCard(.claude)
                agentCard(.codex)
            }
            .frame(height: 54)

            sessions
        }
        .onAppear { agents.refreshIfStale() }
    }

    // MARK: Per-agent summary

    private func agentCard(_ agent: AgentsStore.Agent) -> some View {
        let s = agents.summary[agent] ?? .init()
        return HStack(spacing: 9) {
            Image(systemName: agent.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(agent == .claude ? Color.orange : Color.cyan)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.title)
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle(s))
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)

            HStack(spacing: 7) {
                // Only Codex records plan windows locally; Claude Code does
                // not, so its card shows usage without a dial rather than a
                // number that would be made up.
                ForEach(s.limits, id: \.label) { limit in
                    Dial(percent: limit.usedPercent,
                         caption: limit.label == "Weekly" ? "wk" : "5h",
                         hint: resetHint(limit, stale: s.limitsAreStale),
                         dimmed: s.limitsAreStale)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.09), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(agent.title), \(subtitle(s))")
    }

    private func subtitle(_ s: AgentsStore.Summary) -> String {
        guard s.sessionsToday > 0 else {
            return s.limits.isEmpty ? "Nothing today" : "Nothing today · last window"
        }
        return "\(AgentsStore.format(s.tokensToday)) · \(s.sessionsToday) session\(s.sessionsToday == 1 ? "" : "s")"
    }

    private func resetHint(_ limit: AgentsStore.Limit, stale: Bool) -> String {
        let prefix = stale ? "\(limit.label) (last session)" : limit.label
        guard let resets = limit.resetsAt else { return "\(prefix) window" }
        let mins = Int(resets.timeIntervalSinceNow / 60)
        if mins <= 0 { return "\(prefix) — window has reset" }
        return mins < 60 ? "\(prefix) — resets in \(mins)m" : "\(prefix) — resets in \(mins / 60)h"
    }

    // MARK: Session list

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(agents.liveCount > 0 ? "\(agents.liveCount) WORKING NOW" : "TODAY")
                    .font(.system(size: 8, weight: .semibold)).tracking(0.9)
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
                    VStack(spacing: 3) {
                        ForEach(agents.sessions) { session in
                            SessionRow(session: session) {
                                AgentsStore.open(session)
                                onOpen()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Project, model and the last thing it was asked to do.
private struct SessionRow: View {
    let session: AgentsStore.Session
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) { row }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Open in \(session.agent.appName)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(session.project), \(short(session.model)), \(session.activity ?? "no recent prompt"), \(AgentsStore.format(session.tokens)) tokens, \(ago(session.lastActivity))\(session.isLive ? ", working" : "")")
            .accessibilityHint("Opens \(session.agent.appName)")
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(session.isLive ? Color.green : .white.opacity(0.2))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(short(session.model))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.white.opacity(0.09)))
                }
                Text(session.activity ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(session.activity == nil ? 0.25 : 0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(AgentsStore.format(session.tokens))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                Text(ago(session.lastActivity))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
            }

            Image(systemName: "arrow.up.forward")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 0.6 : 0))
                .padding(.top, 3)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.08 : 0.03)))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func short(_ model: String?) -> String {
        guard let model else { return "—" }
        return model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
    }

    private func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}

/// Ring showing how much of a window or budget is gone.
private struct Dial: View {
    let percent: Double
    let caption: String
    let hint: String
    var dimmed = false

    private var tint: Color {
        switch percent {
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
                    .trim(from: 0, to: min(max(percent, 0) / 100, 1))
                    .stroke(tint.opacity(dimmed ? 0.5 : 1), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percent))")
                    .font(.system(size: 8, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 26, height: 26)
            Text(caption)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .help(hint)
        .accessibilityLabel("\(caption) usage \(Int(percent)) percent")
    }
}
