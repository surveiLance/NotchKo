import AppKit

extension NSImage {
    /// A vivid accent pulled from the artwork: pixels are weighted by
    /// saturation × brightness so a mostly-dark cover with one strong hue
    /// yields that hue, then clamped so it reads on black.
    func accentColor() -> NSColor? {
        let size = 24
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(
            data: &px, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

        var wr = 0.0, wg = 0.0, wb = 0.0, wsum = 0.0
        var ar = 0.0, ag = 0.0, ab = 0.0
        let n = Double(size * size)
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i+1]) / 255, b = Double(px[i+2]) / 255
            ar += r; ag += g; ab += b
            let mx = max(r, g, b), mn = min(r, g, b)
            let sat = mx == 0 ? 0 : (mx - mn) / mx
            let w = sat * sat * mx
            wr += r * w; wg += g * w; wb += b * w; wsum += w
        }
        let c: NSColor = wsum > 0.5
            ? NSColor(red: wr / wsum, green: wg / wsum, blue: wb / wsum, alpha: 1)
            : NSColor(red: ar / n, green: ag / n, blue: ab / n, alpha: 1)

        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        // Make sure it's visible on black and not washed out.
        return NSColor(hue: h, saturation: max(s, 0.5), brightness: max(v, 0.75), alpha: 1)
    }
}
