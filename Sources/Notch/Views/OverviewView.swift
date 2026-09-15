import SwiftUI

/// Home tab: everything at a glance. Each card is a shortcut to its full tab.
struct OverviewView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var spotify: SpotifyClient
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var clock: ClockStore
    @ObservedObject var devices: DevicesStore

    init(state: NotchState) {
        self.state = state
        spotify = state.spotify; shelf = state.shelf; clock = state.clock; devices = state.devices
    }

    var body: some View {
        HStack(spacing: 10) {
            musicCard
                .frame(width: 214)
            VStack(spacing: 6) {
                if clock.isActive { clockRow }
                devicesRow
                shelfRow
            }
        }
        .onAppear { devices.refreshIfStale() }
    }

    // MARK: Music

    private var accent: Color { Color(nsColor: spotify.accent) }

    private var musicCard: some View {
        OverviewCard(action: { state.tab = .music }) {
            HStack(spacing: 10) {
                Group {
                    if let image = spotify.artwork {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08))
                            .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.3)))
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    if let track = spotify.track {
                        Text(track.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(track.artist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        Spacer(minLength: 2)
                        HStack(spacing: 10) {
                            MiniButton(symbol: spotify.isPlaying ? "pause.fill" : "play.fill", label: spotify.isPlaying ? "Pause" : "Play") { spotify.playPause() }
                            MiniButton(symbol: "forward.fill", label: "Next track") { spotify.next() }
                            if spotify.isPlaying { EqualizerBars(color: spotify.accent).scaleEffect(0.8) }
                        }
                    } else {
                        Text("Nothing playing").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        Text("Spotify").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        Spacer(minLength: 2)
                        MiniButton(symbol: "arrow.up.forward.app", label: "Open Spotify") { spotify.openApp(); state.collapseNow() }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
        .accessibilityLabel(spotify.track.map { "Now playing \($0.name) by \($0.artist)" } ?? "Nothing playing")
    }

    // MARK: Rows

    private var clockRow: some View {
        OverviewCard(action: { state.tab = .clock }) {
            HStack(spacing: 8) {
                Image(systemName: clock.timerRunning || clock.timerFired ? "timer" : "stopwatch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(clock.timerFired ? .red : .orange)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text({
                        if let r = clock.pillReadout {
                            switch r {
                            case .timer(let t): return ClockStore.format(t)
                            case .stopwatch(let t): return ClockStore.format(t)
                            case .fired: return "00:00"
                            }
                        }
                        return ""
                    }())
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(clock.timerFired ? .red : .white)
                }
                Text(clock.timerFired ? "Time's up" : (clock.timerRunning ? "Timer" : "Stopwatch"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
                MiniButton(symbol: clock.timerFired ? "checkmark" : "pause.fill",
                           label: clock.timerFired ? "Dismiss" : "Pause") {
                    if clock.timerRunning || clock.timerFired { clock.timerToggle() } else { clock.stopwatchToggle() }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private var devicesRow: some View {
        OverviewCard(action: { state.tab = .devices }) {
            HStack(spacing: 10) {
                if let mac = devices.devices.first(where: { $0.kind == .macBattery }), let b = mac.batteries.first {
                    Label("\(b.percent)%", systemImage: batterySymbol(b.percent, charging: mac.detail.hasPrefix("Charging")))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(mac.detail.hasPrefix("Charging") ? .green : (b.percent <= 20 ? .red : .white))
                } else if let b = Battery.read() {
                    Label("\(b.percent)%", systemImage: batterySymbol(b.percent, charging: b.charging))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(b.charging ? .green : .white)
                }
                let bt = devices.devices.filter { [.headphones, .speaker, .keyboard, .mouse, .gamepad, .phone, .other].contains($0.kind) }
                if bt.isEmpty {
                    Text("No devices").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                } else {
                    ForEach(bt.prefix(2)) { d in
                        HStack(spacing: 3) {
                            Image(systemName: d.symbol).font(.system(size: 10, weight: .medium))
                            if let b = d.batteries.first {
                                Text(d.batteries.count > 1 ? "\(d.batteries.map { "\($0.percent)" }.joined(separator: "/"))%" : "\(b.percent)%")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            } else {
                                Text(d.name).font(.system(size: 10)).lineLimit(1)
                            }
                        }
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    if bt.count > 2 {
                        Text("+\(bt.count - 2)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 10)
        }
    }

    private var shelfRow: some View {
        OverviewCard(action: { state.tab = .shelf }) {
            HStack(spacing: 8) {
                Image(systemName: "tray.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                if shelf.items.isEmpty {
                    Text("Shelf empty · drop files on the notch").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                } else {
                    HStack(spacing: -6) {
                        ForEach(shelf.items.prefix(4)) { item in
                            Image(nsImage: shelf.thumbnail(for: item)).resizable().aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text("\(shelf.items.count) file\(shelf.items.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
                if !shelf.items.isEmpty {
                    MiniButton(symbol: "airplayaudio", label: "AirDrop all") { ShelfStore.airDrop(shelf.items.map(\.url)) }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func batterySymbol(_ p: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch p {
        case ..<10: return "battery.0percent"
        case ..<35: return "battery.25percent"
        case ..<60: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default:    return "battery.100percent"
        }
    }
}

// MARK: - Pieces

private struct OverviewCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct MiniButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(hovering ? 0.18 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}
