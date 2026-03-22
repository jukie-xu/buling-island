import Foundation

enum DisplayMode: String, CaseIterable, Identifiable {
    case grid
    case alphabetical
    case launchpad

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grid: return "默认网格"
        case .alphabetical: return "字母分组"
        case .launchpad: return "Launchpad"
        }
    }

    var description: String {
        switch self {
        case .grid: return "简单网格排列所有应用"
        case .alphabetical: return "按首字母分组，类似通讯录"
        case .launchpad: return "macOS 风格，支持拖拽创建文件夹"
        }
    }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .alphabetical: return "textformat.abc"
        case .launchpad: return "square.grid.3x3"
        }
    }
}
