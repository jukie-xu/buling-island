import XCTest
@testable import BulingIsland

final class TaskSessionStrategyTests: XCTestCase {

    private func strategy(_ id: String) throws -> ConfigurableTaskSessionStrategy {
        try XCTUnwrap(TaskStrategyFileLoader.configurableStrategy(strategyID: id), "missing bundled strategy: \(id)")
    }

    func testClaudeStrategySupportsClaudeSession() throws {
        let s = try strategy("claude")
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

    func testCodexStrategySupportsCodexMarkers() throws {
        let s = try strategy("codex")
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

    func testCodexSupportNoLongerMatchesGenericAssistantWord() throws {
        let s = try strategy("codex")
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

    func testClaudeAndCodexCanClassifySameTailDifferently() throws {
        let claude = try strategy("claude")
        let codex = try strategy("codex")
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

    func testCodexWaitingIncludesInteractionOptions() throws {
        let codex = try strategy("codex")
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
        XCTAssertEqual(result.interactionOptions.map(\.input), ["y", ""])
        XCTAssertEqual(result.interactionPrompt?.title, "do you want to allow this action?")
        XCTAssertEqual(result.interactionPrompt?.selectionMode, .single)
    }

    @MainActor
    func testEngineChoosesHigherPriorityStrategy() throws {
        let generic = try XCTUnwrap(TaskStrategyFileLoader.configurableStrategy(strategyID: "generic"))
        let codex = try XCTUnwrap(TaskStrategyFileLoader.configurableStrategy(strategyID: "codex"))

        let session = CapturedTerminalSession(
            nativeSessionId: "3",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "codex workspace",
            tty: "ttys003",
            tailOutput: "• working (tests)"
        )

        let engine = TaskSessionEngine(strategies: [generic, codex])
        engine.refresh(sessions: [session], now: Date(timeIntervalSince1970: 1000))

        let snap = engine.snapshotsBySessionID[session.id]
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.strategyID, "codex")
        XCTAssertEqual(snap?.lifecycle, .running)
        XCTAssertEqual(snap?.renderTone, .running)
    }
}
