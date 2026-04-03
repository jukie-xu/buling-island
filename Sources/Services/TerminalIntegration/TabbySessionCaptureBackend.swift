import Foundation

/// Tabby：复用外部终端插件架构，通过 `System Events` 枚举窗口并建立会话条。
/// 说明：Tabby 暂未提供稳定 AppleScript 会话 `contents` 接口，因此当前仅提供窗口级会话检测与跳转。
final class TabbySessionCaptureBackend: TerminalSessionCaptureBackend, @unchecked Sendable {
    let backendIdentifier = "com.buling.capture.tabby"
    let shortLabel = "Tabby"
    let supportedTerminalKinds: Set<TerminalKind> = [.tabby]

    nonisolated func fetchSessions() -> TerminalSessionFetchResult {
        let script = """
        set fieldSep to character id 31
        set recordSep to character id 30
        tell application "System Events"
            if not ((exists process "Tabby") or (exists process "tabby")) then
                return "__NOT_RUNNING__"
            end if
            set p to missing value
            if (exists process "Tabby") then
                set p to process "Tabby"
            else
                set p to process "tabby"
            end if
            set outText to ""
            tell p
                set winCount to count of windows
                repeat with wi from 1 to winCount
                    set w to window wi
                    set sid to ""
                    set wid to ""
                    try
                        set wid to (id of w as text)
                    end try
                    if wid is not "" then
                        set sid to wid
                    end if
                    if sid is "" then
                        set wname to ""
                        try
                            set wname to (name of w as text)
                        end try
                        if wname is not "" then
                            set sid to "name:" & wname
                        end if
                    end if
                    if sid is "" then
                        set sid to "index:" & (wi as text)
                    end if

                    set stitle to "Tabby"
                    try
                        set stitle to (name of w as text)
                    end try
                    set stty to ""
                    set bodyText to ""
                    try
                        set allItems to entire contents of w
                        repeat with nodeRef in allItems
                            try
                                if (role of nodeRef as text) is "AXTextArea" then
                                    set v to (value of nodeRef as text)
                                    if v is not "" then
                                        set bodyText to v
                                        exit repeat
                                    end if
                                end if
                            end try
                        end repeat
                        if bodyText is "" then
                            set staticText to ""
                            repeat with nodeRef in allItems
                                try
                                    if (role of nodeRef as text) is "AXStaticText" then
                                        set v to (value of nodeRef as text)
                                        if v is not "" then
                                            if staticText is "" then
                                                set staticText to v
                                            else
                                                set staticText to staticText & linefeed & v
                                            end if
                                        end if
                                    end if
                                end try
                            end repeat
                            set bodyText to staticText
                        end if
                    end try
                    if bodyText is "" then
                        try
                            set txtAreas to (every UI element of w whose role is "AXTextArea")
                            repeat with ta in txtAreas
                                try
                                    set v to (value of ta as text)
                                    if v is not "" then
                                        set bodyText to v
                                        exit repeat
                                    end if
                                end try
                            end repeat
                        end try
                    end if
                    if bodyText is "" then
                        try
                            set staticNodes to (every UI element of w whose role is "AXStaticText")
                            repeat with n in staticNodes
                                try
                                    set v to (value of n as text)
                                    if v is not "" then
                                        if bodyText is "" then
                                            set bodyText to v
                                        else
                                            set bodyText to bodyText & linefeed & v
                                        end if
                                    end if
                                end try
                            end repeat
                        end try
                    end if
                    set tailText to bodyText
                    set charCount to count of tailText
                    if charCount > 12000 then
                        set tailText to text (charCount - 11999) thru -1 of tailText
                    end if
                    set one to sid & fieldSep & "Tabby" & fieldSep & stitle & fieldSep & stty & fieldSep & tailText
                    if outText is "" then
                        set outText to one
                    else
                        set outText to outText & recordSep & one
                    end if
                end repeat
            end tell
            return outText
        end tell
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
        guard terminalKind == .tabby else { return }
        let escaped = nativeSessionId
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        set targetID to "\(escaped)"
        tell application "System Events"
            if not ((exists process "Tabby") or (exists process "tabby")) then
                return "__APP_NOT_RUNNING__"
            end if
            set p to missing value
            if (exists process "Tabby") then
                set p to process "Tabby"
            else
                set p to process "tabby"
            end if
            tell p
                set frontmost to true
                set winCount to count of windows
                repeat with wi from 1 to winCount
                    set w to window wi
                    set wid to ""
                    try
                        set wid to (id of w as text)
                    end try
                    set wname to ""
                    try
                        set wname to (name of w as text)
                    end try
                    set matched to false
                    if wid is not "" then
                        if wid is targetID then set matched to true
                        if ("id:" & wid) is targetID then set matched to true
                    end if
                    if wname is not "" then
                        if wname is targetID then set matched to true
                        if ("name:" & wname) is targetID then set matched to true
                    end if
                    if ("index:" & (wi as text)) is targetID then set matched to true
                    if matched then
                        perform action "AXRaise" of w
                        return "__OK__"
                    end if
                end repeat
            end tell
        end tell
        tell application "Tabby" to activate
        return "__SESSION_NOT_FOUND__"
        """
        DispatchQueue.global(qos: .userInitiated).async {
            _ = TerminalAppleScript.runReturningStdout(script)
        }
    }

    nonisolated func sendInput(nativeSessionId: String, terminalKind: TerminalKind, text: String, submit: Bool) -> Bool {
        guard terminalKind == .tabby else { return false }
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
        tell application "System Events"
            if not ((exists process "Tabby") or (exists process "tabby")) then
                return "__APP_NOT_RUNNING__"
            end if
            set p to missing value
            if (exists process "Tabby") then
                set p to process "Tabby"
            else
                set p to process "tabby"
            end if
            tell p
                set frontmost to true
                set winCount to count of windows
                repeat with wi from 1 to winCount
                    set w to window wi
                    set wid to ""
                    try
                        set wid to (id of w as text)
                    end try
                    set wname to ""
                    try
                        set wname to (name of w as text)
                    end try
                    set matched to false
                    if wid is not "" then
                        if wid is targetID then set matched to true
                        if ("id:" & wid) is targetID then set matched to true
                    end if
                    if wname is not "" then
                        if wname is targetID then set matched to true
                        if ("name:" & wname) is targetID then set matched to true
                    end if
                    if ("index:" & (wi as text)) is targetID then set matched to true
                    if matched then
                        perform action "AXRaise" of w
                        exit repeat
                    end if
                end repeat
            end tell
            keystroke payload
            \(submitLine)
        end tell
        tell application "Tabby" to activate
        return "__OK__"
        """
        DispatchQueue.global(qos: .userInitiated).async {
            _ = TerminalAppleScript.runReturningStdout(script)
        }
        return true
    }
}
