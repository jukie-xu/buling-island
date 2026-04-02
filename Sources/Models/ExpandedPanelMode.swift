import Foundation

/// 展开后面板顶栏三种模式（应用 / Claude / 任务）。
enum ExpandedPanelMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case appStore
    case claude
    case tasks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appStore: return "应用面板"
        case .claude: return "Claude 面板"
        case .tasks: return "任务面板"
        }
    }
}
