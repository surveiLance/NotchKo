import SwiftUI
import Combine

/// Single source of truth for the notch UI. Everything is event-driven:
/// nothing here polls or runs a timer while idle.
@MainActor
final class NotchState: ObservableObject {
    @Published private(set) var isExpanded = false
    /// Transient pill content (greeting, volume, charger…). Nil = normal pill.
    @Published private(set) var notice: Notice?
    var isGreeting: Bool { notice == .greeting }
    private var noticeHide: DispatchWorkItem?
    /// A text field in the notch wants keyboard focus; the panel becomes key only then.
    @Published var keyboardWanted = false
    /// Set by the panel: show a Quick Look preview of these files.
    var previewHandler: (([URL]) -> Void)?
    @Published var tab: Tab = .home
    /// Which zone a file drag is hovering over, if any.
    @Published private(set) var dropZone: DropZone?
    var isDragTargeted: Bool { dropZone != nil }
    /// AirDrop zone frame (SwiftUI global coords) reported by ShelfView.
    var airDropFrame: CGRect?
    enum DropZone { case shelf, airDrop }
    let spotify: SpotifyClient
    let shelf: ShelfStore
    let clock: ClockStore
    let devices: DevicesStore
    let prompter: TeleprompterStore

    enum Tab { case home, music, shelf, clock, devices, prompter, tools }
    private var lastDrop = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    init(services: Services) {
        spotify = services.spotify
        shelf = services.shelf
        clock = services.clock
        devices = services.devices
        prompter = services.prompter

        // Wings: *playing* music gets a narrow wing for artwork/equaliser (a
        // paused track hides, you don't need to see it); a running timer or
        // stopwatch needs room for digits.
        Publishers.CombineLatest(spotify.$isPlaying, clock.$isActive)
            .map { music, clock -> CGFloat in
                if clock { return Motion.wingWidthClock }
                if music { return Motion.wingWidth }
                return 0
            }
            .removeDuplicates()
            .sink { [weak self] w in
                guard let self else { return }
                if w > 0 { self.wingContentWidth = w }
                // Animate at the source so the shape and the wing frames ride
                // the same transaction.
                withAnimation(w > self.wingWidth ? Motion.wings : Motion.wingsOut) { self.wingWidth = w }
            }
            .store(in: &cancellables)

    }

    /// Timer hit zero: open on the clock tab; tuck away if nobody comes to look.
    func timerFired() {
        tab = .clock
        if !isExpanded { toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.awaitingEnter else { return }
            self.collapseNow()
        }
    }

    /// Extra width on each side of the notch while collapsed (the "wings"
    /// that show artwork / equaliser / timer digits).
    @Published private(set) var wingWidth: CGFloat = 0
    /// Last non-zero wing width, not animated: the wings' content is laid out
    /// at this width so it stays put and gets clipped as `wingWidth` animates.
    @Published private(set) var wingContentWidth: CGFloat = Motion.wingWidth

    /// Called by the panel's tracking area. Small delays so that a cursor
    /// merely passing over the notch doesn't pop it open, and a brief exit
    /// (e.g. moving between controls) doesn't slam it shut.
    private var pending: DispatchWorkItem?
    /// Set when opened by keyboard/menu: the window growing under a cursor
    /// that isn't over it synthesises a mouseExited we must ignore until the
    /// mouse has genuinely come in.
    private var awaitingEnter = false

    private var lastCollapse = Date.distantPast

    func setHovering(_ hovering: Bool) {
        if hovering { awaitingEnter = false }
        else if awaitingEnter || isPrompting { return }   // prompter pins the panel open
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !hovering { self.keyboardWanted = false; self.lastCollapse = Date() }
            withAnimation(hovering ? Motion.expand : Motion.collapse) {
                self.isExpanded = hovering
            }
        }
        pending = work
        // Opening: linger for openDelay, and longer if it only just closed —
        // so brushing past, or drifting back right after closing, doesn't count.
        let delay: TimeInterval
        if hovering {
            let cooldownLeft = Motion.reopenCooldown - Date().timeIntervalSince(lastCollapse)
            delay = max(Motion.openDelay, cooldownLeft)
        } else {
            delay = Motion.closeDelay
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// A file being dragged over the notch opens the shelf immediately.
    func setDragTargeted(_ zone: DropZone?) {
        dropZone = zone
        if zone != nil {
            pending?.cancel()
            awaitingEnter = false
            if tab != .tools { tab = .shelf }   // dropping while on Tools keeps you there
            withAnimation(Motion.expand) { isExpanded = true }
        } else if Date().timeIntervalSince(lastDrop) > 0.4 {
            setHovering(false)
        }
    }

    func didDrop() {
        lastDrop = Date()
        pending?.cancel()
        if tab != .tools { tab = .shelf }
    }

    /// Wide reading strip while the teleprompter runs; normal panel otherwise.
    @Published private(set) var isPrompting = false
    var expandedSize: CGSize { isPrompting ? Motion.prompterSize : Motion.expandedSize }

    func startPrompter() {
        guard prompter.hasScript else { return }
        keyboardWanted = false
        prompter.begin()
        withAnimation(Motion.expand) { isPrompting = true; isExpanded = true }
        // Give the strip a beat to appear, then roll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.prompter.play() }
    }

    func stopPrompter(toEditor: Bool) {
        prompter.end()
        withAnimation(Motion.collapse) {
            isPrompting = false
            if toEditor { tab = .prompter } else { isExpanded = false }
        }
    }

    /// Play the login greeting: bounce out into a wide pill, hold, glide back.
    func playGreeting() { show(.greeting) }

    /// Show a transient notice in the pill. Re-showing the same kind (e.g.
    /// repeated volume presses) just updates it and restarts the hold.
    func show(_ new: Notice) {
        guard !isExpanded else { return }
        noticeHide?.cancel()
        let sameKind = notice.map { $0.kind == new.kind } ?? false
        if sameKind {
            notice = new   // no spring: value tick only
        } else {
            withAnimation(new.kind == .greeting ? Motion.greetIn : Motion.noticeIn) { notice = new }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(self.notice?.kind == .greeting ? Motion.greetOut : Motion.noticeOut) { self.notice = nil }
        }
        noticeHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + new.hold, execute: work)
    }

    /// Keyboard / menu toggle. Opening this way pins the notch open until
    /// the mouse leaves it or it's toggled again.
    func toggle() {
        pending?.cancel()
        if isPrompting { stopPrompter(toEditor: false); return }
        awaitingEnter = !isExpanded
        withAnimation(isExpanded ? Motion.collapse : Motion.expand) { isExpanded.toggle() }
    }

    func collapseNow() {
        pending?.cancel()
        keyboardWanted = false
        if isPrompting { prompter.end(); isPrompting = false }
        withAnimation(Motion.collapse) { isExpanded = false }
    }

    func preview(_ urls: [URL]) { previewHandler?(urls) }
}

/// Tunables for feel. Adjust these and rebuild; nothing else needs to change.
enum Motion {
    // "Snappy with a hint of life" opening, "rigid" close — see spring guide.
    static let expand   = Animation.spring(response: 0.38, dampingFraction: 0.74)
    static let collapse = Animation.spring(response: 0.30, dampingFraction: 0.92)
    static let openDelay: TimeInterval  = 0.3    // pointer must linger this long to open
    static let closeDelay: TimeInterval = 0.18
    static let reopenCooldown: TimeInterval = 0.9 // after closing, re-entering waits this long

    static let expandedSize = CGSize(width: 500, height: 160)
    /// Teleprompter strip: wide and a touch taller so 3–4 lines sit under the camera.
    static let prompterSize = CGSize(width: 660, height: 176)
    /// Space between the notch and the nearest tab on each side.
    static let tabNotchGap: CGFloat = 10
    static let wingWidth: CGFloat = 36
    static let wingWidthClock: CGFloat = 60
    /// Transparent slack either side of the collapsed pill that still catches drags/hover.
    static let catchMargin: CGFloat = 8

    // Login greeting: "noticeable bounce, fun" out, "smooth glide" back.
    static let greetIn  = Animation.spring(response: 0.55, dampingFraction: 0.58)
    static let greetOut = Animation.spring(response: 0.6, dampingFraction: 0.85)
    static let greetHold: TimeInterval = 3.6
    static let greetWing: CGFloat = 176
    static let greetHeight: CGFloat = 64
    // Charger / bluetooth pops: quick and crisp.
    static let noticeIn  = Animation.spring(response: 0.32, dampingFraction: 0.72)
    static let noticeOut = Animation.spring(response: 0.35, dampingFraction: 0.9)
    static let wings    = Animation.spring(response: 0.4, dampingFraction: 0.75)   // appearing
    static let wingsOut = Animation.spring(response: 0.36, dampingFraction: 0.95)  // gliding back in
}


/// What the collapsed pill can temporarily turn into.
enum Notice: Equatable {
    case greeting
    case power(charging: Bool, percent: Int)
    case lowBattery(percent: Int)
    case bluetooth(name: String, connected: Bool, isAudio: Bool)
    /// Generic confirmation, e.g. "Copied · 124 words".
    case info(symbol: String, text: String)

    enum Kind { case greeting, power, lowBattery, bluetooth, info }
    var kind: Kind {
        switch self {
        case .greeting: return .greeting
        case .power: return .power
        case .lowBattery: return .lowBattery
        case .bluetooth: return .bluetooth
        case .info: return .info
        }
    }

    /// Width of each wing while this notice shows.
    var wing: CGFloat {
        switch self {
        case .greeting: return Motion.greetWing
        case .power, .lowBattery: return 96
        case .bluetooth, .info: return 120
        }
    }

    /// Island height; notch height for one-line pops, taller for the greeting.
    var height: CGFloat? {
        switch self {
        case .greeting: return Motion.greetHeight
        default: return nil
        }
    }

    var hold: TimeInterval {
        switch self {
        case .greeting: return Motion.greetHold
        case .power: return 2.4
        case .lowBattery: return 4
        case .bluetooth: return 2.6
        case .info: return 2
        }
    }
}
