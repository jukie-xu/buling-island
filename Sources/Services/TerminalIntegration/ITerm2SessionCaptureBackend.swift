import Foundation

/// iTerm2 专用：AppleScript 枚举会话与 `contents` 尾窗。
final class ITerm2SessionCaptureBackend: TerminalSessionCaptureBackend, @unchecked Sendable {
    let backendIdentifier = "com.buling.capture.iterm2"
    let shortLabel = "iTerm2"
    let supportedTerminalKinds: Set<TerminalKind> = [.iTerm2]

    nonisolated func fetchSessions() -> TerminalSessionFetchResult {
        let script = """
        set fieldSep to character id 31
        set recordSep to character id 30
        set outText to ""
        tell application "iTerm2"
            -- 勿用 oneWin/oneTab：AppleScript 会把 one 与后续拆词，触发「预期是 ,」类错误。
            repeat with eachWin in (get windows)
                try
                    set winTabs to tabs of eachWin
                    repeat with eachTab in winTabs
                        set sessionList to sessions of eachTab
                        repeat with sessionRef in sessionList
                            set sid to (unique id of sessionRef as text)
                            set stitle to (name of sessionRef as text)
                            set stty to ""
                            try
                                set stty to (tty of sessionRef as text)
                            end try
                            set bodyText to ""
                            -- 与 Terminal.app 对齐：非前台标签下可视区 API 常不可靠；优先滚动缓冲（若宿主支持 `history`），再回退 `contents`/`text`。
                            try
                                set bodyText to (history of sessionRef as text)
                            on error
                                set bodyText to ""
                            end try
                            if bodyText is "" then
                                try
                                    set bodyText to (contents of sessionRef as text)
                                on error
                                    try
                                        set bodyText to (text of sessionRef as text)
                                    on error
                                        set bodyText to ""
                                    end try
                                end try
                            end if
                            set tailText to bodyText
                            set charCount to count of tailText
                            if charCount > 12000 then
                                set tailText to text (charCount - 11999) thru -1 of tailText
                            end if
                            set one to sid & fieldSep & "iTerm2" & fieldSep & stitle & fieldSep & stty & fieldSep & tailText
                            if outText is "" then
                                set outText to one
                            else
                                set outText to outText & recordSep & one
                            end if
                        end repeat
                    end repeat
                end try
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
        guard terminalKind == .iTerm2 else { return }
        let sessionID = nativeSessionId.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        set targetID to "\(sessionID)"
        tell application "System Events"
            if not (exists process "iTerm2") then
                return "__APP_NOT_RUNNING__"
            end if
        end tell
        tell application "iTerm2"
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
        guard terminalKind == .iTerm2 else { return false }
        let sessionID = nativeSessionId.replacingOccurrences(of: "\"", with: "\\\"")
        let payload = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let newlineFlag = submit ? "YES" : "NO"
        let script = """
        set targetID to "\(sessionID)"
        set payload to "\(payload)"
        tell application "System Events"
            if not (exists process "iTerm2") then
                return "__APP_NOT_RUNNING__"
            end if
        end tell
        tell application "iTerm2"
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

    nonisolated func sendActions(
        nativeSessionId: String,
        terminalKind: TerminalKind,
        actions: [TaskInteractionOption.Action]
    ) -> Bool {
        guard terminalKind == .iTerm2, !actions.isEmpty else { return false }
        let sessionID = nativeSessionId.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        set targetID to "\(sessionID)"
        tell application "System Events"
            if not (exists process "iTerm2") then
                return "__APP_NOT_RUNNING__"
            end if
        end tell
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set matches to (sessions of t whose unique id is targetID)
                        if (count of matches) is not 0 then
                            set s to item 1 of matches
                            select s
                            select t
                            exit repeat
                        end if
                    end try
                end repeat
            end repeat
        end tell
        delay 0.05
        tell application "System Events"
            tell process "iTerm2"
        \(appleScriptActionLines(actions, indentation: "                "))
            end tell
        end tell
        return "__OK__"
        """
        DispatchQueue.global(qos: .userInitiated).async {
            _ = TerminalAppleScript.runReturningStdout(script)
        }
        return true
    }

    private nonisolated func appleScriptActionLines(
        _ actions: [TaskInteractionOption.Action],
        indentation: String = "    "
    ) -> String {
        actions.compactMap { action in
            switch action.kind {
            case .text:
                guard let text = action.text, !text.isEmpty else { return nil }
                let payload = text
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "\(indentation)keystroke \"\(payload)\""
            case .specialKey:
                guard let key = action.specialKey else { return nil }
                return "\(indentation)key code \(keyCode(for: key))"
            case .activate:
                return nil
            }
        }
        .joined(separator: "\n")
    }

    private nonisolated func keyCode(for key: TaskInteractionOption.SpecialKey) -> Int {
        switch key {
        case .enter: return 36
        case .escape: return 53
        case .tab: return 48
        case .space: return 49
        case .arrowUp: return 126
        case .arrowDown: return 125
        case .arrowLeft: return 123
        case .arrowRight: return 124
        }
    }
}
