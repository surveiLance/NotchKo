import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Files parked in the notch. Stores references, not copies; persists paths
/// across launches and silently drops anything that no longer exists.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var selection: Set<ShelfItem.ID> = []
    /// QuickLook previews, generated lazily so images/PDFs show their content.
    @Published private(set) var thumbnails: [ShelfItem.ID: NSImage] = [:]
    private let key = "shelf.paths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(ShelfItem.init)
    }

    func add(_ urls: [URL]) {
        for url in urls
        where !items.contains(where: { $0.url == url }) && FileManager.default.fileExists(atPath: url.path) {
            items.append(ShelfItem(url: url))
        }
        save()
    }

    func thumbnail(for item: ShelfItem) -> NSImage {
        if let t = thumbnails[item.id] { return t }
        requestThumbnail(for: item)
        return item.icon
    }

    private var requested: Set<ShelfItem.ID> = []
    private func requestThumbnail(for item: ShelfItem) {
        guard !requested.contains(item.id) else { return }
        requested.insert(item.id)
        let req = QLThumbnailGenerator.Request(
            fileAt: item.url, size: CGSize(width: 44, height: 44), scale: 2, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let rep else { return }
            Task { @MainActor in self?.thumbnails[item.id] = rep.nsImage }
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
        selection.remove(item.id)
        save()
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
        save()
    }

    /// Trash button: selected files if any are selected, otherwise everything.
    func removeSelectedOrAll() {
        if selection.isEmpty { clear(); return }
        items.removeAll { selection.contains($0.id) }
        selection.removeAll()
        save()
    }

    // MARK: - Selection

    var allSelected: Bool { !items.isEmpty && selection.count == items.count }
    var selectedItems: [ShelfItem] { items.filter { selection.contains($0.id) } }

    func toggle(_ item: ShelfItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func toggleSelectAll() {
        selection = allSelected ? [] : Set(items.map(\.id))
    }

    /// What a drag starting on `item` should carry: the whole selection if the
    /// item is part of it (Finder behaviour), otherwise just that item.
    func dragPayload(for item: ShelfItem) -> [URL] {
        selection.contains(item.id) ? selectedItems.map(\.url) : [item.url]
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: key)
    }

    // MARK: - Drop helpers

    /// Where promised files (screenshot thumbnails etc.) and pasted image data land.
    nonisolated static var dropDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Notch/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func saveDroppedImage(_ data: Data) -> URL? {
        guard let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = dropDirectory.appendingPathComponent("Image \(f.string(from: Date())).png")
        return (try? png.write(to: url)) == nil ? nil : url
    }

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else { return }
        service.perform(withItems: urls)
    }
}
