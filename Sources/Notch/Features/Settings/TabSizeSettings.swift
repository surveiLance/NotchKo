import CoreGraphics
import Combine
import Foundation

/// How the panel decides its size.
@MainActor
final class TabSizeSettings: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        /// Each tab opens at the size its own content needs.
        case auto
        /// Every tab opens at the size the largest enabled tab needs, so the
        /// panel never changes size as you move between them.
        case uniform

        var id: String { rawValue }
        var title: String { self == .auto ? "Fit content" : "Same size" }
        var blurb: String {
            self == .auto
                ? "Each tab opens as big as it needs"
                : "Every tab opens the same size — the notch never resizes"
        }
    }

    @Published var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: key) }
    }

    private let key = "tabs.sizeMode"

    init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        mode = Mode(rawValue: raw) ?? .auto
    }
}
