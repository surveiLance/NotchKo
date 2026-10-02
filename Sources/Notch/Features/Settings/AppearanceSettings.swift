import Foundation
import Combine

/// Look-and-feel preferences that aren't about motion.
@MainActor
final class AppearanceSettings: ObservableObject {
    /// Tint the music surfaces with the current artwork's dominant colour.
    @Published var artworkColour: Bool {
        didSet { UserDefaults.standard.set(artworkColour, forKey: key) }
    }

    private let key = "appearance.artworkColour"

    init() {
        artworkColour = UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
