import SwiftUI

/// Rectangle-like shape with:
/// - Top-left / top-right: outward-flared cubic Bézier corners (like `ExpandedIslandPanelShape`, but configurable)
/// - Bottom-left / bottom-right: tangent fillet arcs (like `TangentFilletBottomRectangle`)
struct FlaredTopTangentBottomRectangle: InsettableShape {
    var topConvexRadius: CGFloat
    var topCornerFlare: CGFloat = 0.58
    var bottomFilletRadius: CGFloat
    /// Horizontal inset for the "body" rect relative to the outer rect.
    /// Increasing this (or the outer rect width) pushes P0 outward while keeping P2 (on the body side) fixed.
    var bodyInsetX: CGFloat? = nil

    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let xOuter0 = insetRect.minX
        let xOuter1 = insetRect.maxX
        let y0 = insetRect.minY
        let h = insetRect.height

        var path = Path()
        guard insetRect.width > 1, h > 1 else { return path }

        let rTop = min(max(topConvexRadius, 0), min(insetRect.width / 2, h / 2) - 0.0001)
        if rTop <= 0 {
            var bottomOnly = TangentFilletBottomRectangle(bottomFilletRadius: bottomFilletRadius)
            bottomOnly.insetAmount = insetAmount
            return bottomOnly.path(in: rect)
        }

        // Body uses a narrower base rect; top flare consumes the outer horizontal margins.
        let insetX = max(bodyInsetX ?? rTop, 0)
        let baseRect = insetRect.insetBy(dx: insetX, dy: 0)
        let x0 = baseRect.minX
        let w = baseRect.width

        let bf = min(max(bottomFilletRadius, 0), min(w / 2, h - rTop) - 0.0001)
        if bf <= 0 {
            path.addRect(insetRect)
            return path
        }

        let tf = min(max(topCornerFlare, 0.5), 0.82)
        let arm = rTop * (1 - tf)

        // Start at outer top-left and draw outer top edge.
        path.move(to: CGPoint(x: xOuter0, y: y0))
        path.addLine(to: CGPoint(x: xOuter1, y: y0))

        // Top-right flare: outer edge -> right side at (x0+w, y0+rTop)
        path.addCurve(
            to: CGPoint(x: x0 + w, y: y0 + rTop),
            control1: CGPoint(x: xOuter1 - arm, y: y0),
            control2: CGPoint(x: x0 + w, y: y0 + arm)
        )

        // Right side down to bottom fillet start.
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

        // Left side up to top-left flare start.
        path.addLine(to: CGPoint(x: x0, y: y0 + rTop))
        path.addCurve(
            to: CGPoint(x: xOuter0, y: y0),
            control1: CGPoint(x: x0, y: y0 + arm),
            control2: CGPoint(x: xOuter0 + arm, y: y0)
        )

        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> FlaredTopTangentBottomRectangle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

