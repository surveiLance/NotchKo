import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// NSHostingView with its own tracking area and AppKit drag-and-drop.
///
/// Hover: we use a tracking area instead of SwiftUI's .onHover because the
/// panel never becomes key, and .activeAlways is the reliable way to get
/// enter/exit there.
///
/// Drop: handled here rather than with SwiftUI's .onDrop so we can accept
/// *file promises* (the floating screenshot thumbnail, Mail attachments,
/// browser images) and raw image data, not just files that already exist.
@MainActor
final class HoverHostingView<Content: View>: NSHostingView<Content> {
    enum DropZone { case shelf, airDrop }

    var onHover: ((Bool) -> Void)?
    var onDragTargeted: ((DropZone?) -> Void)?
    var onDropFiles: (([URL], DropZone) -> Void)?
    /// Frame of the AirDrop zone in SwiftUI global (top-left) coordinates.
    var airDropFrame: (() -> CGRect?)?

    private var tracking: NSTrackingArea?
    private var currentZone: DropZone?
    private let promiseQueue = OperationQueue()

    required init(rootView: Content) {
        super.init(rootView: rootView)
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(types)
    }

    @MainActor required init?(coder: NSCoder) { fatalError() }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    // Let buttons react on the first click even though the panel never becomes key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent)  { onHover?(false) }

    // MARK: Drop

    private func zone(for sender: NSDraggingInfo) -> DropZone {
        guard let frame = airDropFrame?() else { return .shelf }
        let p = convert(sender.draggingLocation, from: nil)
        let topLeft = CGPoint(x: p.x, y: bounds.height - p.y) // SwiftUI global is y-down
        return frame.contains(topLeft) ? .airDrop : .shelf
    }

    private func setZone(_ z: DropZone?) {
        guard z != currentZone else { return }
        currentZone = z
        onDragTargeted?(z)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        setZone(zone(for: sender))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        setZone(zone(for: sender))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { setZone(nil) }
    override func draggingEnded(_ sender: NSDraggingInfo) { setZone(nil) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let target = zone(for: sender)
        let pb = sender.draggingPasteboard
        setZone(nil)

        // 1. Real files.
        let existing = (pb.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []

        // 2. Promised files (screenshot thumbnail etc.) — written into our shelf folder.
        let promises = (pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]) ?? []

        // 3. Bare image data with no file behind it.
        if existing.isEmpty && promises.isEmpty {
            if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
               let url = ShelfStore.saveDroppedImage(data) {
                onDropFiles?([url], target)
                return true
            }
            return false
        }

        guard !promises.isEmpty else {
            onDropFiles?(existing, target)
            return true
        }

        // A promise drag (screenshot thumbnail) also advertises a temp file URL
        // that disappears once the drag ends — keep only the promised copies.
        let dir = ShelfStore.dropDirectory
        let group = DispatchGroup()
        let lock = NSLock()
        var received: [URL] = []
        for p in promises {
            group.enter()
            p.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: promiseQueue) { url, error in
                if error == nil { lock.lock(); received.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.onDropFiles?(received, target)
        }
        return true
    }
}
