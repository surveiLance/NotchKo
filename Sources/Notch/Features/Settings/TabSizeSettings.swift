import CoreGraphics
import Combine
import Foundation

/// How large the panel opens for each tab. Some tabs want room (agents, the
/// mirror), others are better small, so the choice is per tab.
@MainActor
final class TabSizeSettings: ObservableObject {
    typealias Tab = NotchState.Tab

    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var title: String {
            switch self {
            case .small: return "S"
            case .medium: return "M"
            case .large: return "L"
            }
        }
        var scale: CGFloat {
            switch self {
            case .small: return 0.84
            case .medium: return 1
            case .large: return 1.3
            }
        }
    }

    @Published private(set) var sizes: [String: String] {
        didSet { UserDefaults.standard.set(sizes, forKey: key) }
    }

    private let key = "tabs.sizes"

    init() {
        sizes = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    func size(for tab: Tab) -> Size {
        sizes[tab.rawValue].flatMap(Size.init(rawValue:)) ?? .medium
    }

    func set(_ tab: Tab, _ size: Size) {
        sizes[tab.rawValue] = size.rawValue
    }
}
