import SwiftUI

/// Home tab: everything at a glance. Each card is a shortcut to its full tab.
/// The music card borrows the artwork's colour so the notch feels tied to
/// whatever is playing rather than being a grid of grey boxes.
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

    private var accent: Color { Color(nsColor: spotify.accent) }

    var body: some View {
        HStack(spacing: 8) {
            musicCard.frame(width: 226)
            VStack(spacing: 6) {
                if clock.isActive { clockRow }
                devicesRow
                shelfRow
            }
        }
        .onAppear { devices.refreshIfStale() }
    }

    // MARK: Music

    private var musicCard: some View {
        Card(tint: spotify.track != nil ? accent : nil, action: { state.tab = .music }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    artwork
                    VStack(alignment: .leading, spacing: 2) {
                        if let track = spotify.track {
                            Text(track.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white).lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        } else {
                            Text("Nothing playing")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                            Text("Spotify")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer(minLength: 0)
                        controls
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                if spotify.track != nil { progress }
            }
            .padding(10)
        }
        .accessibilityLabel(spotify.track.map { "Now playing \($0.name) by \($0.artist)" } ?? "Nothing playing")
    }

    private var artwork: some View {
        Group {
            if let image = spotify.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08))
                    .overlay(Image(systemName: "music.note").font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.3)))
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 5, y: 2)
    }

    @ViewBuilder
    private var controls: some View {
        if spotify.track != nil {
            HStack(spacing: 8) {
                RoundIcon(symbol: spotify.isPlaying ? "pause.fill" : "play.fill",
                          filled: true, tint: accent,
                          label: spotify.isPlaying ? "Pause" : "Play") { spotify.playPause() }
                RoundIcon(symbol: "forward.fill", filled: false, tint: accent, label: "Next track") { spotify.next() }
                if spotify.isPlaying {
                    EqualizerBars(color: spotify.accent).scaleEffect(0.72).frame(width: 16)
                }
            }
        } else {
            RoundIcon(symbol: "arrow.up.forward", filled: false, tint: accent, label: "Open Spotify") {
                spotify.openApp(); state.collapseNow()
            }
        }
    }

    /// Thin line across the bottom of the card; only ticks while playing.
    private var progress: some View {
        TimelineView(.periodic(from: .now, by: spotify.isPlaying ? 1 : 3600)) { _ in
            let dur = max(spotify.track?.duration ?? 1, 1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(accent)
                        .frame(width: geo.size.width * CGFloat(min(spotify.position / dur, 1)))
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: Rows

    private var clockRow: some View {
        Card(tint: clock.timerFired ? .red : .orange, action: { state.tab = .clock }) {
            HStack(spacing: 8) {
                Image(systemName: clock.timerRunning || clock.timerFired ? "timer" : "stopwatch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(clock.timerFired ? .red : .orange)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(readout)
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(clock.timerFired ? .red : .white)
                }
                Text(clock.timerFired ? "Time's up" : (clock.timerRunning ? "Timer" : "Stopwatch"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 0)
                RoundIcon(symbol: clock.timerFired ? "checkmark" : "pause.fill", filled: false, tint: .orange,
                          label: clock.timerFired ? "Dismiss" : "Pause") {
                    if clock.timerRunning || clock.timerFired { clock.timerToggle() } else { clock.stopwatchToggle() }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private var readout: String {
        guard let r = clock.pillReadout else { return "" }
        switch r {
        case .timer(let t): return ClockStore.format(t)
        case .stopwatch(let t): return ClockStore.format(t)
        case .fired: return "00:00"
        }
    }

    private var mac: (percent: Int, charging: Bool)? {
        if let d = devices.devices.first(where: { $0.kind == .macBattery }), let b = d.batteries.first {
            return (b.percent, d.detail.hasPrefix("Charging"))
        }
        return Battery.read().map { ($0.percent, $0.charging) }
    }

    private var devicesRow: some View {
        // A wash of colour when there's something to notice: charging, or low.
        Card(tint: mac.flatMap { $0.charging ? .green : ($0.percent <= 20 ? .red : nil) },
             action: { state.tab = .devices }) {
            HStack(spacing: 10) {
                if let mac {
                    HStack(spacing: 6) {
                        BatteryMeter(percent: mac.percent, charging: mac.charging)
                        Text("\(mac.percent)%")
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                let bt = devices.devices.filter { $0.kind != .macBattery && $0.kind != .display && $0.kind != .charger }
                if bt.isEmpty {
                    Text(mac?.charging == true ? "Charging" : "No devices")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                } else {
                    ForEach(bt.prefix(2)) { d in
                        HStack(spacing: 4) {
                            Image(systemName: d.symbol).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                            if !d.batteries.isEmpty {
                                Text(d.batteries.map { "\($0.percent)" }.joined(separator: "/") + "%")
                                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(batteryTint(d.batteries.map(\.percent).min() ?? 100))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 10)
        }
    }

    private func batteryTint(_ p: Int) -> Color {
        p <= 20 ? .red : (p <= 40 ? .orange : .white.opacity(0.85))
    }

    private var shelfRow: some View {
        Card(tint: nil, action: { state.tab = .shelf }) {
            HStack(spacing: 8) {
                if shelf.items.isEmpty {
                    Image(systemName: "tray").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Drop files on the notch")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                } else {
                    HStack(spacing: -7) {
                        ForEach(shelf.items.prefix(4)) { item in
                            Image(nsImage: shelf.thumbnail(for: item))
                                .resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(.black.opacity(0.6), lineWidth: 1))
                        }
                    }
                    Text("\(shelf.items.count) file\(shelf.items.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                if !shelf.items.isEmpty {
                    RoundIcon(symbol: "airplayaudio", filled: false, tint: .blue, label: "AirDrop all") {
                        ShelfStore.airDrop(shelf.items.map(\.url))
                    }
                }
            }
            .padding(.horizontal, 10)
        }
    }
}

// MARK: - Pieces

/// Card with a hairline top highlight (the macOS material look) and an
/// optional colour wash bleeding in from the left.
private struct Card<Content: View>: View {
    let tint: Color?
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(hovering ? 0.095 : 0.06))
                    if let tint {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [tint.opacity(0.3), tint.opacity(0.02)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

private struct RoundIcon: View {
    let symbol: String
    let filled: Bool
    let tint: Color
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(filled ? .black.opacity(0.85) : .white.opacity(hovering ? 1 : 0.8))
                .frame(width: 24, height: 24)
                .background(Circle().fill(filled ? tint.opacity(0.95) : .white.opacity(hovering ? 0.2 : 0.12)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

/// Small drawn battery, so the row reads at a glance instead of as text.
private struct BatteryMeter: View {
    let percent: Int
    let charging: Bool

    private var tint: Color {
        if charging { return .green }
        return percent <= 20 ? .red : (percent <= 40 ? .orange : .white.opacity(0.9))
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.35), lineWidth: 1)
                    .frame(width: 22, height: 11)
                RoundedRectangle(cornerRadius: 1.5).fill(tint)
                    .frame(width: max(2, 19 * CGFloat(percent) / 100), height: 7.5)
                    .padding(.leading, 1.5)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black.opacity(0.75))
                        .frame(width: 22)
                }
            }
            Capsule().fill(.white.opacity(0.35)).frame(width: 2, height: 4)
        }
        .accessibilityHidden(true)
    }
}
