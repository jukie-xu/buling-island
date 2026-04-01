import Foundation

@MainActor
final class ITerm2IntegrationService: ObservableObject {
    struct Session: Identifiable {
        let id: String
        let terminalApp: String
        let title: String
        let tty: String
        let tailOutput: String
    }

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var isITerm2Running: Bool = false
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var latestStatusText: String?
    @Published private(set) var latestStatusTone: String = "info"
    @Published private(set) var latestStatusSourceSessionID: String?
    @Published private(set) var latestStatusSourceTail: String?
    @Published private(set) var interactionHint: String?
    @Published private(set) var lastError: String?
    @Published private(set) var statusRevision: Int = 0
    @Published private(set) var mutedSessionIDs: Set<String> = []
    @Published private(set) var activeSessionIDs: Set<String> = []

    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 1.5
    private var inFlight = false
    private var consecutiveFailures = 0
    private var sessionDigest: [String: Int] = [:]
    private var sessionLastChangedAt: [String: Date] = [:]
    private var acknowledgedErrorUntil: [String: Date] = [:]
    private var acknowledgedSessionSignatureUntil: [String: Date] = [:]
    private let mutedSessionDefaultsKey = "itermMutedSessionIDs"

    init() {
        if let saved = UserDefaults.standard.array(forKey: mutedSessionDefaultsKey) as? [String] {
            mutedSessionIDs = Set(saved)
        }
    }

    func updateConfig(enabled: Bool, pollInterval: TimeInterval) {
        self.pollInterval = max(1.0, min(5.0, pollInterval))
        if enabled == isEnabled {
            if enabled {
                restartTimer(interval: currentEffectiveInterval())
            } else {
                stop()
            }
            return
        }
        enabled ? start() : stop()
    }

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        restartTimer(interval: currentEffectiveInterval())
        pollNow()
    }

    func stop() {
        isEnabled = false
        pollTimer?.invalidate()
        pollTimer = nil
        inFlight = false
        consecutiveFailures = 0
        isITerm2Running = false
        sessions = []
        latestStatusText = nil
        latestStatusTone = "info"
        latestStatusSourceSessionID = nil
        latestStatusSourceTail = nil
        interactionHint = nil
        lastError = nil
        acknowledgedErrorUntil.removeAll()
        acknowledgedSessionSignatureUntil.removeAll()
        sessionLastChangedAt.removeAll()
        activeSessionIDs = []
        statusRevision &+= 1
    }

    func acknowledgeCurrentIssue(for session: Session) {
        let key = errorKey(for: session.id, tail: session.tailOutput)
        guard !key.isEmpty else { return }
        acknowledgedErrorUntil[key] = Date().addingTimeInterval(180)
        if let sig = sessionErrorSignature(for: session.id, tail: session.tailOutput) {
            acknowledgedSessionSignatureUntil[sig] = Date().addingTimeInterval(180)
        }
        statusRevision &+= 1
    }

    func acknowledgeAllCurrentIssues() {
        var affected = 0
        for session in sessions {
            let key = errorKey(for: session.id, tail: session.tailOutput)
            guard !key.isEmpty else { continue }
            acknowledgedErrorUntil[key] = Date().addingTimeInterval(180)
            if let sig = sessionErrorSignature(for: session.id, tail: session.tailOutput) {
                acknowledgedSessionSignatureUntil[sig] = Date().addingTimeInterval(180)
            }
            affected += 1
        }
        if affected > 0 {
            statusRevision &+= 1
        }
    }

    func isSessionMuted(_ sessionID: String) -> Bool {
        mutedSessionIDs.contains(sessionID)
    }

    func setSessionMuted(_ muted: Bool, sessionID: String) {
        if muted {
            mutedSessionIDs.insert(sessionID)
        } else {
            mutedSessionIDs.remove(sessionID)
        }
        UserDefaults.standard.set(Array(mutedSessionIDs), forKey: mutedSessionDefaultsKey)
        statusRevision &+= 1
    }

    func activate(session: Session) {
        let sessionID = session.id.replacingOccurrences(of: "\"", with: "\\\"")
        let appName = session.terminalApp.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        set targetID to "\(sessionID)"
        set targetApp to "\(appName)"
        if targetApp is "iTerm2" then
            tell application "System Events"
                if not (exists process "iTerm2") then
                    return "__APP_NOT_RUNNING__"
                end if
            end tell
            tell application "iTerm2"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if (unique id of s as text) is targetID then
                                    select s
                                    select t
                                    return "__OK__"
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end tell
        else if targetApp is "iTerm" then
            tell application "System Events"
                if not (exists process "iTerm") then
                    return "__APP_NOT_RUNNING__"
                end if
            end tell
            tell application "iTerm"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if (unique id of s as text) is targetID then
                                    select s
                                    select t
                                    return "__OK__"
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end tell
        else
            return "__APP_NOT_SUPPORTED__"
        end if
        return "__SESSION_NOT_FOUND__"
        """

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
                process.waitUntilExit()
                let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if process.terminationStatus == 0, out == "__OK__" {
                    } else if out == "__APP_NOT_RUNNING__" {
                    } else if out == "__APP_NOT_SUPPORTED__" {
                    } else if out == "__SESSION_NOT_FOUND__" {
                    } else if !err.isEmpty {
                    } else {
                    }
                    self.statusRevision &+= 1
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.statusRevision &+= 1
                }
            }
        }
    }

    private func currentEffectiveInterval() -> TimeInterval {
        if consecutiveFailures <= 0 { return pollInterval }
        return min(5, pollInterval + Double(consecutiveFailures) * 0.6)
    }

    private func restartTimer(interval: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollNow()
            }
        }
    }

    private func pollNow() {
        guard isEnabled else { return }
        guard !inFlight else { return }
        inFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = Self.fetchSnapshotFromITerm2()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                self.consume(snapshot: result)
            }
        }
    }

    private func consume(snapshot: SnapshotResult) {
        guard isEnabled else { return }
        switch snapshot {
        case .notRunning:
            isITerm2Running = false
            sessions = []
            latestStatusText = nil
            latestStatusTone = "info"
            latestStatusSourceSessionID = nil
            latestStatusSourceTail = nil
            interactionHint = nil
            lastError = nil
            activeSessionIDs = []
            statusRevision &+= 1
            consecutiveFailures = 0
            restartTimer(interval: currentEffectiveInterval())

        case .success(let rows):
            isITerm2Running = true
            consecutiveFailures = 0
            restartTimer(interval: currentEffectiveInterval())

            let mapped = rows.map { row in
                Session(
                    id: row.id,
                    terminalApp: row.terminalApp,
                    title: row.title,
                    tty: row.tty,
                    tailOutput: row.tail
                )
            }
            sessions = mapped

            var bestStatus: (score: Int, text: String, tone: String, rowID: String, tail: String)?
            let now = Date()
            for row in rows {
                if isSessionMuted(row.id) {
                    continue
                }
                let digest = row.tail.hashValue
                if sessionDigest[row.id] == digest {
                    continue
                }
                sessionDigest[row.id] = digest
                sessionLastChangedAt[row.id] = now
                let analysis = analyzeStatus(text: row.tail)
                if analysis.tone == "error" || analysis.tone == "warn" || analysis.tone == "success" {
                    if analysis.tone == "error" {
                        let key = errorKey(for: row.id, tail: row.tail)
                        if let until = acknowledgedErrorUntil[key], until > Date() {
                            continue
                        }
                        if let sig = sessionErrorSignature(for: row.id, tail: row.tail),
                           let until = acknowledgedSessionSignatureUntil[sig],
                           until > Date() {
                            continue
                        }
                    }
                    let score = statusPriority(analysis.tone)
                    if bestStatus == nil || score > bestStatus!.score {
                        bestStatus = (score, analysis.text, analysis.tone, row.id, row.tail)
                    }
                } else if interactionHint == nil, analysis.tone == "busy" {
                    let score = statusPriority(analysis.tone)
                    if bestStatus == nil || score > bestStatus!.score {
                        bestStatus = (score, analysis.text, analysis.tone, row.id, row.tail)
                    }
                }
            }

            // 输出内容在短窗口内持续变化，判定为运行中。
            activeSessionIDs = Set(
                sessionLastChangedAt
                    .filter { now.timeIntervalSince($0.value) <= 6.0 }
                    .map(\.key)
            )

            if let bestStatus {
                latestStatusText = bestStatus.text
                latestStatusTone = bestStatus.tone
                latestStatusSourceSessionID = bestStatus.rowID
                latestStatusSourceTail = bestStatus.tail
                if bestStatus.tone == "warn" {
                    interactionHint = bestStatus.text
                }
                statusRevision &+= 1
            }

        case .failure(let reason):
            consecutiveFailures = min(5, consecutiveFailures + 1)
            restartTimer(interval: currentEffectiveInterval())
            lastError = "iTerm2 捕获失败: \(reason)"
            latestStatusText = "iTerm2 捕获失败"
            latestStatusTone = "error"
            latestStatusSourceSessionID = nil
            latestStatusSourceTail = nil
            statusRevision &+= 1
        }
    }

    private func analyzeStatus(text: String) -> (text: String, tone: String) {
        let outputLines = normalizedOutputLines(from: text)
        let compact = outputLines.suffix(6).joined(separator: " ")
        let lower = compact.lowercased()

        if compact.isEmpty {
            return ("暂无可分析输出", "info")
        }

        if lower.contains("error") || lower.contains("failed") || lower.contains("exception")
            || lower.contains("auth_error") || lower.contains("401") || lower.contains("unauthorized")
            || lower.contains("报错") || lower.contains("失败") || lower.contains("错误") {
            return ("错误: \(truncate(compact, max: 42))", "error")
        }
        if lower.contains("allow") || lower.contains("approve") || lower.contains("[y/n]") || lower.contains("(y/n)")
            || lower.contains("请确认") || lower.contains("请选择") || lower.contains("是否允许") {
            return ("等待确认: \(truncate(compact, max: 42))", "warn")
        }
        if lower.contains("billowing") || lower.contains("thinking") || lower.contains("analyzing")
            || lower.contains("executing") || lower.contains("processing") || lower.contains("处理中") {
            return ("执行中: \(truncate(compact, max: 42))", "busy")
        }
        if lower.contains("done") || lower.contains("completed") || lower.contains("success")
            || lower.contains("已完成") || lower.contains("成功") {
            return ("已完成: \(truncate(compact, max: 42))", "success")
        }
        if lower.contains("running") || lower.contains("processing") || lower.contains("executing")
            || lower.contains("thinking") || lower.contains("处理中") || lower.contains("执行中") {
            return ("执行中: \(truncate(compact, max: 42))", "busy")
        }
        return (truncate(compact, max: 42), "info")
    }

    private func normalizedOutputLines(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            // 过滤用户输入行，避免把用户输入的 401/json 当异常。
            .filter { !isUserInputCommandLine($0) }
    }

    private func isUserInputCommandLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("❯") || trimmed.hasPrefix(">") {
            return true
        }
        return false
    }

    private func statusPriority(_ tone: String) -> Int {
        switch tone {
        case "error": return 4
        case "warn": return 3
        case "success": return 2
        case "busy": return 1
        default: return 0
        }
    }

    private func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
    }

    private func errorKey(for sessionID: String, tail: String) -> String {
        let line = extractLastErrorLine(from: tail)
        guard !line.isEmpty else { return "" }
        return "\(sessionID)|\(normalizeErrorLine(line))"
    }

    private func sessionErrorSignature(for sessionID: String, tail: String) -> String? {
        let line = extractLastErrorLine(from: tail)
        guard !line.isEmpty else { return nil }
        return "\(sessionID)|\(normalizeErrorLine(line))"
    }

    private func extractLastErrorLine(from tail: String) -> String {
        let lines = tail
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let markers = ["error", "failed", "exception", "unauthorized", "auth_error", "401", "timeout", "报错", "失败", "错误", "超时"]
        for line in lines.reversed() {
            let lower = line.lowercased()
            if markers.contains(where: { lower.contains($0) }) {
                return line
            }
        }
        return ""
    }

    private func normalizeErrorLine(_ line: String) -> String {
        var s = line.lowercased()
        s = s.replacingOccurrences(of: "[0-9a-f]{6,}", with: "#", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\b\\d+\\b", with: "#", options: .regularExpression)
        return s
    }

    private struct SnapshotRow {
        let id: String
        let terminalApp: String
        let title: String
        let tty: String
        let tail: String
    }

    private enum SnapshotResult {
        case success([SnapshotRow])
        case notRunning
        case failure(String)
    }

    nonisolated private static func fetchSnapshotFromITerm2() -> SnapshotResult {
        let script = """
        set fieldSep to character id 31
        set recordSep to character id 30
        set hasITerm2 to false
        set hasITerm to false
        tell application "System Events"
            if exists process "iTerm2" then
                set hasITerm2 to true
            end if
            if exists process "iTerm" then
                set hasITerm to true
            end if
        end tell
        if (hasITerm2 is false) and (hasITerm is false) then
            return "__NOT_RUNNING__"
        end if

        set outText to ""
        if hasITerm2 then
            tell application "iTerm2"
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
                                set bodyText to (contents of s as text)
                            end try
                            set tailText to bodyText
                            if (count of characters of tailText) > 12000 then
                                set tailText to text -12000 thru -1 of tailText
                            end if
                            set one to sid & fieldSep & "iTerm2" & fieldSep & stitle & fieldSep & stty & fieldSep & tailText
                            if outText is "" then
                                set outText to one
                            else
                                set outText to outText & recordSep & one
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
        end if

        if hasITerm then
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
                                set bodyText to (contents of s as text)
                            end try
                            set tailText to bodyText
                            if (count of characters of tailText) > 12000 then
                                set tailText to text -12000 thru -1 of tailText
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
        end if
        return outText
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let error = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus != 0 {
                return .failure(error.isEmpty ? "osascript 退出码 \(process.terminationStatus)" : error)
            }
            if output == "__NOT_RUNNING__" {
                return .notRunning
            }
            if output.isEmpty {
                return .success([])
            }
            let recordSeparator = Character(UnicodeScalar(30)!)
            let fieldSeparator = String(Character(UnicodeScalar(31)!))
            let rows = output
                .split(separator: recordSeparator)
                .map { String($0) }
                .compactMap { line -> SnapshotRow? in
                    let parts = line.components(separatedBy: fieldSeparator)
                    guard parts.count >= 5 else { return nil }
                    return SnapshotRow(
                        id: parts[0],
                        terminalApp: parts[1],
                        title: parts[2],
                        tty: parts[3],
                        tail: parts.dropFirst(4).joined(separator: "||")
                    )
                }
            return .success(rows)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
