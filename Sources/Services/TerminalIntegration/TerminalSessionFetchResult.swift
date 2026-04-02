import Foundation

/// 单次轮询中，某一后端对「宿主是否可达 / 会话列表」的判断。
enum TerminalSessionFetchResult: Equatable {
    /// 目标终端进程未运行或脚本明确判定未启动。
    case hostNotRunning
    /// 已成功从宿主取回快照（含 0 条会话，表示已连接但无窗口会话）。
    case captured([TerminalSessionRow])
    /// AppleScript / 桥接失败。
    case scriptFailed(String)
}

/// 后端内部的行数据，经 `TerminalCaptureService` 转为 `CapturedTerminalSession`。
struct TerminalSessionRow: Equatable {
    let nativeSessionId: String
    let terminalKind: TerminalKind
    let title: String
    let tty: String
    let tail: String
}
