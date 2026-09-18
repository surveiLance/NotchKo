import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Offline image operations for shelf files. Each returns the URLs it wrote
/// (next to the source, never overwriting it).
enum ImageTools {
    enum Format: String, CaseIterable, Identifiable {
        case png, jpg, heic, pdf
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
        var utType: UTType {
            switch self {
            case .png: return .png
            case .jpg: return .jpeg
            case .heic: return .heic
            case .pdf: return .pdf
            }
        }
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    // MARK: Convert

    static func convert(_ url: URL, to format: Format, quality: Double = 0.9) async -> URL? {
        await Task.detached(priority: .userInitiated) {
            guard let cg = loadCGImage(url) else { return nil }
            let out = outputURL(for: url, suffix: "", ext: format.rawValue)
            if format == .pdf { return writePDF([cg], to: out) ? out : nil }
            return write(cg, to: out, type: format.utType, quality: quality) ? out : nil
        }.value
    }

    // MARK: Cut-out (remove background)

    /// Keeps the foreground subject(s), transparent elsewhere. macOS 14+.
    static func removeBackground(_ url: URL) async -> URL? {
        await Task.detached(priority: .userInitiated) {
            guard let cg = loadCGImage(url) else { return nil }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let result = request.results?.first,
                  let buffer = try? result.generateMaskedImage(
                    ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
            else { return nil }
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let masked = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
            let out = outputURL(for: url, suffix: " cutout", ext: "png")
            return write(masked, to: out, type: .png, quality: 1) ? out : nil
        }.value
    }

    // MARK: Shrink

    /// Downscale so the longest edge is at most `maxEdge` pixels.
    static func shrink(_ url: URL, maxEdge: Int = 1920) async -> URL? {
        await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxEdge,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return nil }
            let ext = url.pathExtension.lowercased() == "png" ? "png" : "jpg"
            let out = outputURL(for: url, suffix: " small", ext: ext)
            return write(cg, to: out, type: ext == "png" ? .png : .jpeg, quality: 0.85) ? out : nil
        }.value
    }

    // MARK: Helpers

    /// Full-size image with EXIF orientation baked in (phone photos are often
    /// stored sideways with a rotation flag; Vision and the writers want pixels
    /// the right way up).
    private static func loadCGImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1),
            kCGImageSourceShouldCache: false
        ] as CFDictionary)
    }

    private static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    private static func writePDF(_ images: [CGImage], to url: URL) -> Bool {
        guard let ctx = CGContext(url as CFURL, mediaBox: nil, nil) else { return false }
        for img in images {
            var box = CGRect(x: 0, y: 0, width: img.width, height: img.height)
            ctx.beginPage(mediaBox: &box)
            ctx.draw(img, in: box)
            ctx.endPage()
        }
        ctx.closePDF()
        return true
    }

    /// "<name><suffix>.<ext>" beside the source; adds " 2", " 3"… if taken.
    private static func outputURL(for url: URL, suffix: String, ext: String) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent + suffix
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
