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
        let parser = ClaudeCodexSessionSignalParser()
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

    func testParseSnapshotTableSupportsTabbyTerminalKind() {
        let fieldSep = String(Character("\u{001F}"))
        let row = [
            "tabby-win-1",
            "Tabby",
            "workspace",
            "",
            ""
        ].joined(separator: fieldSep)

        let parsed = TerminalAppleScript.parseSnapshotTable(row)

        XCTAssertEqual(parsed?.count, 1)
        XCTAssertEqual(parsed?.first?.terminalKind, .tabby)
        XCTAssertEqual(parsed?.first?.nativeSessionId, "tabby-win-1")
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
