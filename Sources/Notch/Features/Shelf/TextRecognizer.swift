import AppKit
import PDFKit
import Vision
import UniformTypeIdentifiers

/// On-device OCR for shelf files (images and PDFs) via Vision.
enum TextRecognizer {
    static func supports(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    /// Recognised text, paragraphs joined with newlines; nil if nothing found.
    static func recognize(_ url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let images: [CGImage]
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                images = pdfPages(url, limit: 20)
            } else if let img = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                images = [img]
            } else {
                return nil
            }
            let pages = images.compactMap(recognize)
            let text = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }.value
    }

    private static func recognize(_ image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results, !results.isEmpty else { return nil }
        return results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func pdfPages(_ url: URL, limit: Int) -> [CGImage] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<min(doc.pageCount, limit)).compactMap { i in
            guard let page = doc.page(at: i) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.white.setFill(); rect.fill()
                let ctx = NSGraphicsContext.current!.cgContext
                ctx.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: ctx)
                return true
            }
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
}
