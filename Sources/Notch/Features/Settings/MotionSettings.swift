import AppKit
import Combine

/// How quickly the notch moves. Persisted, and pushed into `Motion` so every
/// spring and delay in the app follows it.
@MainActor
final class MotionSettings: ObservableObject {
    @Published var speed: Motion.Speed {
        didSet {
            Motion.speed = speed
            UserDefaults.standard.set(speed.rawValue, forKey: key)
        }
    }
    /// True when macOS Accessibility → Display → Reduce motion is on; the app
    /// then uses short fades whatever speed is chosen.
    @Published private(set) var systemReducesMotion = Motion.reduceMotion

    private let key = "motion.speed"

    init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        speed = Motion.Speed(rawValue: raw) ?? .normal
        Motion.speed = speed
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemReducesMotion = Motion.reduceMotion }
        }
    }
}
