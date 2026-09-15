import AppKit
import Combine

/// Stopwatch + countdown timer. Nothing ticks in here: elapsed/remaining are
/// derived from wall-clock anchors, and the timer's end is a single scheduled
/// callback. Views that want a live readout use a TimelineView, which only
/// exists while they're on screen.
@MainActor
final class ClockStore: ObservableObject {
    // MARK: Stopwatch
    @Published private(set) var stopwatchRunning = false
    private var swAccumulated: TimeInterval = 0
    private var swStart: Date?

    var stopwatchElapsed: TimeInterval {
        swAccumulated + (swStart.map { Date().timeIntervalSince($0) } ?? 0)
    }
    var stopwatchHasValue: Bool { stopwatchRunning || swAccumulated > 0 }

    func stopwatchToggle() {
        if stopwatchRunning {
            swAccumulated = stopwatchElapsed
            swStart = nil
        } else {
            swStart = Date()
        }
        stopwatchRunning.toggle()
        updateActive()
    }

    func stopwatchReset() {
        swAccumulated = 0; swStart = nil; stopwatchRunning = false
        updateActive()
    }

    // MARK: Timer
    @Published private(set) var timerDuration: TimeInterval = 5 * 60
    @Published private(set) var timerRunning = false
    @Published private(set) var timerFired = false
    private var timerEnd: Date?
    private var timerPausedRemaining: TimeInterval?
    private var fireWork: DispatchWorkItem?

    /// Called on the main actor when the countdown hits zero.
    var onTimerFired: (() -> Void)?

    var timerRemaining: TimeInterval {
        if let timerEnd, timerRunning { return max(0, timerEnd.timeIntervalSinceNow) }
        return timerPausedRemaining ?? timerDuration
    }
    var timerHasValue: Bool { timerRunning || timerPausedRemaining != nil || timerFired }

    func timerToggle() {
        if timerFired { timerReset(); return }
        if timerRunning {
            timerPausedRemaining = timerRemaining
            timerEnd = nil
            fireWork?.cancel()
            timerRunning = false
        } else {
            let remaining = timerPausedRemaining ?? timerDuration
            guard remaining > 0 else { return }
            timerEnd = Date().addingTimeInterval(remaining)
            timerPausedRemaining = nil
            timerRunning = true
            scheduleFire(in: remaining)
        }
        updateActive()
    }

    func timerReset() {
        fireWork?.cancel()
        timerEnd = nil; timerPausedRemaining = nil
        timerRunning = false; timerFired = false
        updateActive()
    }

    /// Change the configured length (only meaningful while not running).
    func timerSet(_ seconds: TimeInterval) {
        guard !timerRunning else { return }
        timerDuration = max(60, min(seconds, 24 * 3600))
        timerPausedRemaining = nil
        timerFired = false
        updateActive()
    }

    func timerAdjust(by delta: TimeInterval) { timerSet(timerDuration + delta) }

    private func scheduleFire(in seconds: TimeInterval) {
        fireWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.timerRunning else { return }
            self.timerRunning = false
            self.timerEnd = nil
            self.timerFired = true
            self.updateActive()
            NSSound(named: "Glass")?.play()
            self.onTimerFired?()
        }
        fireWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Shared

    /// True when something is worth showing in the collapsed pill.
    @Published private(set) var isActive = false
    private func updateActive() { isActive = stopwatchRunning || timerRunning || timerFired }

    /// What the pill shows: the timer wins over the stopwatch.
    enum PillReadout { case timer(TimeInterval), stopwatch(TimeInterval), fired }
    var pillReadout: PillReadout? {
        if timerFired { return .fired }
        if timerRunning { return .timer(timerRemaining) }
        if stopwatchRunning { return .stopwatch(stopwatchElapsed) }
        return nil
    }

    /// Accepts "25" (minutes), "1:30", "1:05:00", "90s", "1h20m", "45m", "2h".
    nonisolated static func parse(_ raw: String) -> TimeInterval? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        if s.contains(":") {
            let parts = s.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.allSatisfy({ $0 != nil }) else { return nil }
            let v = parts.map { $0! }
            switch v.count {
            case 2: return v[0] * 60 + v[1]
            case 3: return v[0] * 3600 + v[1] * 60 + v[2]
            default: return nil
            }
        }
        if s.last!.isLetter {
            var total = 0.0, num = ""
            for ch in s {
                if ch.isNumber || ch == "." { num.append(ch); continue }
                guard let n = Double(num) else { return nil }
                switch ch {
                case "h": total += n * 3600
                case "m": total += n * 60
                case "s": total += n
                default: return nil
                }
                num = ""
            }
            return num.isEmpty ? total : nil
        }
        return Double(s).map { $0 * 60 }
    }

    nonisolated static func format(_ t: TimeInterval, tenths: Bool = false) -> String {
        let total = max(0, t)
        let h = Int(total) / 3600, m = (Int(total) % 3600) / 60, s = Int(total) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        if tenths {
            let d = Int((total - floor(total)) * 10)
            return String(format: "%02d:%02d.%d", m, s, d)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
