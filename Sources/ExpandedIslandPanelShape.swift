import SwiftUI

/// **展开态面板**外轮廓（与收缩 pill 无关）：
/// - 顶左、顶右：**凸圆角**，圆弧与顶边、竖边相切（与 `addArc(tangent1End:tangent2End:radius:)` 一致），便于和屏上沿形成连续过渡。
/// - 底左、底右：相切凸圆弧（同 `TangentFilletBottomRectangle`）。
struct ExpandedIslandPanelShape: InsettableShape {

    /// 顶部左、右凸圆角半径（相切圆弧，非 `UnevenRoundedRectangle` 近似）。
    var topConvexRadius: CGFloat

    /// 底部左、右凸圆角半径（相切圆弧）。
    var bottomFilletRadius: CGFloat

    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let x0 = insetRect.minX
        let y0 = insetRect.minY
        let w = insetRect.width
        let h = insetRect.height
        var path = Path()
        guard w > 1, h > 1 else { return path }

        let rTop = min(max(topConvexRadius, 0), min(w / 2, h / 2) - 0.0001)
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

        path.move(to: CGPoint(x: x0 + rTop, y: y0))
        path.addLine(to: CGPoint(x: x0 + w - rTop, y: y0))
        path.addArc(
            tangent1End: CGPoint(x: x0 + w, y: y0),
            tangent2End: CGPoint(x: x0 + w, y: y0 + rTop),
            radius: rTop
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
        path.addArc(
            tangent1End: CGPoint(x: x0, y: y0),
            tangent2End: CGPoint(x: x0 + rTop, y: y0),
            radius: rTop
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
