import XCTest
@testable import BulingIsland

final class TerminalCaptureServiceTests: XCTestCase {

    func testMergeSkipsBackendWhenHostNotRunning() {
        let backend = MockCaptureBackend(
            supportedKinds: [.iTerm2],
            result: .scriptFailed("permission denied")
        )
        let probe = MockHostProbe(kind: .iTerm2, running: false)

        let merged = TerminalCaptureService.mergeBackendFetches([backend], probes: [probe])

        XCTAssertTrue(merged.runningTerminalKinds.isEmpty)
        XCTAssertFalse(merged.anyBackendCaptured)
        XCTAssertTrue(merged.scriptErrors.isEmpty)
        XCTAssertTrue(merged.sessions.isEmpty)
    }

    func testMergeReportsScriptErrorOnlyWhenHostRunning() {
        let backend = MockCaptureBackend(
            supportedKinds: [.iTerm2],
            result: .scriptFailed("permission denied")
        )
        let probe = MockHostProbe(kind: .iTerm2, running: true)

        let merged = TerminalCaptureService.mergeBackendFetches([backend], probes: [probe])

        XCTAssertEqual(merged.runningTerminalKinds, [.iTerm2])
        XCTAssertFalse(merged.anyBackendCaptured)
        XCTAssertEqual(merged.scriptErrors.count, 1)
        XCTAssertTrue(merged.scriptErrors[0].contains("permission denied"))
    }

    func testSignalParserProducesNormalizedErrorFingerprint() {
        let parser = TaskStrategySessionSignalParser()
        let session = CapturedTerminalSession(
            nativeSessionId: "42",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "codex",
            tty: "ttys001",
            tailOutput: "Request failed with error 401 at job 123456"
        )

        let signal = parser.parse(session: session)

        XCTAssertEqual(signal.tone, "error")
        XCTAssertNotNil(signal.errorFingerprint)
        XCTAssertEqual(signal.errorFingerprint, "request failed with error # at job #")
    }

    func testParseSnapshotTableSupportsAppleTerminalKind() {
        let fieldSep = String(Character("\u{001F}"))
        let row = [
            "1:1",
            "Terminal",
            "workspace",
            "",
            ""
        ].joined(separator: fieldSep)

        let parsed = TerminalAppleScript.parseSnapshotTable(row)

        XCTAssertEqual(parsed?.count, 1)
        XCTAssertEqual(parsed?.first?.terminalKind, .appleTerminal)
        XCTAssertEqual(parsed?.first?.nativeSessionId, "1:1")
    }

    func testWaitingInputSignalUsesFixedManualConfirmationReminder() {
        let parser = TaskStrategySessionSignalParser()
        let session = CapturedTerminalSession(
            nativeSessionId: "approve",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "codex session",
            tty: "/dev/ttys001",
            tailOutput: """
            Would you like to run the following command?
            1. Yes, proceed (y)
            2. No, and tell Codex what to do differently (esc)
            """
        )

        let signal = parser.parse(session: session)

        XCTAssertEqual(signal.tone, "warn")
        XCTAssertEqual(signal.summaryText, "您的任务需要手工确认。")
        XCTAssertEqual(signal.interactionHint, "您的任务需要手工确认。")
    }

    @MainActor
    func testSessionLifecycleTransitionsFromActiveToMissingThenEvicted() {
        let backend = MockCaptureBackend(
            supportedKinds: [.iTerm2],
            result: .captured([
                TerminalSessionRow(
                    nativeSessionId: "42",
                    terminalKind: .iTerm2,
                    title: "codex",
                    tty: "ttys001",
                    tail: "› hi"
                )
            ])
        )
        let probe = MockHostProbe(kind: .iTerm2, running: true)
        let service = TerminalCaptureService(backends: [backend], hostHealthProbes: [probe], signalParsers: [])

        let mergedActive = TerminalCaptureService.mergeBackendFetches([backend], probes: [probe])
        service.performTestConsume(merged: mergedActive)

        XCTAssertEqual(service.sessionLifecycleByID["mock.backend|42"]?.phase, .active)

        let missingBackend = MockCaptureBackend(
            supportedKinds: [.iTerm2],
            result: .captured([])
        )
        let mergedMissing = TerminalCaptureService.mergeBackendFetches([missingBackend], probes: [probe])
        service.performTestConsume(merged: mergedMissing)
        XCTAssertEqual(service.sessionLifecycleByID["mock.backend|42"]?.phase, .missing)

        service.performTestConsume(merged: mergedMissing)
        XCTAssertNil(service.sessionLifecycleByID["mock.backend|42"])
    }

    @MainActor
    func testBusyStatusCanBeKeptFromLifecycleEvenWhenTailDigestDoesNotChange() {
        let backend = MockCaptureBackend(
            supportedKinds: [.iTerm2],
            result: .captured([
                TerminalSessionRow(
                    nativeSessionId: "43",
                    terminalKind: .iTerm2,
                    title: "codex",
                    tty: "ttys001",
                    tail: """
                    › hi
                    • working (reading files)
                    """
                )
            ])
        )
        let probe = MockHostProbe(kind: .iTerm2, running: true)
        let service = TerminalCaptureService(backends: [backend], hostHealthProbes: [probe], signalParsers: [])

        let merged = TerminalCaptureService.mergeBackendFetches([backend], probes: [probe])
        service.performTestConsume(merged: merged)
        XCTAssertEqual(service.latestStatusTone, "busy")

        service.performTestConsume(merged: merged)
        XCTAssertEqual(service.latestStatusTone, "busy")
        XCTAssertEqual(service.latestStatusSourceSessionID, "mock.backend|43")
    }
}

private final class MockCaptureBackend: TerminalSessionCaptureBackend, @unchecked Sendable {
    let backendIdentifier = "mock.backend"
    let shortLabel = "Mock"
    let supportedTerminalKinds: Set<TerminalKind>
    private let result: TerminalSessionFetchResult

    init(supportedKinds: Set<TerminalKind>, result: TerminalSessionFetchResult) {
        self.supportedTerminalKinds = supportedKinds
        self.result = result
    }

    nonisolated func fetchSessions() -> TerminalSessionFetchResult {
        result
    }

    nonisolated func activate(nativeSessionId: String, terminalKind: TerminalKind) {
        _ = nativeSessionId
        _ = terminalKind
    }
}

private struct MockHostProbe: TerminalHostHealthProbe {
    let probeID: String
    let terminalKind: TerminalKind
    let running: Bool

    init(kind: TerminalKind, running: Bool) {
        self.probeID = "mock.probe.\(kind.rawValue)"
        self.terminalKind = kind
        self.running = running
    }

    nonisolated func isHostRunning() -> Bool {
        running
    }
}
