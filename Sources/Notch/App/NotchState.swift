import AppKit
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
    let camera: CameraController
    let tabs: TabSettings
    let motion: MotionSettings

    /// Order here is the order they appear in the strip.
    enum Tab: String, CaseIterable, Identifiable {
        case home, music, shelf, mirror, clock, devices, prompter, tools
        var id: String { rawValue }

        enum Side { case left, right }

        var title: String {
            switch self {
            case .home: return "Overview"
            case .music: return "Music"
            case .shelf: return "Shelf"
            case .mirror: return "Mirror"
            case .clock: return "Timer"
            case .devices: return "Devices"
            case .prompter: return "Teleprompter"
            case .tools: return "Image tools"
            }
        }

        var symbol: String {
            switch self {
            case .home: return "square.grid.2x2.fill"
            case .music: return "music.note"
            case .shelf: return "tray.fill"
            case .mirror: return "person.crop.square"
            case .clock: return "timer"
            case .devices: return "cable.connector.horizontal"
            case .prompter: return "text.alignleft"
            case .tools: return "wand.and.stars"
            }
        }

        var blurb: String {
            switch self {
            case .home: return "Everything at a glance"
            case .music: return "Spotify controls and artwork"
            case .shelf: return "Park files, AirDrop, scan text"
            case .mirror: return "Camera self-check"
            case .clock: return "Stopwatch and timer"
            case .devices: return "AirPods and battery levels"
            case .prompter: return "Read a script under the camera"
            case .tools: return "Convert, compress, cut out"
            }
        }

        /// The overview is the landing tab and can't be switched off.
        var isRequired: Bool { self == .home }
    }
    private var lastDrop = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    init(services: Services) {
        spotify = services.spotify
        shelf = services.shelf
        clock = services.clock
        devices = services.devices
        prompter = services.prompter
        camera = services.camera
        tabs = services.tabs
        motion = services.motion

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
        else if awaitingEnter || isPrompting || scanTarget != nil || isChoosingTabs { return }   // these pin the panel open
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
    /// Image being scanned for text, if any — takes over the panel while set.
    @Published private(set) var scanTarget: URL?
    /// Tab picker is showing.
    @Published private(set) var isChoosingTabs = false
    /// Width of this display's notch, set by the panel — the tab strips have
    /// to fit either side of it.
    @Published var notchWidth: CGFloat = 179

    var expandedSize: CGSize {
        if isPrompting { return Motion.prompterSize }
        if scanTarget != nil { return Motion.scanSize }
        if isChoosingTabs { return Motion.setupSize }
        let height = tab == .mirror ? Motion.mirrorSize.height : Motion.expandedSize.height
        return CGSize(width: max(Motion.expandedSize.width, widthForTabs), height: height)
    }

    /// Enough width that both strips fit beside the notch without crowding.
    private var widthForTabs: CGFloat {
        let left = CGFloat(tabs.ordered(on: .left).count) * Motion.tabSlot
        // The right strip also carries the settings button.
        let right = CGFloat(tabs.ordered(on: .right).count) * Motion.tabSlot + Motion.settingsSlot
        let side = max(left, right) + Motion.stripPadding
        return notchWidth + 2 * Motion.tabNotchGap + 2 * side
    }

    /// Open an image in the scan view (crop a region, read the text).
    /// Expands directly — going through toggle() would see the new target
    /// and close the scan again.
    func startScan(_ url: URL) {
        pending?.cancel()
        awaitingEnter = true
        withAnimation(Motion.expand) {
            scanTarget = url
            isExpanded = true
        }
    }

    func endScan() {
        guard scanTarget != nil else { return }
        withAnimation(Motion.collapse) { scanTarget = nil }
    }

    /// Open the tab picker (first run, or from the menu bar).
    func startSetup() {
        pending?.cancel()
        awaitingEnter = true
        withAnimation(Motion.expand) {
            isChoosingTabs = true
            isExpanded = true
        }
    }

    func endSetup() {
        guard isChoosingTabs else { return }
        withAnimation(Motion.collapse) { isChoosingTabs = false }
        if !tabs.isOn(tab) { tab = .home }
    }

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
        if isChoosingTabs { endSetup(); return }
        if scanTarget != nil { endScan(); return }
        if isPrompting { stopPrompter(toEditor: false); return }
        awaitingEnter = !isExpanded
        withAnimation(isExpanded ? Motion.collapse : Motion.expand) { isExpanded.toggle() }
    }

    func collapseNow() {
        pending?.cancel()
        keyboardWanted = false
        scanTarget = nil
        isChoosingTabs = false
        if isPrompting { prompter.end(); isPrompting = false }
        withAnimation(Motion.collapse) { isExpanded = false }
    }

    func preview(_ urls: [URL]) { previewHandler?(urls) }
}

/// Tunables for feel. The springs scale with the user's chosen speed, and
/// collapse to short fades when macOS "Reduce motion" is on.
enum Motion {
    enum Speed: String, CaseIterable, Identifiable {
        case fast, normal, relaxed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fast: return "Fast"
            case .normal: return "Normal"
            case .relaxed: return "Relaxed"
            }
        }
        /// Multiplies every duration and delay.
        var scale: Double {
            switch self {
            case .fast: return 0.6
            case .normal: return 1
            case .relaxed: return 1.5
            }
        }
    }

    /// Only ever written from the main actor (the settings store).
    nonisolated(unsafe) static var speed: Speed = .normal

    /// macOS Accessibility → Display → Reduce motion.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static var k: Double { speed.scale }

    private static func spring(_ response: Double, _ damping: Double) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.12 * k)
            : .spring(response: response * k, dampingFraction: damping)
    }

    // Opening is "snappy with a hint of life", closing near-rigid.
    static var expand: Animation   { spring(0.38, 0.74) }
    static var collapse: Animation { spring(0.30, 0.92) }
    static var wings: Animation    { spring(0.40, 0.75) }
    static var wingsOut: Animation { spring(0.36, 0.95) }
    // Login greeting: bouncy out, smooth glide back.
    static var greetIn: Animation  { spring(0.55, 0.58) }
    static var greetOut: Animation { spring(0.60, 0.85) }
    // Charger / bluetooth pops: quick and crisp.
    static var noticeIn: Animation  { spring(0.32, 0.72) }
    static var noticeOut: Animation { spring(0.35, 0.90) }

    static var openDelay: TimeInterval  { 0.3 * k }   // linger before opening
    static var closeDelay: TimeInterval { 0.18 * k }
    static var reopenCooldown: TimeInterval { 0.9 * k }
    static var greetHold: TimeInterval { 3.6 }
    /// How long to wait for a collapse to settle before shrinking the window.
    static var settle: TimeInterval { reduceMotion ? 0.14 * k : 0.5 * k }

    static let expandedSize = CGSize(width: 500, height: 160)
    static let wingWidth: CGFloat = 36
    static let wingWidthClock: CGFloat = 60
    /// Transparent slack either side of the collapsed pill that still catches drags/hover.
    static let catchMargin: CGFloat = 8
    /// Space between the notch and the nearest tab on each side.
    static let tabNotchGap: CGFloat = 10
    /// One tab button plus its spacing, the settings button plus its gap, and
    /// the breathing room at the outer edge of each strip.
    static let tabSlot: CGFloat = 28
    static let settingsSlot: CGFloat = 36
    static let stripPadding: CGFloat = 12
    static let greetWing: CGFloat = 176
    static let greetHeight: CGFloat = 64
    /// Teleprompter strip: wide and a touch taller so 3–4 lines sit under the camera.
    static let prompterSize = CGSize(width: 660, height: 176)
    /// Mirror: same width as every other tab so the tab strips never reflow,
    /// just taller so the 16:9 preview is big enough to check yourself in.
    static let mirrorSize = CGSize(width: expandedSize.width, height: 300)
    /// Scan: wide and tall enough to pick a region out of a screenshot.
    static let scanSize = CGSize(width: 700, height: 330)
    /// Tab picker: two columns of choices.
    static let setupSize = CGSize(width: 620, height: 340)
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
