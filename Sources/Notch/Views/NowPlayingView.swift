import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var spotify: SpotifyClient
    var onOpenApp: () -> Void = {}
    @State private var artHover = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            artwork
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(artHover ? 0.45 : 0))
                        .overlay {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .opacity(artHover ? 1 : 0)
                        }
                }
                .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
                .scaleEffect(artHover ? 1.03 : 1)
                .animation(.easeOut(duration: 0.15), value: artHover)
                .onHover { artHover = $0 }
                .onTapGesture { spotify.openApp(); onOpenApp() }
                .help("Open in Spotify")
                .accessibilityLabel("Album artwork. Click to open Spotify.")
                .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 0) {
                Text(spotify.track?.name ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(spotify.track?.artist ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .padding(.top, 2)

                controls
                    .padding(.vertical, 6)

                progress
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { spotify.refreshModes() }
    }

    private var accent: Color { Color(nsColor: spotify.accent) }

    @ViewBuilder
    private var artwork: some View {
        if let image = spotify.artwork {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.white.opacity(0.3)))
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            ModeButton(symbol: "shuffle", on: spotify.shuffling, accent: accent, label: "Shuffle") { spotify.toggleShuffle() }
            TransportButton(symbol: "backward.fill", size: 15, label: "Previous track") { spotify.previous() }
            TransportButton(symbol: spotify.isPlaying ? "pause.fill" : "play.fill", size: 20,
                            label: spotify.isPlaying ? "Pause" : "Play") { spotify.playPause() }
            TransportButton(symbol: "forward.fill", size: 15, label: "Next track") { spotify.next() }
            ModeButton(symbol: "repeat", on: spotify.repeating, accent: accent, label: "Repeat") { spotify.toggleRepeat() }
        }
        .frame(maxWidth: .infinity)
    }

    /// Scrubbable progress. Only ticks while this view is on screen (i.e. the
    /// notch is open and something is playing). Closed notch = no timer.
    private var progress: some View {
        TimelineView(.periodic(from: .now, by: spotify.isPlaying ? 1 : 3600)) { _ in
            Scrubber(position: spotify.position,
                     duration: max(spotify.track?.duration ?? 1, 1),
                     accent: accent) { spotify.seek(to: $0) }
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Click anywhere on the bar to jump, or drag the knob. The bar grows and
/// the knob appears on hover so it's obvious it's interactive.
private struct Scrubber: View {
    let position: TimeInterval
    let duration: TimeInterval
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    @State private var hovering = false
    @State private var dragFraction: Double? = nil

    private var fraction: Double { dragFraction ?? (position / duration) }
    private var active: Bool { hovering || dragFraction != nil }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(active ? 0.22 : 0.15))
                    Capsule().fill(accent).frame(width: w * CGFloat(fraction))
                    Circle()
                        .fill(.white)
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .offset(x: w * CGFloat(fraction) - 5.5)
                        .opacity(active ? 1 : 0)
                }
                .frame(height: active ? 6 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in dragFraction = min(max(0, v.location.x / w), 1) }
                        .onEnded { v in
                            let f = min(max(0, v.location.x / w), 1)
                            onSeek(f * duration)
                            // Keep showing the dragged spot until Spotify catches up.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dragFraction = nil }
                        }
                )
            }
            .frame(height: 14)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: active)

            HStack {
                Text(format(fraction * duration))
                Spacer()
                Text("-" + format(duration - fraction * duration))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress \(format(position)) of \(format(duration))")
        .accessibilityValue("\(Int(fraction * 100)) percent")
        .accessibilityAdjustableAction { dir in
            onSeek(position + (dir == .increment ? 10 : -10))
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(max(0, t).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct ModeButton: View {
    let symbol: String
    let on: Bool
    let accent: Color
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(on ? accent : .white.opacity(hovering ? 0.8 : 0.4))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
                .overlay(alignment: .bottom) {
                    Circle().fill(accent).frame(width: 3, height: 3).opacity(on ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
    }
}

private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(label)
    }
}

/// The Dynamic-Island-style collapsed state: artwork on the left wing,
/// a small equaliser on the right. The equaliser is a plain Core Animation
/// scale loop on four tiny layers — the only thing that animates while the
/// notch is closed, and only while music is actually playing.
struct CollapsedWingsView: View {
    @ObservedObject var spotify: SpotifyClient
    @ObservedObject var clock: ClockStore
    let notchWidth: CGFloat
    let wing: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            leftWing.frame(width: wing)
            Spacer().frame(width: notchWidth)
            rightWing.frame(width: wing)
        }
        .frame(maxHeight: .infinity)
    }

    /// Artwork if music is playing, otherwise the clock glyph.
    @ViewBuilder
    private var leftWing: some View {
        if spotify.isPlaying {
            Group {
                if let image = spotify.artwork {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else if let readout = clock.pillReadout {
            Image(systemName: {
                switch readout {
                case .timer, .fired: return "timer"
                case .stopwatch: return "stopwatch"
                }
            }())
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(clockTint(readout))
        }
    }

    /// Timer/stopwatch digits win; otherwise the music state.
    @ViewBuilder
    private var rightWing: some View {
        if let readout = clock.pillReadout {
            // 1 Hz text update while a clock runs and the notch is closed.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text({
                    switch readout {
                    case .timer:     return ClockStore.format(clock.timerRemaining)
                    case .stopwatch: return ClockStore.format(clock.stopwatchElapsed)
                    case .fired:     return "00:00"
                    }
                }())
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(clockTint(readout))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        } else if spotify.isPlaying {
            EqualizerBars(color: spotify.accent)
        }
    }

    private func clockTint(_ r: ClockStore.PillReadout) -> Color {
        switch r {
        case .fired: return .red
        case .timer: return .orange
        case .stopwatch: return .white.opacity(0.9)
        }
    }
}


/// Four bars driven by CABasicAnimation. Core Animation runs this out of
/// process in the render server, so the app itself uses ~0% CPU while it
/// bounces (SwiftUI's own animation would cost ~7% on the main thread).
struct EqualizerBars: NSViewRepresentable {
    var color: NSColor
    func makeNSView(context: Context) -> EqualizerLayerView { EqualizerLayerView(color: color) }
    func updateNSView(_ view: EqualizerLayerView, context: Context) { view.color = color }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerLayerView, context: Context) -> CGSize? {
        CGSize(width: EqualizerLayerView.width, height: EqualizerLayerView.height)
    }
}

final class EqualizerLayerView: NSView {
    static let width: CGFloat = 18
    static let height: CGFloat = 14
    private static let bars: [(duration: Double, low: CGFloat)] = [
        (0.55, 0.30), (0.42, 0.45), (0.65, 0.25), (0.48, 0.50)
    ]

    var color: NSColor {
        didSet { layer?.sublayers?.forEach { $0.backgroundColor = color.cgColor } }
    }

    init(color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        wantsLayer = true
        layer?.masksToBounds = false
        let barW: CGFloat = 3, gap: CGFloat = 2
        for (i, bar) in Self.bars.enumerated() {
            let l = CALayer()
            l.backgroundColor = color.cgColor
            l.cornerRadius = barW / 2
            l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            l.bounds = CGRect(x: 0, y: 0, width: barW, height: Self.height)
            l.position = CGPoint(x: CGFloat(i) * (barW + gap) + barW / 2, y: Self.height / 2)
            layer?.addSublayer(l)

            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = bar.low
            a.toValue = 1.0
            a.duration = bar.duration
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.beginTime = CACurrentMediaTime() + Double(i) * 0.07
            l.add(a, forKey: "bounce")
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: Self.width, height: Self.height) }
}
