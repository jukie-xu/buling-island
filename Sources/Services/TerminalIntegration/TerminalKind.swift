import Foundation

/// 已接入或计划接入的终端产品在捕获协议中的标识（与 AppleScript `tell application` 名称对齐）。
enum TerminalKind: String, Codable, CaseIterable, Hashable {
    case iTerm2 = "iTerm2"
    /// 经典 iTerm（非 iTerm2）
    case iTermLegacy = "iTerm"
    /// 系统自带「终端」(Terminal.app)
    case appleTerminal = "Terminal"
    /// Tabby 终端（基于 Electron）
    case tabby = "Tabby"

    /// `NSRunningApplication` / `System Events` 里的进程名。
    var processName: String {
        switch self {
        case .appleTerminal:
            return "Terminal"
        case .tabby:
            return "Tabby"
        default:
            return rawValue
        }
    }

    /// 运行时进程探针用：优先按 bundle id 判断，找不到时回退 `processName`。
    var runtimeBundleIdentifierCandidates: [String] {
        switch self {
        case .iTerm2:
            return ["com.googlecode.iterm2"]
        case .iTermLegacy:
            return ["com.googlecode.iterm"]
        case .appleTerminal:
            return ["com.apple.Terminal"]
        case .tabby:
            return ["org.tabby", "io.tabby", "app.tabby"]
        }
    }

    /// AppleScript 目标应用名。
    var appleScriptApplicationName: String {
        switch self {
        case .appleTerminal:
            return "Terminal"
        default:
            return rawValue
        }
    }

    /// 用于 `tell application id` 触发自动化授权；为 nil 时回退为 `appleScriptApplicationName`。
    var automationBundleIdentifier: String? {
        switch self {
        case .iTerm2:
            return "com.googlecode.iterm2"
        case .iTermLegacy:
            return nil
        case .appleTerminal:
            return "com.apple.Terminal"
        case .tabby:
            return "org.tabby"
        }
    }

    /// UI 分组用简短名称（多种子品牌可并入同一组）。
    var captureGroupLabel: String {
        switch self {
        case .iTerm2, .iTermLegacy:
            return "iTerm"
        case .appleTerminal:
            return "Terminal"
        case .tabby:
            return "Tabby"
        }
    }
}
