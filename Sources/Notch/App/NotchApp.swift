import AppKit

@main
@MainActor
enum NotchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // belt-and-braces with LSUIElement
        app.run()
    }
}
