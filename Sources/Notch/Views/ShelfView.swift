import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var state: NotchState
    private var airDropTargeted: Bool { state.dropZone == .airDrop }

    var body: some View {
        HStack(spacing: 14) {
            airDropZone
                .frame(width: 84)

            if shelf.items.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfItemView(
                                item: item,
                                image: shelf.thumbnail(for: item),
                                selected: shelf.selection.contains(item.id),
                                dragPayload: { shelf.dragPayload(for: item) },
                                onTap: { shelf.toggle(item) },
                                onRemove: { shelf.remove(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(.top, 2)
    }

    /// Selected files if any are selected, otherwise everything on the shelf.
    private var airDropTargets: [URL] {
        (shelf.selection.isEmpty ? shelf.items : shelf.selectedItems).map(\.url)
    }

    private var airDropZone: some View {
        VStack(spacing: 5) {
            Image(systemName: "airplayaudio")  // closest SF glyph to the AirDrop rings
                .font(.system(size: 24, weight: .medium))
            Text(shelf.selection.isEmpty ? "AirDrop" : "AirDrop \(shelf.selection.count)")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(airDropTargeted ? .white : .white.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.blue.opacity(airDropTargeted ? 0.55 : 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.blue.opacity(airDropTargeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: airDropTargeted ? [] : [5, 4]))
        )
        .animation(.easeOut(duration: 0.15), value: airDropTargeted)
        // Report where we are so the AppKit drop handler can tell this zone from the shelf.
        .background(GeometryReader { geo in
            Color.clear.preference(key: AirDropFrameKey.self, value: geo.frame(in: .global))
        })
        .onPreferenceChange(AirDropFrameKey.self) { state.airDropFrame = $0 }
        .onTapGesture { ShelfStore.airDrop(airDropTargets) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shelf.selection.isEmpty ? "AirDrop all shelf files" : "AirDrop \(shelf.selection.count) selected files")
        .accessibilityAddTraits(.isButton)
    }

    private var shelfTargeted: Bool { state.dropZone == .shelf }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: shelfTargeted ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 22))
            Text(shelfTargeted ? "Drop to keep here" : "Drop files or screenshots here")
                .font(.system(size: 11))
        }
        .foregroundStyle(.white.opacity(shelfTargeted ? 0.9 : 0.4))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(shelfTargeted ? 0.5 : 0.15), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
    }
}

struct AirDropFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

private struct ShelfItemView: View {
    let item: ShelfItem
    let image: NSImage
    let selected: Bool
    let dragPayload: () -> [URL]
    let onTap: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 68)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.28) : .white.opacity(hovering ? 0.1 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(selected ? 0.9 : 0), lineWidth: 1.5)
        )
        .overlay(
            MultiFileDragSource(urls: dragPayload, onTap: onTap, onRemove: onRemove, onHover: { hovering = $0 })
        )
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white, Color.accentColor)
                    .offset(x: 3, y: -3)
                    .allowsHitTesting(false)
            } else if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .black.opacity(0.7))
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -3)
                .accessibilityLabel("Remove \(item.name) from shelf")
            }
        }
        .animation(.easeOut(duration: 0.12), value: selected)
        .help(item.url.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Click to select. Drag to copy out. Right-click to remove.")
        .accessibilityAddTraits(.isButton)
    }
}
