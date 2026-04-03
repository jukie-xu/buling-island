import XCTest
@testable import BulingIsland

final class TaskStrategyFileConfigTests: XCTestCase {

    func testLoadsBundledStrategyFiles() {
        let loaded = TaskStrategyFileLoader.loadConfiguredStrategies()
        let ids = Set(loaded.map(\.strategyID))
        XCTAssertTrue(ids.contains("claude"))
        XCTAssertTrue(ids.contains("codex"))
        XCTAssertTrue(ids.contains("generic"))
    }

    func testConfigurableStrategyUsesLifecycleSpecificExtraction() throws {
        let json = """
        {
          "strategyID": "demo.tui",
          "displayName": "Demo TUI",
          "priority": 200,
          "supports": {
            "titleContains": ["demo tui"],
            "titleRegex": [],
            "tailContains": [],
            "tailRegex": []
          },
          "lifecycleRules": {
            "error": { "titleContains": [], "titleRegex": [], "tailContains": ["fatal"], "tailRegex": [] },
            "waitingInput": { "titleContains": [], "titleRegex": [], "tailContains": ["approve"], "tailRegex": [] },
            "running": { "titleContains": [], "titleRegex": [], "tailContains": ["working"], "tailRegex": [] },
            "success": { "titleContains": [], "titleRegex": [], "tailContains": ["done"], "tailRegex": [] }
          },
          "defaultLifecycle": "idle",
          "emptyOutput": {
            "lifecycle": "idle",
            "renderTone": "neutral",
            "secondaryText": "idle-empty"
          },
          "extraction": {
            "fallbackText": "fallback",
            "fallbackMaxLength": 88,
            "byLifecycle": {
              "idle": { "mode": "fixedText", "text": "idle-text" },
              "running": { "mode": "fixedText", "text": "running-text" },
              "waitingInput": { "mode": "fixedText", "text": "wait-text" },
              "success": { "mode": "fixedText", "text": "ok-text" },
              "error": { "mode": "fixedText", "text": "err-text" }
            }
          }
        }
        """

        let config = try JSONDecoder().decode(TaskStrategyFileConfig.self, from: Data(json.utf8))
        let strategy = ConfigurableTaskSessionStrategy(config: config)

        let session = CapturedTerminalSession(
            nativeSessionId: "x",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "Demo TUI Session",
            tty: "ttys010",
            tailOutput: "now working"
        )

        let result = strategy.analyze(session: session)
        XCTAssertEqual(result.lifecycle, .running)
        XCTAssertEqual(result.secondaryText, "running-text")
    }

    func testBundledClaudeConfigClassifiesInterruptedAsWaitingInput() {
        let strategies = TaskStrategyFileLoader.loadConfiguredStrategies()
        guard let claude = strategies.first(where: { $0.strategyID == "claude" }) else {
            XCTFail("missing bundled claude strategy")
            return
        }

        let session = CapturedTerminalSession(
            nativeSessionId: "claude-1",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "Claude",
            tty: "ttys001",
            tailOutput: """
            ❯ hi
              ⎿ Interrupted · What should Claude do instead?
            """
        )

        let result = claude.analyze(session: session)
        XCTAssertEqual(result.lifecycle, .waitingInput)
        XCTAssertTrue(result.secondaryText.contains("Interrupted"))
    }

    func testBundledClaudeConfigClassifiesSublimatingAsRunning() {
        let strategies = TaskStrategyFileLoader.loadConfiguredStrategies()
        guard let claude = strategies.first(where: { $0.strategyID == "claude" }) else {
            XCTFail("missing bundled claude strategy")
            return
        }

        let session = CapturedTerminalSession(
            nativeSessionId: "claude-2",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "Claude",
            tty: "ttys002",
            tailOutput: "✻ Sublimating…"
        )

        let result = claude.analyze(session: session)
        XCTAssertEqual(result.lifecycle, .running)
    }

    func testBundledCodexDoesNotTreatMarketingRateLimitsTipAsError() {
        let strategies = TaskStrategyFileLoader.loadConfiguredStrategies()
        guard let codex = strategies.first(where: { $0.strategyID == "codex" }) else {
            XCTFail("missing bundled codex strategy")
            return
        }

        let session = CapturedTerminalSession(
            nativeSessionId: "codex-tip",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "codex",
            tty: "ttys003",
            tailOutput: """
              Tip: New Try the Codex App with 2x rate limits until April 2nd.
            gpt-5.4 medium · 100% left · ~/git/buling-island
            """
        )

        let result = codex.analyze(session: session)
        XCTAssertNotEqual(result.lifecycle, .error)
        // 仅有 Tip + 空闲态脚注 `gpt-x.x medium · n% left ·` 时不应判为 running（该脚注在无 • working 时一直存在）。
        XCTAssertEqual(result.lifecycle, .idle)
    }

    func testBundledCodexStillDetectsRateLimitExceeded() {
        let strategies = TaskStrategyFileLoader.loadConfiguredStrategies()
        guard let codex = strategies.first(where: { $0.strategyID == "codex" }) else {
            XCTFail("missing bundled codex strategy")
            return
        }

        let session = CapturedTerminalSession(
            nativeSessionId: "codex-429",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "codex",
            tty: "ttys004",
            tailOutput: "Error: Rate limit exceeded. Try again in 30s."
        )

        let result = codex.analyze(session: session)
        XCTAssertEqual(result.lifecycle, .error)
    }
}
