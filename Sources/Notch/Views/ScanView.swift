import AppKit
import SwiftUI

/// Pull text out of part of an image: drag a box over the picture and the
/// text inside it is read and shown right there, ready to copy. Built for
/// one-time codes — those get their own big button.
struct ScanView: View {
    @ObservedObject var state: NotchState
    let url: URL

    @State private var image: NSImage?
    /// Selection in normalised image coordinates, origin top-left.
    @State private var selection: CGRect?
    @State private var dragStart: CGPoint?
    @State private var busy = false
    @State private var result: String?
    @State private var codes: [String] = []
    /// Whatever the user has highlighted in the recognised text.
    @State private var highlighted = ""


    var body: some View {
        HStack(spacing: 10) {
            picture
            sidebar.frame(width: 232)
        }
        .onAppear {
            image = NSImage(contentsOf: url)
            // Highlighting and ⌘C need the panel to accept key events.
            state.keyboardWanted = true
        }
        .onDisappear { state.keyboardWanted = false }
    }

    // MARK: Picture + crop box

    private var picture: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                // Dim everything outside the selection.
                if let sel = selection {
                    let r = rect(sel, in: geo.size)
                    Canvas { ctx, size in
                        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.55)))
                        ctx.blendMode = .destinationOut
                        ctx.fill(Path(r), with: .color(.black))
                    }
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                } else {
                    Color.black.opacity(0.25)
                    Text("Drag a box over the text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        if dragStart == nil { dragStart = v.startLocation }
                        selection = normalised(from: dragStart ?? v.startLocation, to: v.location, in: geo.size)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        if let sel = selection, sel.width > 0.01, sel.height > 0.01 { scan(sel) }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .accessibilityLabel("Image to scan. Drag to select a region.")
    }

    /// Selection is stored relative to the *displayed* picture, which is
    /// letterboxed inside the view by aspect-fit.
    private func contentFrame(in size: CGSize) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func normalised(from a: CGPoint, to b: CGPoint, in size: CGSize) -> CGRect {
        let f = contentFrame(in: size)
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, f.minX), f.maxX), y: min(max(p.y, f.minY), f.maxY))
        }
        let p1 = clamp(a), p2 = clamp(b)
        return CGRect(x: (min(p1.x, p2.x) - f.minX) / f.width,
                      y: (min(p1.y, p2.y) - f.minY) / f.height,
                      width: abs(p2.x - p1.x) / f.width,
                      height: abs(p2.y - p1.y) / f.height)
    }

    private func rect(_ norm: CGRect, in size: CGSize) -> CGRect {
        let f = contentFrame(in: size)
        return CGRect(x: f.minX + norm.minX * f.width, y: f.minY + norm.minY * f.height,
                      width: norm.width * f.width, height: norm.height * f.height)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { state.endScan() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 24, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to the shelf")

                Text("Scan").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
                if busy { ProgressView().controlSize(.small) }
            }

            if !codes.isEmpty {
                Text("LOOKS LIKE A CODE").font(.system(size: 8, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.45))
                ForEach(codes.prefix(3), id: \.self) { code in
                    Button { copy(code) } label: {
                        HStack {
                            Text(code)
                                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white)
                            Spacer(minLength: 4)
                            Image(systemName: "doc.on.doc").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 9).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.opacity(0.3)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Copy \(code)")
                }
            }

            if let result, !result.isEmpty {
                HStack(spacing: 4) {
                    Text(highlighted.isEmpty ? "DRAG TO HIGHLIGHT" : "HIGHLIGHTED")
                        .font(.system(size: 8, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer(minLength: 0)
                }

                SelectableText(text: result, selection: $highlighted)
                    .frame(maxHeight: codes.isEmpty ? .infinity : 86)

                Button { copy(highlighted.isEmpty ? result : highlighted) } label: {
                    Label(highlighted.isEmpty ? "Copy all" : "Copy highlighted",
                          systemImage: "doc.on.clipboard")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(highlighted.isEmpty ? .white.opacity(0.14) : Color.accentColor.opacity(0.75)))
                }
                .buttonStyle(.plain)
                .help("⌘C works too")
            } else if !busy {
                Text(selection == nil
                     ? "Drag a box over the part you want, or scan the whole image."
                     : "No text in that box — try a bigger one.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button { scanAll() } label: {
                Label("Scan whole image", systemImage: "text.viewfinder")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    private func scan(_ region: CGRect) {
        busy = true
        Task {
            let text = await TextRecognizer.recognize(url, region: region)
            finish(text)
        }
    }

    private func scanAll() {
        selection = nil
        busy = true
        Task {
            let text = await TextRecognizer.recognize(url)
            finish(text)
        }
    }

    private func finish(_ text: String?) {
        busy = false
        highlighted = ""
        // Vision returns one line per observation; keep them as-is so the
        // highlighted text matches what's on screen.
        result = text
        guard let text else { codes = []; return }
        var found = TextRecognizer.codes(in: text)
        // Codes are often spaced or split across lines ("764 362", or one
        // digit group per line) — the whole selection squashed together is
        // usually the thing you actually wanted.
        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        if (4...10).contains(compact.count),
           compact.rangeOfCharacter(from: .decimalDigits) != nil,
           compact.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil,
           !found.contains(compact) {
            found.insert(compact, at: 0)
        }
        codes = found
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        state.endScan()
        state.show(.info(symbol: "doc.on.clipboard.fill", text: "Copied \(s.count <= 16 ? s : "\(s.count) characters")"))
    }
}


/// Read-only text you can drag-highlight, with ⌘C and ⌘A, reporting the
/// current selection back to SwiftUI.
private struct SelectableText: NSViewRepresentable {
    let text: String
    @Binding var selection: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textColor = .white
        tv.font = .systemFont(ofSize: 11)
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.55),
            .foregroundColor: NSColor.white
        ]
        tv.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
        tv.setSelectedRange(NSRange(location: 0, length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let range = tv.selectedRange()
            let picked = range.length > 0 ? (tv.string as NSString).substring(with: range) : ""
            if selection.wrappedValue != picked { selection.wrappedValue = picked }
        }
    }
}
