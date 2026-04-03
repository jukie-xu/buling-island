import Foundation

/// 单一终端产品与宿主通信的扩展点：快照轮询 + 激活会话。
/// 新增终端时：实现本协议并在 `TerminalCaptureService` 中注册即可。
/// 具体类建议标注 `@unchecked Sendable`，以便在后台队列合并轮询结果。
protocol TerminalSessionCaptureBackend: AnyObject, Sendable {
    /// 稳定标识，写入 `CapturedTerminalSession.backendIdentifier`， Persist 静音键等。
    var backendIdentifier: String { get }
    /// 错误文案、调试日志用短名。
    var shortLabel: String { get }
    /// 本后端负责的终端种类（用于在宿主未运行时短路抓取，避免误报）。
    var supportedTerminalKinds: Set<TerminalKind> { get }

    nonisolated func fetchSessions() -> TerminalSessionFetchResult

    /// 在用户点击外部会话条时，将焦点切到对应宿主窗口（具体实现因 App 而异）。
    nonisolated func activate(nativeSessionId: String, terminalKind: TerminalKind)

    /// 向目标会话注入输入（可选回车执行）。返回 false 表示当前后端不支持该能力。
    nonisolated func sendInput(nativeSessionId: String, terminalKind: TerminalKind, text: String, submit: Bool) -> Bool
}

extension TerminalSessionCaptureBackend {
    nonisolated func sendInput(nativeSessionId: String, terminalKind: TerminalKind, text: String, submit: Bool) -> Bool {
        _ = nativeSessionId
        _ = terminalKind
        _ = text
        _ = submit
        return false
    }
}
