import Foundation

/// The one-per-app backends every notch panel shares (there's one panel per
/// display, but only one Spotify, one shelf, one clock).
@MainActor
final class Services {
    let spotify = SpotifyClient()
    let shelf = ShelfStore()
    let clock = ClockStore()
    let devices = DevicesStore()
    let prompter = TeleprompterStore()
    let camera = CameraController()
}
