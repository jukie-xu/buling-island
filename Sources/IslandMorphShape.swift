import SwiftUI

/// Morph between a pill-sized flare shape and the expanded panel shape.
/// Both share the same topology (top flare corners + bottom tangent fillets),
/// so we can interpolate the rect + key parameters smoothly.
struct IslandMorphShape: Shape {
    /// 0 = pill, 1 = expanded
    var progress: CGFloat

    var pillSize: CGSize
    var expandedSize: CGSize

    var pillTopRadius: CGFloat
    var expandedTopRadius: CGFloat

    var pillTopFlare: CGFloat
    var expandedTopFlare: CGFloat

    var pillBottomFillet: CGFloat
    var expandedBottomFillet: CGFloat

    /// Horizontal body inset (keeps P2 fixed) for the pill; expanded uses its top radius.
    var pillBodyInsetX: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(max(progress, 0), 1)

        let pillRect = CGRect(
            x: rect.midX - pillSize.width / 2,
            y: rect.minY,
            width: pillSize.width,
            height: pillSize.height
        )
        let expandedRect = CGRect(
            x: rect.midX - expandedSize.width / 2,
            y: rect.minY,
            width: expandedSize.width,
            height: expandedSize.height
        )

        let cur = lerpRect(pillRect, expandedRect, t)
        let rTop = lerp(pillTopRadius, expandedTopRadius, t)
        let tf = lerp(pillTopFlare, expandedTopFlare, t)
        let bf = lerp(pillBottomFillet, expandedBottomFillet, t)

        // Body inset X: interpolate from pill's custom inset -> expanded's rTop.
        let insetX = lerp(pillBodyInsetX, rTop, t)

        return flaredTopTangentBottomPath(in: cur, topRadius: rTop, topFlare: tf, bottomFillet: bf, bodyInsetX: insetX)
    }

    private func flaredTopTangentBottomPath(
        in rect: CGRect,
        topRadius: CGFloat,
        topFlare: CGFloat,
        bottomFillet: CGFloat,
        bodyInsetX: CGFloat
    ) -> Path {
        let insetRect = rect
        let xOuter0 = insetRect.minX
        let xOuter1 = insetRect.maxX
        let y0 = insetRect.minY
        let h = insetRect.height

        var path = Path()
        guard insetRect.width > 1, h > 1 else { return path }

        let rTop = min(max(topRadius, 0), min(insetRect.width / 2, h / 2) - 0.0001)
        let insetX = min(max(bodyInsetX, 0), insetRect.width / 2 - 0.0001)
        let baseRect = insetRect.insetBy(dx: insetX, dy: 0)
        let x0 = baseRect.minX
        let w = baseRect.width

        let bf = min(max(bottomFillet, 0), min(w / 2, h - rTop) - 0.0001)
        if rTop <= 0 || bf <= 0 {
            path.addRect(insetRect)
            return path
        }

        let tf = min(max(topFlare, 0.5), 0.82)
        let arm = rTop * (1 - tf)

        path.move(to: CGPoint(x: xOuter0, y: y0))
        path.addLine(to: CGPoint(x: xOuter1, y: y0))
        path.addCurve(
            to: CGPoint(x: x0 + w, y: y0 + rTop),
            control1: CGPoint(x: xOuter1 - arm, y: y0),
            control2: CGPoint(x: x0 + w, y: y0 + arm)
        )
        path.addLine(to: CGPoint(x: x0 + w, y: y0 + h - bf))
        path.addArc(
            tangent1End: CGPoint(x: x0 + w, y: y0 + h),
            tangent2End: CGPoint(x: x0 + w - bf, y: y0 + h),
            radius: bf
        )
        path.addLine(to: CGPoint(x: x0 + bf, y: y0 + h))
        path.addArc(
            tangent1End: CGPoint(x: x0, y: y0 + h),
            tangent2End: CGPoint(x: x0, y: y0 + h - bf),
            radius: bf
        )
        path.addLine(to: CGPoint(x: x0, y: y0 + rTop))
        path.addCurve(
            to: CGPoint(x: xOuter0, y: y0),
            control1: CGPoint(x: x0, y: y0 + arm),
            control2: CGPoint(x: xOuter0 + arm, y: y0)
        )
        path.closeSubpath()
        return path
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private func lerpRect(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: lerp(a.origin.x, b.origin.x, t),
            y: lerp(a.origin.y, b.origin.y, t),
            width: lerp(a.size.width, b.size.width, t),
            height: lerp(a.size.height, b.size.height, t)
        )
    }
}

