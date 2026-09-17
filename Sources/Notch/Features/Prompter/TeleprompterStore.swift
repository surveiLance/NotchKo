import Foundation

/// Script + playback state for the teleprompter. Scrolling is derived from a
/// wall-clock anchor, so nothing ticks unless the strip is on screen and
/// running (the view drives itself with a paused-when-idle TimelineView).
@MainActor
final class TeleprompterStore: ObservableObject {
    @Published var script: String { didSet { defaults.set(script, forKey: "prompter.script") } }
    /// Points per second.
    @Published var speed: Double { didSet { defaults.set(speed, forKey: "prompter.speed") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "prompter.fontSize") } }
    /// Mirror the text horizontally (for a physical beam-splitter rig).
    @Published var mirrored = false

    /// The wide reading strip is showing (panel pinned open).
    @Published private(set) var isPrompting = false
    @Published private(set) var isRunning = false

    private let defaults = UserDefaults.standard
    private var scrolledBase: Double = 0
    private var anchor = Date()

    init() {
        script = defaults.string(forKey: "prompter.script") ?? ""
        let s = defaults.double(forKey: "prompter.speed"); speed = s == 0 ? 28 : s
        let f = defaults.double(forKey: "prompter.fontSize"); fontSize = f == 0 ? 22 : f
    }

    var hasScript: Bool { !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Distance scrolled at `date`, in points.
    func scrolled(at date: Date = Date()) -> Double {
        isRunning ? scrolledBase + date.timeIntervalSince(anchor) * speed : scrolledBase
    }

    // MARK: Controls

    func begin() {
        guard hasScript else { return }
        scrolledBase = 0
        isPrompting = true
        isRunning = false
    }

    func play() {
        guard isPrompting, !isRunning else { return }
        anchor = Date()
        isRunning = true
    }

    func pause() {
        guard isRunning else { return }
        scrolledBase = scrolled()
        isRunning = false
    }

    func togglePlay() { isRunning ? pause() : play() }

    func restart() {
        scrolledBase = 0
        anchor = Date()
    }

    /// Manual nudge (scroll wheel / buttons), works while paused or playing.
    func nudge(by points: Double) {
        scrolledBase = max(0, scrolled() + points)
        anchor = Date()
    }

    func setSpeed(_ v: Double) {
        // Re-anchor so the change doesn't jump the text.
        scrolledBase = scrolled(); anchor = Date()
        speed = min(max(v, 6), 120)
    }

    /// Called by the view when the text has scrolled fully past.
    func reachedEnd() { pause() }

    func end() {
        pause()
        isPrompting = false
    }
}
