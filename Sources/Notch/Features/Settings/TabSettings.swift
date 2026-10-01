import Foundation
import Combine
import CoreGraphics

/// Which tabs the user wants in their notch. Everything is optional except
/// the overview, so the panel stays as small as each person needs it.
@MainActor
final class TabSettings: ObservableObject {
    typealias Tab = NotchState.Tab

    @Published private(set) var enabled: Set<Tab> {
        didSet { defaults.set(enabled.map(\.rawValue), forKey: enabledKey) }
    }
    /// False until the picker has been dismissed once.
    @Published private(set) var hasChosen: Bool {
        didSet { defaults.set(hasChosen, forKey: chosenKey) }
    }

    private let defaults = UserDefaults.standard
    private let enabledKey = "tabs.enabled"
    private let chosenKey = "tabs.hasChosen"

    /// A light starting point — the rest are opt-in from the picker.
    static let starter: Set<Tab> = [.home, .music, .shelf, .clock]

    init() {
        hasChosen = defaults.bool(forKey: chosenKey)
        if let raw = defaults.stringArray(forKey: enabledKey) {
            enabled = Set(raw.compactMap(Tab.init(rawValue:)))
        } else {
            enabled = Self.starter
        }
        enabled.formUnion(Tab.allCases.filter(\.isRequired))
    }

    /// Enabled tabs in display order.
    var ordered: [Tab] { Tab.allCases.filter(isOn) }

    /// Split evenly down the middle so both strips stay balanced however many
    /// tabs are switched on (a fixed left/right assignment leaves one side
    /// stranded when most are off).
    func ordered(on side: Tab.Side) -> [Tab] {
        let all = ordered
        let leftCount = Int(ceil(Double(all.count) / 2))
        return side == .left ? Array(all.prefix(leftCount)) : Array(all.dropFirst(leftCount))
    }

    func isOn(_ tab: Tab) -> Bool { tab.isRequired || enabled.contains(tab) }

    func set(_ tab: Tab, _ on: Bool) {
        guard !tab.isRequired else { return }
        if on { enabled.insert(tab) } else { enabled.remove(tab) }
    }

    func toggle(_ tab: Tab) { set(tab, !isOn(tab)) }

    func markChosen() { hasChosen = true }
}
