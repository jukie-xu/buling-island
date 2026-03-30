import SwiftUI

/// **展开态面板**外轮廓（与收缩 pill 无关）：
/// - 顶左、顶右：**外撇式**过渡——用三次 Bézier 替代内切圆角；沿顶/竖边保留更长近似直线段，弯角更贴屏角（视觉上左角更朝左、右角更朝右「鼓」），外接矩形不变。
/// - 底左、底右：相切凸圆弧（同 `TangentFilletBottomRectangle`）。
struct ExpandedIslandPanelShape: InsettableShape {

    /// 顶部左、右弯角尺度（与旧版圆角半径语义兼容，用于确定顶边与竖边上受影响的区段长度）。
    var topConvexRadius: CGFloat

    /// 越大弯角越「收向」外角（沿边平直段越长）；约在 `0.52~0.58` 接近旧圆形，`0.60~0.72` 更外撇。建议与 `topConvexRadius` 搭配调。
    var topCornerFlare: CGFloat = 0.64

    /// 底部左、右凸圆角半径（相切圆弧）。
    var bottomFilletRadius: CGFloat

    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let y0 = insetRect.minY
        let h = insetRect.height
        var path = Path()
        guard insetRect.width > 1, h > 1 else { return path }

        // We render the "body" inside a base rect, leaving horizontal margins on both sides
        // so the top flare (which needs extra horizontal room) can be drawn without being
        // clipped by the window/view bounds.
        let rTop = min(max(topConvexRadius, 0), min(insetRect.width / 2, h / 2) - 0.0001)
        let baseRect = insetRect.insetBy(dx: rTop, dy: 0)
        let x0 = baseRect.minX
        let w = baseRect.width

        let bf = min(max(bottomFilletRadius, 0), min(w / 2, h - rTop) - 0.0001)

        if rTop <= 0 {
            var bottomOnly = TangentFilletBottomRectangle(bottomFilletRadius: bottomFilletRadius)
            bottomOnly.insetAmount = insetAmount
            return bottomOnly.path(in: rect)
        }

        if bf <= 0 {
            path.addRect(insetRect)
            return path
        }

        let tf = min(max(topCornerFlare, 0.5), 0.82)
        let arm = rTop * (1 - tf)

        // Top flare corners:
        // Top endpoints live at the *outer* rect edges (inside `insetRect`), while the side/bottom
        // geometry uses the inner `baseRect` (body stays same width).

        path.move(to: CGPoint(x: insetRect.minX, y: y0))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: y0))
        path.addCurve(
            to: CGPoint(x: x0 + w, y: y0 + rTop),
            control1: CGPoint(x: insetRect.maxX - arm, y: y0),
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
            to: CGPoint(x: insetRect.minX, y: y0),
            control1: CGPoint(x: x0, y: y0 + arm),
            control2: CGPoint(x: insetRect.minX + arm, y: y0)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> ExpandedIslandPanelShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
