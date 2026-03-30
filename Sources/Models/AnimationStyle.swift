import SwiftUI

// MARK: - Safe panel transitions（勿把偏好直接绑进 `transition`）

/// 展开/收起「路径」必须**固定**：若 `transition` 随 `SettingsManager` 的选项变化而换成另一种 `AnyTransition`，
/// SwiftUI 可能在过渡中途重算视图并闪退。弹性 / 弹跳等手感仍由 ViewModel 里 `withAnimation(settings.expandAnimation.animation)` 等提供。
enum IslandPanelViewTransition {
    static let collapsedBranch: AnyTransition = .asymmetric(
        insertion: .opacity,
        removal: .identity
    )

    /// 主面板仅用透明度：与 `clipShape(ExpandedIslandPanelShape)` 组合时，`scale` 过渡在部分 macOS/SwiftUI 版本上易在展开瞬间崩溃。
    static let expandedBranch: AnyTransition = .asymmetric(
        insertion: .opacity,
        removal: .opacity
    )

    /// 设置页预览（与主面板同样避免动态 `transition`）。
    static let settingsPreviewExpanded: AnyTransition = .opacity
        .combined(with: .scale(scale: 0.92, anchor: .top))

    static let settingsPreviewCollapsed: AnyTransition = .opacity
        .combined(with: .scale(scale: 0.96, anchor: .top))
}

// MARK: - Expand Animation

enum ExpandAnimation: String, CaseIterable, Identifiable {
    case spring
    case snappy
    case smooth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spring: return "弹性展开"
        case .snappy: return "快速弹出"
        case .smooth: return "柔和展开"
        }
    }

    var detail: String {
        switch self {
        case .spring: return "有弹性，稳定耐看"
        case .snappy: return "响应更快、更利落"
        case .smooth: return "更慢、更柔和"
        }
    }

    var animation: Animation {
        switch self {
        case .spring: return .spring(response: 0.35, dampingFraction: 0.8)
        case .snappy: return .spring(response: 0.2, dampingFraction: 0.9)
        case .smooth: return .easeInOut(duration: 0.5)
        }
    }
}

// MARK: - Collapse Animation

enum CollapseAnimation: String, CaseIterable, Identifiable {
    case spring
    case snappy
    case smooth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spring: return "弹性收回"
        case .snappy: return "快速收回"
        case .smooth: return "柔和收回"
        }
    }

    var detail: String {
        switch self {
        case .spring: return "有弹性，回收自然"
        case .snappy: return "更快、更干脆"
        case .smooth: return "更慢、更柔和"
        }
    }

    var animation: Animation {
        switch self {
        case .spring: return .spring(response: 0.3, dampingFraction: 0.85)
        case .snappy: return .spring(response: 0.15, dampingFraction: 0.9)
        case .smooth: return .easeInOut(duration: 0.45)
        }
    }
}
