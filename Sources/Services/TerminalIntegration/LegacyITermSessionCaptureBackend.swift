import Foundation

/// 经典 iTerm（非 iTerm2）会话枚举，AppleScript 表面与 iTerm2 相近但 `tell application` 不同。
final class LegacyITermSessionCaptureBackend: TerminalSessionCaptureBackend, @unchecked Sendable {
    let backendIdentifier = "com.buling.capture.iterm-legacy"
    let shortLabel = "iTerm"
    let supportedTerminalKinds: Set<TerminalKind> = [.iTermLegacy]

    nonisolated func fetchSessions() -> TerminalSessionFetchResult {
        let script = """
        set fieldSep to character id 31
        set recordSep to character id 30
        tell application "System Events"
            if not (exists process "iTerm") then
                return "__NOT_RUNNING__"
            end if
        end tell
        set outText to ""
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sid to (unique id of s as text)
                        set stitle to (name of s as text)
                        set stty to ""
                        try
                            set stty to (tty of s as text)
                        end try
                        set bodyText to ""
                        try
                            set bodyText to (text of s as text)
                        on error
                            try
                                set bodyText to (contents of s as text)
                            on error
                                set bodyText to ""
                            end try
                        end try
                        set tailText to bodyText
                        set charCount to count of tailText
                        if charCount > 12000 then
                            set tailText to text (charCount - 11999) thru -1 of tailText
                        end if
                        set one to sid & fieldSep & "iTerm" & fieldSep & stitle & fieldSep & stty & fieldSep & tailText
                        if outText is "" then
                            set outText to one
                        else
                            set outText to outText & recordSep & one
                        end if
                    end repeat
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
        guard terminalKind == .iTermLegacy else { return }
        let sessionID = nativeSessionId.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        set targetID to "\(sessionID)"
        tell application "System Events"
            if not (exists process "iTerm") then
                return "__APP_NOT_RUNNING__"
            end if
        end tell
        tell application "iTerm"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set matches to (sessions of t whose unique id is targetID)
                        if (count of matches) is not 0 then
                            set s to item 1 of matches
                            select s
                            select t
                            return "__OK__"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "__SESSION_NOT_FOUND__"
        """
        DispatchQueue.global(qos: .userInitiated).async {
            _ = TerminalAppleScript.runReturningStdout(script)
        }
    }

    nonisolated func sendInput(nativeSessionId: String, terminalKind: TerminalKind, text: String, submit: Bool) -> Bool {
        guard terminalKind == .iTermLegacy else { return false }
        let sessionID = nativeSessionId.replacingOccurrences(of: "\"", with: "\\\"")
        let payload = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let newlineFlag = submit ? "YES" : "NO"
        let script = """
        set targetID to "\(sessionID)"
        set payload to "\(payload)"
        tell application "System Events"
            if not (exists process "iTerm") then
                return "__APP_NOT_RUNNING__"
            end if
        end tell
        tell application "iTerm"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set matches to (sessions of t whose unique id is targetID)
                        if (count of matches) is not 0 then
                            set s to item 1 of matches
                            select s
                            select t
                            tell s to write text payload newline \(newlineFlag)
                            return "__OK__"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "__SESSION_NOT_FOUND__"
        """
        DispatchQueue.global(qos: .userInitiated).async {
            _ = TerminalAppleScript.runReturningStdout(script)
        }
        return true
    }
}
