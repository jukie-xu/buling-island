import SwiftUI

// MARK: - Expand Animation

enum ExpandAnimation: String, CaseIterable, Identifiable {
    case spring
    case easeOut
    case bouncy
    case snappy
    case smooth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spring: return "弹性展开"
        case .easeOut: return "平滑展开"
        case .bouncy: return "弹跳展开"
        case .snappy: return "快速弹出"
        case .smooth: return "柔和展开"
        }
    }

    var animation: Animation {
        switch self {
        case .spring: return .spring(response: 0.35, dampingFraction: 0.8)
        case .easeOut: return .easeOut(duration: 0.3)
        case .bouncy: return .spring(response: 0.4, dampingFraction: 0.6)
        case .snappy: return .spring(response: 0.2, dampingFraction: 0.9)
        case .smooth: return .easeInOut(duration: 0.5)
        }
    }

    var transition: AnyTransition {
        switch self {
        case .spring: return .scale(scale: 0.9, anchor: .top).combined(with: .opacity)
        case .easeOut: return .opacity.combined(with: .move(edge: .top))
        case .bouncy: return .scale(scale: 0.5, anchor: .top).combined(with: .opacity)
        case .snappy: return .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
        case .smooth: return .opacity
        }
    }
}

// MARK: - Collapse Animation

enum CollapseAnimation: String, CaseIterable, Identifiable {
    case spring
    case easeIn
    case bouncy
    case snappy
    case smooth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spring: return "弹性收回"
        case .easeIn: return "平滑收回"
        case .bouncy: return "弹跳收回"
        case .snappy: return "快速收回"
        case .smooth: return "柔和收回"
        }
    }

    var animation: Animation {
        switch self {
        case .spring: return .spring(response: 0.3, dampingFraction: 0.85)
        case .easeIn: return .easeIn(duration: 0.25)
        case .bouncy: return .spring(response: 0.35, dampingFraction: 0.6)
        case .snappy: return .spring(response: 0.15, dampingFraction: 0.9)
        case .smooth: return .easeInOut(duration: 0.45)
        }
    }

    var transition: AnyTransition {
        switch self {
        case .spring: return .scale(scale: 0.9, anchor: .top).combined(with: .opacity)
        case .easeIn: return .opacity.combined(with: .move(edge: .top))
        case .bouncy: return .scale(scale: 0.5, anchor: .top).combined(with: .opacity)
        case .snappy: return .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
        case .smooth: return .opacity
        }
    }
}
