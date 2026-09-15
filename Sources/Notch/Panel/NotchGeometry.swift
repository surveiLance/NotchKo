import AppKit

/// Where the (physical or simulated) notch is, in screen coordinates.
struct NotchGeometry {
    let screen: NSScreen
    let notchSize: CGSize
    let hasRealNotch: Bool

    /// Size of the virtual notch drawn on displays without a physical one.
    static let virtualWidth: CGFloat = 170

    static func detect(for screen: NSScreen) -> NotchGeometry {
        if screen.safeAreaInsets.top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let width = screen.frame.width - left - right
            return NotchGeometry(
                screen: screen,
                notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                hasRealNotch: true
            )
        }
        // External / notchless: a black pill the height of that screen's menu bar.
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(
            screen: screen,
            notchSize: CGSize(width: virtualWidth, height: menuBarHeight > 0 ? menuBarHeight : 25),
            hasRealNotch: false
        )
    }

    /// Panel frame for a given content size, top-centred on the screen.
    func frame(for size: CGSize) -> NSRect {
        let f = screen.frame
        return NSRect(
            x: f.midX - size.width / 2,
            y: f.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
