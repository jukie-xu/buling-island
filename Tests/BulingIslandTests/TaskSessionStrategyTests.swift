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

    func testCodexSupportNoLongerMatchesGenericAssistantWord() {
        let s = CodexTaskSessionStrategy()
        let session = CapturedTerminalSession(
            nativeSessionId: "2b",
            backendIdentifier: "backend",
            terminalKind: .appleTerminal,
            title: "task runner",
            tty: "ttys002",
            tailOutput: "assistant is analyzing your codebase"
        )
        XCTAssertFalse(s.supports(session: session))
    }

    func testClaudeAndCodexCanClassifySameTailDifferently() {
        let claude = ClaudeTaskSessionStrategy()
        let codex = CodexTaskSessionStrategy()
        let session = CapturedTerminalSession(
            nativeSessionId: "4",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "shared terminal",
            tty: "ttys004",
            tailOutput: "tool call: exec_command"
        )

        let claudeState = claude.analyze(session: session).lifecycle
        let codexState = codex.analyze(session: session).lifecycle

        XCTAssertEqual(claudeState, .idle)
        XCTAssertEqual(codexState, .running)
    }

    func testCodexWaitingIncludesInteractionOptions() {
        let codex = CodexTaskSessionStrategy()
        let session = CapturedTerminalSession(
            nativeSessionId: "5",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "codex session",
            tty: "ttys005",
            tailOutput: """
            do you want to allow this action?
            1. Yes, proceed (y)
            2. No, and tell Codex what to do differently (esc)
            """
        )

        let result = codex.analyze(session: session)

        XCTAssertEqual(result.lifecycle, .waitingInput)
        XCTAssertEqual(result.interactionOptions.map(\.input), ["y", "n"])
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
