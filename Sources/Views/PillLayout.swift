import SwiftUI

/// 收缩态 pill 几何：以**刘海宽度为中枢**，左右两翼向外延展；与 `collapsedView` 布局一致。
@MainActor
enum PillLayout {

    /// 两翼与刘海留缝（避免贴死硬件裁切感）。
    static let notchAdjacentGap: CGFloat = 2
    /// 与 pill 左右圆角内侧的留白（内容靠最外沿对齐）。
    static var pillEndInset: CGFloat { 6 }

    /// Without an outer stroke, the pill can look visually shorter than the notch.
    /// We slightly overhang the pill height and shift it upward in `IslandView`,
    /// and keep hit-testing in sync via `PanelManager`.
    static var visualHeightOverhang: CGFloat { SettingsManager.shared.pillVisualHeightOverhang }

    /// Extra horizontal room for the flared top corners (P0 sits further out),
    /// making the flare rounder without shifting inner content layout.
    static var visualWidthOverhang: CGFloat { SettingsManager.shared.pillVisualWidthOverhang }

    /// Content inset measured from the notch vertical edge (inner edge between wing and core).
    /// This keeps battery/network text stable even if wing widths change.
    static var contentInsetFromNotchEdge: CGFloat { 6 }

    /// 左侧或右侧只要挂了电量/网速任一模块，两翼占位宽度**相同且固定**，避免左右不对称、随类型浮动。
    static var sideSlotFixedWidth: CGFloat { SettingsManager.shared.pillSideSlotWidth }

    static func slotWidth(_ widget: PillSideWidget) -> CGFloat {
        switch widget {
        case .none: return 0
        case .battery, .networkSpeed: return sideSlotFixedWidth
        }
    }

    /// 刘海中枢：与系统检测的 `notchWidth` 完全一致（无附加加宽）；无刘海回退时用默认值。
    static func coreNotchWidth(notch: NotchInfo) -> CGFloat {
        let w = notch.notchWidth
        return w > 0 ? w : NotchInfo.default.notchWidth
    }

    /// 左翼：pill 左外沿 → 刘海左缘（外留白 + 槽 + 与刘海缝）。
    static func leftWingTotalWidth(left: PillSideWidget) -> CGFloat {
        guard left != .none else { return 0 }
        return pillEndInset + slotWidth(left) + notchAdjacentGap
    }

    /// 右翼：刘海右缘 → pill 右外沿（缝 + 槽 + 外留白）。
    static func rightWingTotalWidth(right: PillSideWidget) -> CGFloat {
        guard right != .none else { return 0 }
        return notchAdjacentGap + slotWidth(right) + pillEndInset
    }

    /// 无侧栏时总宽 = 刘海宽；有侧栏时 = 左/右（或仅端部 inset）+ 中枢。
    /// 与 `collapsedView.frame(width:)` 一致，供 `PanelManager` 热区使用。
    static func totalWidth(notch: NotchInfo, left: PillSideWidget, right: PillSideWidget) -> CGFloat {
        let core = coreNotchWidth(notch: notch)
        let hasLeft = left != .none
        let hasRight = right != .none
        if !hasLeft && !hasRight {
            return core
        }
        var w = core
        if hasLeft { w += leftWingTotalWidth(left: left) }
        if hasRight { w += rightWingTotalWidth(right: right) }
        return w
    }
}
