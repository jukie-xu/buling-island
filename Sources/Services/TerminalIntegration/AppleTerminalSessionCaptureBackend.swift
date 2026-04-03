import Foundation

/// macOS 自带 Terminal.app：通过 AppleScript 读取 `history`（滚动缓冲）与 `tty`。
/// 会话键为 `窗口 id` + `标签序号`（`wid:tabIndex`），与 iTerm 的 UUID 不同。
final class AppleTerminalSessionCaptureBackend: TerminalSessionCaptureBackend, @unchecked Sendable {
    let backendIdentifier = "com.buling.capture.apple-terminal"
    let shortLabel = "Terminal"
    let supportedTerminalKinds: Set<TerminalKind> = [.appleTerminal]

    nonisolated func fetchSessions() -> TerminalSessionFetchResult {
        let script = """
        set fieldSep to character id 31
        set recordSep to character id 30
        tell application "System Events"
            if not (exists process "Terminal") then
                return "__NOT_RUNNING__"
            end if
        end tell
        set outText to ""
        tell application "Terminal"
            repeat with w in windows
                set wid to id of w
                set wname to name of w
                set tabCount to count of tabs of w
                repeat with ti from 1 to tabCount
                    set t to tab ti of w
                    set stitle to wname
                    try
                        set ct to custom title of t
                        if ct is not "" then set stitle to ct
                    end try
                    set stty to ""
                    try
                        set stty to tty of t as text
                    end try
                    set bodyText to ""
                    try
                        set bodyText to history of t as text
                    end try
                    set tailText to bodyText
                    set charCount to count of tailText
                    if charCount > 12000 then
                        set tailText to text (charCount - 11999) thru -1 of tailText
                    end if
                    set sid to (wid as text) & ":" & (ti as text)
                    set one to sid & fieldSep & "Terminal" & fieldSep & stitle & fieldSep & stty & fieldSep & tailText
                    if outText is "" then
                        set outText to one
                    else
                        set outText to outText & recordSep & one
                    end if
                end repeat
            end repeat
        end tell
        return outText
        """

        switch TerminalAppleScript.runReturningStdout(script) {
        case .success(let out):
            if out == "__NOT_RUNNING__" {
                return .hostNotRunning
            }
            guard let rows = TerminalAppleScript.parseSnapshotTable(out) else {
                return .scriptFailed("快照解析失败")
            }
            return .captured(rows)
        case .failure(let err):
            switch err {
            case .hostUnreachable:
                return .hostNotRunning
            case .scriptFailed(let msg):
                return .scriptFailed(msg)
            }
        }
    }

    nonisolated func activate(nativeSessionId: String, terminalKind: TerminalKind) {
        guard terminalKind == .appleTerminal else { return }
        let escaped = nativeSessionId
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        set targetID to "\(escaped)"
        set saveTID to AppleScript's text item delimiters
        set AppleScript's text item delimiters to ":"
        set parts to text items of targetID
        set AppleScript's text item delimiters to saveTID
        if (count of parts) is not 2 then return "__BAD_ID__"
        set targetWid to item 1 of parts
        set targetTi to (item 2 of parts as integer)
        tell application "System Events"
            if not (exists process "Terminal") then
                return "__APP_NOT_RUNNING__"
            end if
        end tell
        tell application "Terminal"
            activate
            repeat with w in windows
                if (id of w as text) is targetWid then
                    set selected of tab targetTi of w to true
                    set frontmost of w to true
                    set index of w to 1
                    return "__OK__"
                end if
            end repeat
        end tell
        return "__SESSION_NOT_FOUND__"
        """
        DispatchQueue.global(qos: .userInitiated).async {
            _ = TerminalAppleScript.runReturningStdout(script)
        }
    }

    nonisolated func sendInput(nativeSessionId: String, terminalKind: TerminalKind, text: String, submit: Bool) -> Bool {
        guard terminalKind == .appleTerminal else { return false }
        let escapedID = nativeSessionId
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let payload = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let submitLine = submit ? "key code 36" : ""
        let script = """
        set targetID to "\(escapedID)"
        set payload to "\(payload)"
        set saveTID to AppleScript's text item delimiters
        set AppleScript's text item delimiters to ":"
        set parts to text items of targetID
        set AppleScript's text item delimiters to saveTID
        if (count of parts) is not 2 then return "__BAD_ID__"
        set targetWid to item 1 of parts
        set targetTi to (item 2 of parts as integer)
        tell application "System Events"
            if not (exists process "Terminal") then
                return "__APP_NOT_RUNNING__"
            end if
        end tell
        tell application "Terminal"
            activate
            repeat with w in windows
                if (id of w as text) is targetWid then
                    set selected of tab targetTi of w to true
                    set frontmost of w to true
                    set index of w to 1
                    exit repeat
                end if
            end repeat
        end tell
        tell application "System Events"
            keystroke payload
            \(submitLine)
        end tell
        return "__OK__"
        """
        DispatchQueue.global(qos: .userInitiated).async {
            _ = TerminalAppleScript.runReturningStdout(script)
        }
        return true
    }
}
