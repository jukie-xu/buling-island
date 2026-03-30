import Foundation

/// 收缩态刘海 pill 左右扩展区可展示的内容（在设置中分别配置左右槽位）。
enum PillSideWidget: String, CaseIterable, Identifiable, Codable, Hashable {
    case none
    case battery
    case networkSpeed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "无"
        case .battery: return "电量"
        case .networkSpeed: return "实时网速"
        }
    }
}
