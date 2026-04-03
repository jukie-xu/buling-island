import Foundation

/// 经「终端捕获」聚合后的统一会话模型（跨后端唯一 `id`）。
struct CapturedTerminalSession: Identifiable, Hashable {
    /// 后端分配的原始会话 ID（例如 AppleScript `unique id`）。
    let nativeSessionId: String
    /// 捕获后端标识，对应 `TerminalSessionCaptureBackend.backendIdentifier`。
    let backendIdentifier: String
    let terminalKind: TerminalKind
    let title: String
    let tty: String
    let tailOutput: String
    /// 统一标准化后的终端文本。初始化时预计算，避免上层重复访问时反复整段标准化。
    let standardizedTailOutput: String

    init(
        nativeSessionId: String,
        backendIdentifier: String,
        terminalKind: TerminalKind,
        title: String,
        tty: String,
        tailOutput: String
    ) {
        self.nativeSessionId = nativeSessionId
        self.backendIdentifier = backendIdentifier
        self.terminalKind = terminalKind
        self.title = title
        self.tty = tty
        self.tailOutput = tailOutput
        self.standardizedTailOutput = TaskSessionTextToolkit.standardizedTerminalText(from: tailOutput)
    }

    /// SwiftUI / 状态合并用稳定键；跨后端全局唯一。
    var id: String { "\(backendIdentifier)|\(nativeSessionId)" }

    /// 静音列表在 UserDefaults 中存储的键（新格式）；兼容逻辑见 `TerminalCaptureService`。
    var muteStorageKey: String { id }

    /// 会话条等区域仍可按「应用品牌」分组（与历史 `terminalApp` 字符串行为一致）。
    var captureGroupKey: String { terminalKind.captureGroupLabel }
}
