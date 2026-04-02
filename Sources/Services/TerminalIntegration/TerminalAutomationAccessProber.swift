import Foundation

/// 在用户打开任务面板时，向本机发起无害 Apple Event，促使系统弹出「自动化 / 控制其他 App」授权（每个宿主首次一次）。
/// 捕获脚本依赖 `System Events` 与各终端宿主，故按序探测。
enum TerminalAutomationAccessProber {

    private static let throttleLock = NSLock()
    private static var lastProbeUptime: TimeInterval = -1e9
    /// 避免在模式切换动画间重复触发多次 osascript。
    private static let throttleInterval: TimeInterval = 8

    /// 应用冷启动时调用一次（无节流），促使系统依次弹出「自动化 / 控制其他 App」授权向导。
    static func requestPromptsAtApplicationLaunch() {
        DispatchQueue.global(qos: .userInitiated).async {
            probeSystemEvents()
            for kind in TerminalKind.allCases {
                probeTerminal(kind: kind)
            }
        }
    }

    /// 在后台队列执行，不阻塞 UI。
    static func requestPromptsForSupportedTerminalHosts() {
        let now = ProcessInfo.processInfo.systemUptime
        throttleLock.lock()
        if now - lastProbeUptime < throttleInterval {
            throttleLock.unlock()
            return
        }
        lastProbeUptime = now
        throttleLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            probeSystemEvents()
            for kind in TerminalKind.allCases {
                probeTerminal(kind: kind)
            }
        }
    }

    private nonisolated static func probeSystemEvents() {
        let script = """
        try
            tell application id "com.apple.systemevents"
                get version
            end tell
        end try
        """
        _ = TerminalAppleScript.runReturningStdout(script)
    }

    private nonisolated static func probeTerminal(kind: TerminalKind) {
        let script: String
        if let bid = kind.automationBundleIdentifier {
            let escaped = bid.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            script = """
            try
                tell application id "\(escaped)"
                    get version
                end tell
            end try
            """
        } else {
            let name = kind.appleScriptApplicationName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            script = """
            try
                tell application "\(name)"
                    get version
                end tell
            end try
            """
        }
        _ = TerminalAppleScript.runReturningStdout(script)
    }
}
