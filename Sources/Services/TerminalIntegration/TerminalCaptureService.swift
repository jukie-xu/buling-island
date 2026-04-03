import Foundation

/// 聚合多个 `TerminalSessionCaptureBackend` 的轮询与 UI 状态；对外保持与原 `ITerm2IntegrationService` 相当的观察接口。
@MainActor
final class TerminalCaptureService: ObservableObject {

    @Published private(set) var isEnabled: Bool = false
    /// 至少有一个后端已成功连上其终端宿主（允许当前 0 条会话）。
    @Published private(set) var isTerminalHostReachable: Bool = false
    @Published private(set) var sessions: [CapturedTerminalSession] = []
    @Published private(set) var latestStatusText: String?
    @Published private(set) var latestStatusTone: String = "info"
    @Published private(set) var latestStatusSourceSessionID: String?
    @Published private(set) var latestStatusSourceTail: String?
    @Published private(set) var interactionHint: String?
    @Published private(set) var lastError: String?
    @Published private(set) var statusRevision: Int = 0
    @Published private(set) var mutedSessionIDs: Set<String> = []
    @Published private(set) var activeSessionIDs: Set<String> = []

    private let backends: [TerminalSessionCaptureBackend]
    private let hostHealthProbes: [TerminalHostHealthProbe]
    private var signalParsers: [any TerminalSessionSignalParser]
    private let backendById: [String: TerminalSessionCaptureBackend]

    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 1.5
    private var inFlight = false
    private var consecutiveFailures = 0
    private var sessionDigest: [String: Int] = [:]
    private var sessionLastChangedAt: [String: Date] = [:]
    private var acknowledgedErrorUntil: [String: Date] = [:]
    private var acknowledgedSessionSignatureUntil: [String: Date] = [:]
    /// 历史键名保留，避免用户升级后静音列表清空。
    private let mutedSessionDefaultsKey = "itermMutedSessionIDs"

    init(
        backends: [TerminalSessionCaptureBackend],
        hostHealthProbes: [TerminalHostHealthProbe],
        signalParsers: [any TerminalSessionSignalParser]
    ) {
        self.backends = backends
        self.hostHealthProbes = hostHealthProbes
        var seen = Set<String>()
        self.signalParsers = signalParsers
            .filter { seen.insert($0.parserID).inserted }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.parserID < rhs.parserID
                }
                return lhs.priority > rhs.priority
            }
        self.backendById = Dictionary(uniqueKeysWithValues: backends.map { ($0.backendIdentifier, $0) })
        if let saved = UserDefaults.standard.array(forKey: mutedSessionDefaultsKey) as? [String] {
            mutedSessionIDs = Set(saved)
        }
    }

    convenience init() {
        self.init(
            backends: TerminalCaptureBackendRegistry.resolvedBackends(),
            hostHealthProbes: TerminalHostHealthProbeRegistry.resolvedProbes(),
            signalParsers: TerminalSessionSignalParserRegistry.resolvedParsers()
        )
    }

    func replaceSignalParsers(_ parsers: [any TerminalSessionSignalParser]) {
        var seen = Set<String>()
        signalParsers = parsers
            .filter { seen.insert($0.parserID).inserted }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.parserID < rhs.parserID
                }
                return lhs.priority > rhs.priority
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
        isTerminalHostReachable = false
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

    func acknowledgeCurrentIssue(for session: CapturedTerminalSession) {
        let signal = parseSignal(for: session)
        let key = errorKey(for: session.id, signal: signal)
        guard !key.isEmpty else { return }
        acknowledgedErrorUntil[key] = Date().addingTimeInterval(180)
        if let sig = sessionErrorSignature(for: session.id, signal: signal) {
            acknowledgedSessionSignatureUntil[sig] = Date().addingTimeInterval(180)
        }
        statusRevision &+= 1
    }

    func acknowledgeAllCurrentIssues() {
        var affected = 0
        for session in sessions {
            let signal = parseSignal(for: session)
            let key = errorKey(for: session.id, signal: signal)
            guard !key.isEmpty else { continue }
            acknowledgedErrorUntil[key] = Date().addingTimeInterval(180)
            if let sig = sessionErrorSignature(for: session.id, signal: signal) {
                acknowledgedSessionSignatureUntil[sig] = Date().addingTimeInterval(180)
            }
            affected += 1
        }
        if affected > 0 {
            statusRevision &+= 1
        }
    }

    /// `sessionID` 一般为 `CapturedTerminalSession.id`（`backend|native`）；兼容仅保存 `nativeSessionId` 的旧静音项。
    func isSessionMuted(_ sessionID: String) -> Bool {
        if mutedSessionIDs.contains(sessionID) { return true }
        if let r = sessionID.range(of: "|") {
            let native = String(sessionID[r.upperBound...])
            if mutedSessionIDs.contains(native) { return true }
        }
        return false
    }

    func isSessionMuted(session: CapturedTerminalSession) -> Bool {
        isSessionMuted(session.id)
    }

    func setSessionMuted(_ muted: Bool, sessionID: String) {
        if muted {
            mutedSessionIDs.insert(sessionID)
        } else {
            mutedSessionIDs.remove(sessionID)
            // 取消静音时同时移除旧版仅 nativeId 的键，否则 `isSessionMuted` 仍会为 true。
            if let r = sessionID.range(of: "|") {
                mutedSessionIDs.remove(String(sessionID[r.upperBound...]))
            }
        }
        UserDefaults.standard.set(Array(mutedSessionIDs), forKey: mutedSessionDefaultsKey)
        statusRevision &+= 1
    }

    func activate(session: CapturedTerminalSession) {
        guard let backend = backendById[session.backendIdentifier] else { return }
        backend.activate(nativeSessionId: session.nativeSessionId, terminalKind: session.terminalKind)
    }

    @discardableResult
    func sendInput(to session: CapturedTerminalSession, text: String, submit: Bool = true) -> Bool {
        guard let backend = backendById[session.backendIdentifier] else { return false }
        return backend.sendInput(
            nativeSessionId: session.nativeSessionId,
            terminalKind: session.terminalKind,
            text: text,
            submit: submit
        )
    }

    private func currentEffectiveInterval() -> TimeInterval {
        if consecutiveFailures <= 0 { return pollInterval }
        return min(5, pollInterval + Double(consecutiveFailures) * 0.6)
    }

    private func restartTimer(interval: TimeInterval) {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollNow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func pollNow() {
        guard isEnabled else { return }
        guard !inFlight else { return }
        inFlight = true
        let snapshotBackends = backends
        let snapshotProbes = hostHealthProbes
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let merged = Self.mergeBackendFetches(snapshotBackends, probes: snapshotProbes)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                self.consume(merged: merged)
            }
        }
    }

    struct MergedFetch {
        let sessions: [CapturedTerminalSession]
        let runningTerminalKinds: Set<TerminalKind>
        let anyBackendCaptured: Bool
        let scriptErrors: [String]
    }

    nonisolated static func mergeBackendFetches(
        _ backends: [TerminalSessionCaptureBackend],
        probes: [TerminalHostHealthProbe]
    ) -> MergedFetch {
        var sessions: [CapturedTerminalSession] = []
        let runningTerminalKinds = Set(
            probes
                .filter { $0.isHostRunning() }
                .map(\.terminalKind)
        )
        var anyBackendCaptured = false
        var scriptErrors: [String] = []
        for b in backends {
            if runningTerminalKinds.isDisjoint(with: b.supportedTerminalKinds) {
                continue
            }
            switch b.fetchSessions() {
            case .hostNotRunning:
                break
            case .captured(let rows):
                anyBackendCaptured = true
                for r in rows {
                    sessions.append(
                        CapturedTerminalSession(
                            nativeSessionId: r.nativeSessionId,
                            backendIdentifier: b.backendIdentifier,
                            terminalKind: r.terminalKind,
                            title: r.title,
                            tty: r.tty,
                            tailOutput: r.tail
                        )
                    )
                }
            case .scriptFailed(let msg):
                // 各后端对应的终端若根本未启动，脚本可能走到 scriptFailed；与「轮询时所有宿主都未开」视为同一类，不刷药丸红条。
                if TerminalAppleScript.messageIndicatesTerminalAppNotRunning(msg) {
                    break
                }
                scriptErrors.append("\(b.shortLabel): \(msg)")
            }
        }
        return MergedFetch(
            sessions: sessions,
            runningTerminalKinds: runningTerminalKinds,
            anyBackendCaptured: anyBackendCaptured,
            scriptErrors: scriptErrors
        )
    }

    private func consume(merged: MergedFetch) {
        guard isEnabled else { return }

        let hasRunningHost = !merged.runningTerminalKinds.isEmpty
        let shouldTreatAsHealthy = hasRunningHost && (merged.anyBackendCaptured || merged.scriptErrors.isEmpty)

        if shouldTreatAsHealthy {
            consecutiveFailures = 0
            restartTimer(interval: currentEffectiveInterval())
            isTerminalHostReachable = hasRunningHost
            lastError = nil

            let rows = merged.sessions
            sessions = rows

            var bestStatus: (score: Int, text: String, tone: String, rowID: String, tail: String)?
            var hintText: String?
            let now = Date()
            for row in rows {
                if isSessionMuted(session: row) {
                    continue
                }
                let digest = row.tailOutput.hashValue
                if sessionDigest[row.id] == digest {
                    continue
                }
                sessionDigest[row.id] = digest
                sessionLastChangedAt[row.id] = now
                let analysis = parseSignal(for: row)
                if hintText == nil, let hint = analysis.interactionHint, !hint.isEmpty {
                    hintText = hint
                }
                if analysis.tone == "error" || analysis.tone == "warn" || analysis.tone == "success" {
                    if analysis.tone == "error" {
                        let key = errorKey(for: row.id, signal: analysis)
                        if let until = acknowledgedErrorUntil[key], until > Date() {
                            continue
                        }
                        if let sig = sessionErrorSignature(for: row.id, signal: analysis),
                           let until = acknowledgedSessionSignatureUntil[sig],
                           until > Date() {
                            continue
                        }
                    }
                    let score = statusPriority(analysis.tone)
                    if bestStatus == nil || score > bestStatus!.score {
                        bestStatus = (score, analysis.summaryText, analysis.tone, row.id, row.tailOutput)
                    }
                } else if interactionHint == nil, analysis.tone == "busy" {
                    let score = statusPriority(analysis.tone)
                    if bestStatus == nil || score > bestStatus!.score {
                        bestStatus = (score, analysis.summaryText, analysis.tone, row.id, row.tailOutput)
                    }
                }
            }

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
                    interactionHint = hintText ?? bestStatus.text
                } else {
                    interactionHint = hintText
                }
                statusRevision &+= 1
            } else {
                // 本轮无值得推送的状态（例如全部静音或输出未变）；清除「等待确认」类提示，避免卡死在上一次 warn。
                interactionHint = hintText
            }

            return
        }

        isTerminalHostReachable = hasRunningHost
        sessions = []
        latestStatusText = nil
        latestStatusTone = "info"
        latestStatusSourceSessionID = nil
        latestStatusSourceTail = nil
        interactionHint = nil
        activeSessionIDs = []

        if hasRunningHost && !merged.scriptErrors.isEmpty {
            consecutiveFailures = min(5, consecutiveFailures + 1)
            restartTimer(interval: currentEffectiveInterval())
            let reason = merged.scriptErrors.joined(separator: "；")
            lastError = "终端会话捕获失败: \(reason)"
            latestStatusText = "终端会话捕获失败"
            latestStatusTone = "error"
            statusRevision &+= 1
        } else {
            consecutiveFailures = 0
            restartTimer(interval: currentEffectiveInterval())
            lastError = nil
            statusRevision &+= 1
        }
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

    private func parseSignal(for session: CapturedTerminalSession) -> TerminalSessionSignal {
        if let parser = signalParsers.first(where: { $0.supports(session: session) }) {
            return parser.parse(session: session)
        }
        return GenericSessionSignalParser().parse(session: session)
    }

    private func errorKey(for sessionID: String, signal: TerminalSessionSignal) -> String {
        let line = signal.errorFingerprint ?? normalizeErrorLine(signal.summaryText)
        guard !line.isEmpty else { return "" }
        return "\(sessionID)|\(line)"
    }

    private func sessionErrorSignature(for sessionID: String, signal: TerminalSessionSignal) -> String? {
        let line = signal.errorFingerprint ?? normalizeErrorLine(signal.summaryText)
        guard !line.isEmpty else { return nil }
        return "\(sessionID)|\(line)"
    }

    private func normalizeErrorLine(_ line: String) -> String {
        var s = line.lowercased()
        s = s.replacingOccurrences(of: "[0-9a-f]{6,}", with: "#", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\b\\d+\\b", with: "#", options: .regularExpression)
        return s
    }
}
