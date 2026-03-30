import SwiftUI

/// 矩形仅底部左右为**圆角**，圆角为与竖边、底边**相切的圆弧**（外切 / 经典机加工倒圆），
/// 不由 `cornerRadius` 曲线族近似，几何上与两条直线段光滑相接。
struct TangentFilletBottomRectangle: InsettableShape {

    /// 底部左、右使用同一圆弧半径（与底边、侧边相切）。
    var bottomFilletRadius: CGFloat

    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = bottomFilletRadius
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = insetRect.width
        let h = insetRect.height
        let x = insetRect.minX
        let y = insetRect.minY
        var path = Path()

        guard w > 0, h > 0 else { return path }

        // 仅底角倒圆：半径不得超过半宽，且不得超过高度（弧顶需落在矩形内）
        let fillet = min(max(r, 0), min(w / 2, h) - 0.0001)
        if fillet <= 0 {
            path.addRect(insetRect)
            return path
        }

        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + w, y: y))
        path.addLine(to: CGPoint(x: x + w, y: y + h - fillet))
        path.addArc(
            tangent1End: CGPoint(x: x + w, y: y + h),
            tangent2End: CGPoint(x: x + w - fillet, y: y + h),
            radius: fillet
        )
        path.addLine(to: CGPoint(x: x + fillet, y: y + h))
        path.addArc(
            tangent1End: CGPoint(x: x, y: y + h),
            tangent2End: CGPoint(x: x, y: y + h - fillet),
            radius: fillet
        )
        path.addLine(to: CGPoint(x: x, y: y))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> TangentFilletBottomRectangle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
