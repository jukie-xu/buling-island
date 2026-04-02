import XCTest
@testable import BulingIsland

final class TaskSessionStrategyTests: XCTestCase {

    func testClaudeStrategySupportsClaudeSession() {
        let s = ClaudeTaskSessionStrategy()
        let session = CapturedTerminalSession(
            nativeSessionId: "1",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "claude - project",
            tty: "ttys001",
            tailOutput: "Thinking..."
        )
        XCTAssertTrue(s.supports(session: session))
    }

    func testCodexStrategySupportsCodexMarkers() {
        let s = CodexTaskSessionStrategy()
        let session = CapturedTerminalSession(
            nativeSessionId: "2",
            backendIdentifier: "backend",
            terminalKind: .appleTerminal,
            title: "task runner",
            tty: "ttys002",
            tailOutput: "openai codex is analyzing patch"
        )
        XCTAssertTrue(s.supports(session: session))
    }

    @MainActor
    func testEngineChoosesHigherPriorityStrategy() {
        let session = CapturedTerminalSession(
            nativeSessionId: "3",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "codex workspace",
            tty: "ttys003",
            tailOutput: "running"
        )

        let engine = TaskSessionEngine(strategies: [
            GenericTaskSessionStrategy(),
            CodexTaskSessionStrategy(),
        ])
        engine.refresh(sessions: [session], activeSessionIDs: [session.id], now: Date(timeIntervalSince1970: 1000))

        let snap = engine.snapshotsBySessionID[session.id]
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.strategyID, "codex")
        XCTAssertEqual(snap?.lifecycle, .running)
        XCTAssertEqual(snap?.renderTone, .running)
    }
}
