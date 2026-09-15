import AppKit
import SwiftUI

/// Transparent overlay that turns a SwiftUI view into an AppKit drag source
/// able to carry several files at once (SwiftUI's .onDrag is one item only).
/// A click without movement is a tap; right-click asks for removal.
struct MultiFileDragSource: NSViewRepresentable {
    var urls: () -> [URL]
    var onTap: () -> Void
    var onRemove: () -> Void
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let v = DragSourceView()
        update(v)
        return v
    }
    func updateNSView(_ v: DragSourceView, context: Context) { update(v) }
    private func update(_ v: DragSourceView) {
        v.urls = urls; v.onTap = onTap; v.onRemove = onRemove; v.onHover = onHover
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var urls: () -> [URL] = { [] }
    var onTap: () -> Void = {}
    var onRemove: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    private var downPoint: NSPoint?
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent)  { onHover(false) }

    override func mouseDown(with event: NSEvent) { downPoint = event.locationInWindow }

    override func mouseUp(with event: NSEvent) {
        if downPoint != nil { onTap() }
        downPoint = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Remove from Shelf", action: #selector(removeAction), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func removeAction() { onRemove() }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        downPoint = nil

        let payload = urls()
        guard !payload.isEmpty else { return }
        let local = convert(event.locationInWindow, from: nil)
        let items = payload.enumerated().map { (i, url) -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            // Fan the icons out slightly so a multi-drag reads as a stack.
            let off = CGFloat(min(i, 4)) * 3
            item.setDraggingFrame(
                NSRect(x: local.x - 24 + off, y: local.y - 24 - off, width: 48, height: 48),
                contents: icon
            )
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }
}
