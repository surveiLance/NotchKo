import SwiftUI
import UniformTypeIdentifiers

/// Image tools. Works on the shelf's selected images, or every image on the
/// shelf when nothing is selected. Images can be dropped straight onto the
/// notch or pasted from the clipboard while this tab is open.
struct ToolsView: View {
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var state: NotchState
    @State private var busy: String? = nil
    @State private var lastOutputs: [URL] = []
    /// Compress target in bytes.
    @AppStorage("tools.compressTarget") private var compressTarget: Int = 1_000_000

    private static let targets: [(label: String, bytes: Int)] = [
        ("200 KB", 200_000), ("500 KB", 500_000), ("1 MB", 1_000_000),
        ("2 MB", 2_000_000), ("5 MB", 5_000_000)
    ]

    private var images: [ShelfItem] { shelf.items.filter { ImageTools.isImage($0.url) } }
    private var targets: [ShelfItem] {
        let selected = shelf.selectedItems.filter { ImageTools.isImage($0.url) }
        return selected.isEmpty ? images : selected
    }

    var body: some View {
        VStack(spacing: 8) {
            sources
            tools
        }
        .overlay {
            if let busy {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.75))
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(busy).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    }
                }
            }
        }
    }

    // MARK: Row 1 — what we're working on

    private var sources: some View {
        HStack(spacing: 10) {
            if targets.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Drop images on the notch, or paste one").font(.system(size: 11, weight: .semibold))
                        Text("They'll appear here, then pick a tool below").font(.system(size: 9.5))
                    }
                }
                .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
            } else {
                HStack(spacing: -8) {
                    ForEach(targets.prefix(6)) { item in
                        Image(nsImage: shelf.thumbnail(for: item))
                            .resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.black, lineWidth: 1.5))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(scopeTitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    Text(scopeHint).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }

            if !lastOutputs.isEmpty {
                Button {
                    shelf.selection = Set(lastOutputs.map(\.path))
                    state.tab = .shelf
                } label: {
                    Label("\(lastOutputs.count) ready · Show on Shelf", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.green.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }

            ToolChip("Paste", symbol: "doc.on.clipboard") { pasteFromClipboard() }
                .help("Add an image or copied files from the clipboard")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: targets.isEmpty ? [5, 4] : [])))
    }

    private var scopeTitle: String {
        let n = targets.count
        let selected = !shelf.selectedItems.filter { ImageTools.isImage($0.url) }.isEmpty
        return "\(n) image\(n == 1 ? "" : "s") \(selected ? "selected" : "on the Shelf")"
    }
    private var scopeHint: String {
        let selected = !shelf.selectedItems.filter { ImageTools.isImage($0.url) }.isEmpty
        return selected ? "Tools apply to your selection" : "Applies to all · select on the Shelf to narrow"
    }

    // MARK: Row 2 — the tools

    private var tools: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ToolLabel("Convert to")
                ForEach(ImageTools.Format.allCases) { f in
                    ToolChip(f.label) { run("Converting to \(f.label)…") { await ImageTools.convert($0, to: f) } }
                }
                Spacer(minLength: 0)
                ToolChip("Cut out", symbol: "person.crop.rectangle") {
                    run("Cutting out subject…") { await ImageTools.removeBackground($0) }
                }
                .help("Keeps the person/object, makes the background transparent (PNG)")
            }
            HStack(spacing: 6) {
                ToolLabel("Make smaller")
                ToolChip("Compress to", symbol: "square.and.arrow.down.on.square") {
                    run("Compressing…") { await ImageTools.compress($0, targetBytes: compressTarget) }
                }
                .help("Squeeze each image under the chosen size (JPEG; downscales only if it has to)")
                Menu {
                    ForEach(Self.targets, id: \.bytes) { t in
                        Button(t.label) { compressTarget = t.bytes }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(currentTargetLabel).font(.system(size: 10, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.11)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Compression target size")

                ToolChip("Fit 1920px", symbol: "arrow.down.right.and.arrow.up.left") {
                    run("Shrinking…") { await ImageTools.shrink($0) }
                }
                .help("Downscale so the longest side is 1920 pixels")
                Spacer(minLength: 0)
            }
        }
        .disabled(targets.isEmpty)
        .opacity(targets.isEmpty ? 0.4 : 1)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private struct ToolLabel: View {
        let text: String
        init(_ text: String) { self.text = text }
        var body: some View {
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 74, alignment: .leading)
        }
    }

    private var currentTargetLabel: String {
        Self.targets.first { $0.bytes == compressTarget }?.label ?? ImageTools.formatBytes(compressTarget)
    }

    // MARK: Actions

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            shelf.add(urls)
            shelf.selection = Set(urls.map(\.path))
        } else if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff), let url = ShelfStore.saveDroppedImage(data) {
            shelf.add([url])
            shelf.selection = [url.path]
        } else {
            state.show(.info(symbol: "doc.on.clipboard", text: "No image on the clipboard"))
        }
    }

    private func run(_ label: String, _ op: @escaping (URL) async -> URL?) {
        let items = targets
        guard !items.isEmpty, busy == nil else { return }
        busy = label
        lastOutputs = []
        Task {
            var outputs: [URL] = []
            for item in items {
                if let out = await op(item.url) { outputs.append(out) }
            }
            busy = nil
            guard !outputs.isEmpty else {
                state.show(.info(symbol: "xmark.circle", text: "Nothing to do"))
                return
            }
            shelf.add(outputs)
            lastOutputs = outputs
            let total = outputs.reduce(0) { $0 + ImageTools.fileSize($1) }
            let detail = outputs.count == 1 ? ImageTools.formatBytes(total) : "\(outputs.count) files"
            state.show(.info(symbol: "checkmark.circle.fill", text: "Ready · \(detail)"))
        }
    }
}

private struct ToolChip: View {
    let text: String
    var symbol: String? = nil
    let action: () -> Void
    @State private var hovering = false
    init(_ text: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.text = text; self.symbol = symbol; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(text).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(hovering ? 0.2 : 0.11)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(text)
    }
}
