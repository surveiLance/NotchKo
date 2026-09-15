import SwiftUI

/// The classic notch silhouette: concave "ears" at the top corners that
/// blend into the bezel, convex rounded corners at the bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let tr = topRadius, br = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + tr, y: r.minY + tr),
                       control: CGPoint(x: r.minX + tr, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tr, y: r.maxY - br))
        p.addQuadCurve(to: CGPoint(x: r.minX + tr + br, y: r.maxY),
                       control: CGPoint(x: r.minX + tr, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - tr - br, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - tr, y: r.maxY - br),
                       control: CGPoint(x: r.maxX - tr, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY + tr))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.maxX - tr, y: r.minY))
        p.closeSubpath()
        return p
    }
}
