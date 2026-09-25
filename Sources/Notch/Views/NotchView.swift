import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var spotify: SpotifyClient
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var clock: ClockStore
    @ObservedObject var prompter: TeleprompterStore
    let notchSize: CGSize

    init(state: NotchState, notchSize: CGSize) {
        self.state = state
        self.spotify = state.spotify
        self.shelf = state.shelf
        self.clock = state.clock
        self.prompter = state.prompter
        self.notchSize = notchSize
    }

    private var isOpen: Bool { state.isExpanded }
    private var notice: Notice? { isOpen ? nil : state.notice }
    private var hasNotice: Bool { notice != nil }
    private var hasWings: Bool { !isOpen && !hasNotice && state.wingWidth > 0 }

    private var tallNotice: Bool { (notice?.height ?? 0) > notchSize.height }

    /// Ears only appear when open or on a tall island; collapsed the shape hides under the real notch.
    private var topRadius: CGFloat { isOpen ? 14 : (tallNotice ? 10 : 0) }
    private var bottomRadius: CGFloat {
        if isOpen { return 22 }
        if tallNotice { return 24 }
        if hasNotice { return notchSize.height / 2 }
        return hasWings ? 14 : 10
    }

    private var size: CGSize {
        if isOpen { return state.expandedSize }
        let wing = notice?.wing ?? state.wingWidth
        return CGSize(width: notchSize.width + 2 * wing, height: notice?.height ?? notchSize.height)
    }

    var body: some View {
        // Everything sits inside one frame that animates between the collapsed,
        // notice and expanded sizes, and is clipped to the notch silhouette —
        // so content is carried (and cropped) by the black as it moves.
        ZStack(alignment: .top) {
            NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(.black)

            if isOpen && state.isPrompting {
                PrompterStripView(prompter: prompter, state: state, notchSize: notchSize)
                    .padding(.horizontal, topRadius)
                    .frame(width: Motion.prompterSize.width, height: Motion.prompterSize.height, alignment: .top)
                    .transition(.opacity.animation(.easeOut(duration: 0.25).delay(0.1)))
            } else if isOpen {
                VStack(spacing: 0) {
                    header.frame(height: notchSize.height)
                    content
                        .frame(maxWidth: .infinity)
                        .frame(height: state.expandedSize.height - notchSize.height - 6 - 14, alignment: .top)
                        .clipped()
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                        .padding(.bottom, 14)
                }
                .padding(.horizontal, topRadius)
                .frame(width: state.expandedSize.width, height: state.expandedSize.height, alignment: .top)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                        .animation(.easeOut(duration: 0.22).delay(0.05)),
                    removal: .opacity.animation(.easeOut(duration: 0.08))
                ))
            } else if let notice {
                Group {
                    if notice == .greeting {
                        GreetingView(notchWidth: notchSize.width, wing: Motion.greetWing - topRadius)
                            .transition(.opacity.animation(.easeOut(duration: 0.25)))
                    } else {
                        NoticeView(notice: notice, notchWidth: notchSize.width, wing: notice.wing)
                            .transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.08)))
                    }
                }
                .frame(width: size.width, height: size.height)
            } else {
                // Always present so its wing widths animate with the pill:
                // artwork and equalizer get squeezed into the notch on pause
                // rather than lingering while the black shrinks around them.
                CollapsedWingsView(spotify: spotify, clock: clock, notchWidth: notchSize.width,
                                   wing: state.wingWidth, contentWing: state.wingContentWidth)
                    .frame(width: size.width, height: size.height)
                    .opacity(hasWings ? 1 : 0)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 0) {
            // Left strip: tabs hug the notch.
            HStack(spacing: 2) {
                TabButton(symbol: "square.grid.2x2.fill", active: state.tab == .home, label: "Overview") { state.tab = .home }
                TabButton(symbol: "music.note", active: state.tab == .music, label: "Now Playing") { state.tab = .music }
                TabButton(symbol: "tray.fill", active: state.tab == .shelf, badge: shelf.items.count, label: "Shelf, \(shelf.items.count) files") { state.tab = .shelf }
                TabButton(symbol: "person.crop.square", active: state.tab == .mirror, label: "Mirror") { state.tab = .mirror }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Spacer().frame(width: notchSize.width + 2 * Motion.tabNotchGap)

            // Right strip: tabs hug the notch.
            HStack(spacing: 2) {
                TabButton(symbol: "timer", active: state.tab == .clock, dot: clock.isActive, label: "Stopwatch and timer") { state.tab = .clock }
                TabButton(symbol: "cable.connector.horizontal", active: state.tab == .devices, label: "Connected devices") { state.tab = .devices }
                TabButton(symbol: "text.alignleft", active: state.tab == .prompter, label: "Teleprompter") { state.tab = .prompter }
                TabButton(symbol: "wand.and.stars", active: state.tab == .tools, label: "Image tools") { state.tab = .tools }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.tab {
        case .home:
            OverviewView(state: state)
        case .shelf:
            ShelfView(shelf: shelf, state: state)
        case .clock:
            ClockView(clock: clock, state: state)
        case .devices:
            DevicesView(devices: state.devices)
        case .prompter:
            TeleprompterView(prompter: prompter, state: state)
        case .tools:
            ToolsView(shelf: shelf, state: state)
        case .mirror:
            MirrorView(camera: state.camera)
        case .music:
            if spotify.track != nil {
                NowPlayingView(spotify: spotify) { state.collapseNow() }
            } else {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: "music.note")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Play something in Spotify")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct TabButton: View {
    let symbol: String
    let active: Bool
    var badge: Int = 0
    var dot: Bool = false
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(active ? 1 : (hovering ? 0.8 : 0.45)))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(active ? 0.16 : (hovering ? 0.08 : 0))))
                .overlay(alignment: .topTrailing) {
                    if dot {
                        Circle().fill(.orange).frame(width: 6, height: 6).offset(x: 1, y: 2)
                    } else if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Capsule().fill(.white))
                            .offset(x: 5, y: -1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}
