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

    /// Recognised text from part of an image. `rect` is normalised with the
    /// origin at the top-left, matching how the crop box is drawn on screen.
    static func recognize(_ url: URL, region rect: CGRect) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let full = loadImage(url) else { return nil }
            let w = CGFloat(full.width), h = CGFloat(full.height)
            let crop = CGRect(x: rect.minX * w, y: rect.minY * h,
                              width: rect.width * w, height: rect.height * h).integral
            guard crop.width >= 4, crop.height >= 4,
                  let cropped = full.cropping(to: crop) else { return nil }
            return recognize(cropped)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    /// Full-size bitmap with EXIF orientation applied.
    static func loadImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1)
        ] as CFDictionary)
    }

    /// Likely one-time codes in a block of text, most code-like first:
    /// 4–8 character runs of digits (or digits mixed with capitals).
    static func codes(in text: String) -> [String] {
        let patterns = [
            #"\b\d{4,8}\b"#,
            #"\b[A-Z0-9]{4,8}\b"#,
            #"\b\d{3}[- ]\d{3}\b"#
        ]
        var found: [String] = []
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let s = ns.substring(with: m.range).replacingOccurrences(of: " ", with: "")
                if !found.contains(s), s.rangeOfCharacter(from: .decimalDigits) != nil { found.append(s) }
            }
        }
        return found
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
