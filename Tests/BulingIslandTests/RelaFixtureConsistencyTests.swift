import XCTest
@testable import BulingIsland

@MainActor
final class RelaFixtureConsistencyTests: XCTestCase {

    private struct EvaluatedFixture {
        let name: String
        let session: CapturedTerminalSession
        let strategyID: String
        let prompt: String?
        let reply: String?
        let analysis: TaskSessionRawAnalysis
        let snapshot: TaskSessionSnapshot
        let signal: TerminalSessionSignal
    }

    private let expectedFixtureNames: Set<String> = [
        "claude-error.txt",
        "claude-undo-Interrupted.txt",
        "claude-undo.txt",
        "claude-working.txt",
        "codex-done.txt",
        "codex-jiaohu.txt",
        "codex-working.txt",
        "codex^working2.txt",
    ]

    func testRelaFixtureInventoryIsFullyCovered() throws {
        XCTAssertEqual(Set(availableFixtureNames()), expectedFixtureNames)
    }

    func testClaudeErrorFixtureParsesAsError() throws {
        let evaluated = try evaluateFixture(named: "claude-error.txt", title: "claude")

        XCTAssertEqual(evaluated.strategyID, "claude")
        XCTAssertEqual(evaluated.analysis.lifecycle, .error)
        XCTAssertEqual(evaluated.snapshot.lifecycle, .error)
        XCTAssertEqual(evaluated.snapshot.renderTone, .error)
        XCTAssertEqual(evaluated.signal.tone, "error")
        XCTAssertEqual(evaluated.prompt, "hi")
        XCTAssertEqual(evaluated.reply, #"401 {"error":{"message":"[trace_id: 2a8803db-81b1-4008-8c6e-407670e6cfb6] Validate Certification"#)
        XCTAssertTrue(evaluated.snapshot.secondaryText.contains("hi"))
        XCTAssertFalse(evaluated.snapshot.secondaryText.isEmpty)
    }

    func testClaudeInterruptedFixtureParsesAsWaitingInput() throws {
        let evaluated = try evaluateFixture(named: "claude-undo-Interrupted.txt", title: "claude")

        XCTAssertEqual(evaluated.strategyID, "claude")
        XCTAssertEqual(evaluated.analysis.lifecycle, .waitingInput)
        XCTAssertEqual(evaluated.snapshot.lifecycle, .waitingInput)
        XCTAssertEqual(evaluated.snapshot.renderTone, .warning)
        XCTAssertEqual(evaluated.signal.tone, "warn")
        XCTAssertEqual(evaluated.prompt, "hi")
        XCTAssertEqual(evaluated.reply, "Interrupted · What should Claude do instead?")
        XCTAssertEqual(evaluated.analysis.interactionPrompt?.title, "Interrupted · What should Claude do instead?")
        XCTAssertEqual(evaluated.snapshot.interactionPrompt?.selectionMode, .freeform)
        XCTAssertEqual(evaluated.snapshot.interactionPrompt?.confirmButton?.kind, .activate)
    }

    func testClaudeUndoFixtureParsesAsIdleWithPromptOnly() throws {
        let evaluated = try evaluateFixture(named: "claude-undo.txt", title: "claude")

        XCTAssertEqual(evaluated.strategyID, "claude")
        XCTAssertEqual(evaluated.analysis.lifecycle, .idle)
        XCTAssertEqual(evaluated.snapshot.lifecycle, .idle)
        XCTAssertEqual(evaluated.signal.tone, "info")
        XCTAssertEqual(evaluated.prompt, #"Try "how does PanelManager.swift work?""#)
        XCTAssertNil(evaluated.reply)
        XCTAssertEqual(evaluated.snapshot.secondaryText, #"Try "how does PanelManager.swift work?""#)
    }

    func testClaudeWorkingFixtureStillParsesDeterministically() throws {
        let evaluated = try evaluateFixture(named: "claude-working.txt", title: "claude")

        XCTAssertEqual(evaluated.strategyID, "claude")
        XCTAssertEqual(evaluated.analysis.lifecycle, .error)
        XCTAssertEqual(evaluated.snapshot.lifecycle, .error)
        XCTAssertEqual(evaluated.signal.tone, "error")
        XCTAssertEqual(evaluated.prompt, "hi")
        XCTAssertNotNil(evaluated.reply)
        XCTAssertFalse(evaluated.snapshot.secondaryText.isEmpty)
    }

    func testCodexDoneFixtureParsesAsSuccess() throws {
        let evaluated = try evaluateFixture(named: "codex-done.txt", title: "OpenAI Codex")

        XCTAssertEqual(evaluated.strategyID, "codex")
        XCTAssertEqual(evaluated.analysis.lifecycle, .success)
        XCTAssertEqual(evaluated.snapshot.lifecycle, .success)
        XCTAssertEqual(evaluated.snapshot.renderTone, .success)
        XCTAssertEqual(evaluated.signal.tone, "success")
        XCTAssertEqual(evaluated.prompt, "Summarize recent commits")
        XCTAssertTrue(evaluated.snapshot.secondaryText.contains(TaskSessionTextToolkit.taskPanelCompletedLine))
    }

    func testCodexInteractionFixtureParsesAsWaitingInput() throws {
        let evaluated = try evaluateFixture(named: "codex-jiaohu.txt", title: "OpenAI Codex")

        XCTAssertEqual(evaluated.strategyID, "codex")
        XCTAssertEqual(evaluated.analysis.lifecycle, .waitingInput)
        XCTAssertEqual(evaluated.snapshot.lifecycle, .waitingInput)
        XCTAssertEqual(evaluated.snapshot.renderTone, .warning)
        XCTAssertEqual(evaluated.signal.tone, "warn")
        XCTAssertEqual(
            evaluated.snapshot.interactionPrompt?.title,
            "Would you like to run the following command?"
        )
        XCTAssertEqual(evaluated.snapshot.interactionPrompt?.selectionMode, .single)
        XCTAssertEqual(evaluated.snapshot.interactionPrompt?.options.count, 3)
        XCTAssertEqual(evaluated.snapshot.interactionPrompt?.options.first?.input, "y")
    }

    func testCodexWorkingFixtureParsesAsRunning() throws {
        let evaluated = try evaluateFixture(named: "codex-working.txt", title: "OpenAI Codex")

        XCTAssertEqual(evaluated.strategyID, "codex")
        XCTAssertEqual(evaluated.analysis.lifecycle, .running)
        XCTAssertEqual(evaluated.snapshot.lifecycle, .running)
        XCTAssertEqual(evaluated.snapshot.renderTone, .running)
        XCTAssertEqual(evaluated.signal.tone, "busy")
        XCTAssertEqual(evaluated.prompt, "Summarize recent commits")
        XCTAssertNil(evaluated.snapshot.interactionPrompt)
        XCTAssertTrue(evaluated.snapshot.secondaryText.contains("Summarize recent commits"))
    }

    func testCodexWorkingVariantFixtureParsesAsRunning() throws {
        let evaluated = try evaluateFixture(named: "codex^working2.txt", title: "OpenAI Codex")

        XCTAssertEqual(evaluated.strategyID, "codex")
        XCTAssertEqual(evaluated.analysis.lifecycle, .running)
        XCTAssertEqual(evaluated.snapshot.lifecycle, .running)
        XCTAssertEqual(evaluated.snapshot.renderTone, .running)
        XCTAssertEqual(evaluated.signal.tone, "busy")
        XCTAssertEqual(evaluated.prompt, "Summarize recent commits")
        XCTAssertNil(evaluated.snapshot.interactionPrompt)
        XCTAssertTrue(evaluated.snapshot.secondaryText.contains("Summarize recent commits"))
    }

    func testEquivalentFixturesProduceConsistentRenderContracts() throws {
        let claudeError = try evaluateFixture(named: "claude-error.txt", title: "claude")
        let claudeWorking = try evaluateFixture(named: "claude-working.txt", title: "claude")

        XCTAssertEqual(claudeError.strategyID, claudeWorking.strategyID)
        XCTAssertEqual(claudeError.snapshot.lifecycle, claudeWorking.snapshot.lifecycle)
        XCTAssertEqual(claudeError.snapshot.renderTone, claudeWorking.snapshot.renderTone)
        XCTAssertEqual(claudeError.prompt, claudeWorking.prompt)
        XCTAssertEqual(claudeError.snapshot.interactionPrompt, claudeWorking.snapshot.interactionPrompt)
        XCTAssertEqual(claudeError.signal.tone, claudeWorking.signal.tone)

        let codexWorking = try evaluateFixture(named: "codex-working.txt", title: "OpenAI Codex")
        let codexWorkingVariant = try evaluateFixture(named: "codex^working2.txt", title: "OpenAI Codex")

        XCTAssertEqual(codexWorking.strategyID, codexWorkingVariant.strategyID)
        XCTAssertEqual(codexWorking.snapshot.lifecycle, codexWorkingVariant.snapshot.lifecycle)
        XCTAssertEqual(codexWorking.snapshot.renderTone, codexWorkingVariant.snapshot.renderTone)
        XCTAssertEqual(codexWorking.prompt, codexWorkingVariant.prompt)
        XCTAssertEqual(codexWorking.snapshot.interactionPrompt, codexWorkingVariant.snapshot.interactionPrompt)
        XCTAssertEqual(codexWorking.signal.tone, codexWorkingVariant.signal.tone)
    }

    func testTerminalAndITermCodexLikeSamplesResolveToSameStrategyContract() throws {
        let terminalTail = """
        >_ OpenAI Codex (v0.118.0)
        model: gpt-5.4 medium    /model to change
        directory: ~/git/buling-island

        Tip: New Try the Codex App with 2x rate limits until April 2nd. Run 'codex app'

        › hiss

        gpt-5.4 medium · 100% left · ~/git/buling-island
        """
        let iTermTail = """
        >_ OpenAI Codex (v0.118.0)
        model: gpt-5.4 medium    /model to change
        directory: ~/git/buling-island

        Tip: Run codex app to open Codex Desktop (it installs on macOS if needed).

        › 哈哈哈11

        gpt-5.4 medium · 100% left · ~/git/buling-island
        """

        let terminal = try evaluateInlineSession(title: "buling-island", tail: terminalTail, nativeID: "terminal")
        let iTerm = try evaluateInlineSession(title: "buling-island (codex)", tail: iTermTail, nativeID: "iterm")

        XCTAssertEqual(terminal.strategyID, "codex")
        XCTAssertEqual(iTerm.strategyID, "codex")
        XCTAssertEqual(terminal.snapshot.lifecycle, iTerm.snapshot.lifecycle)
        XCTAssertEqual(terminal.snapshot.renderTone, iTerm.snapshot.renderTone)
        XCTAssertEqual(terminal.signal.tone, iTerm.signal.tone)
        XCTAssertEqual(terminal.prompt, "hiss")
        XCTAssertEqual(iTerm.prompt, "哈哈哈11")
        XCTAssertEqual(terminal.snapshot.secondaryText, "hiss")
        XCTAssertEqual(iTerm.snapshot.secondaryText, "哈哈哈11")
    }

    func testTerminalAndITermSamePromptResolveToIdenticalSecondaryText() throws {
        let prompt = "hiss"
        let terminalTail = """
        ╭──────────────────────────────────────────────╮
        │ >_ OpenAI Codex (v0.118.0)                   │
        │                                              │
        │ model:     gpt-5.4 medium   /model to change │
        │ directory: ~/git/buling-island               │
        ╰──────────────────────────────────────────────╯

          Tip: New Try the Codex App with 2x rate limits until April 2nd. Run 'codex app'

        › \(prompt)

          gpt-5.4 medium · 100% left · ~/git/buling-island
        """
        let iTermTail = """
        >_ OpenAI Codex (v0.118.0)
        model: gpt-5.4 medium    /model to change
        directory: ~/git/buling-island

        Tip: Run codex app to open Codex Desktop (it installs on macOS if needed).

        › \(prompt)

        gpt-5.4 medium · 100% left · ~/git/buling-island
        """

        let terminal = try evaluateInlineSession(title: "buling-island", tail: terminalTail, nativeID: "terminal-same")
        let iTerm = try evaluateInlineSession(title: "buling-island (codex)", tail: iTermTail, nativeID: "iterm-same")

        XCTAssertEqual(terminal.strategyID, "codex")
        XCTAssertEqual(iTerm.strategyID, "codex")
        XCTAssertEqual(terminal.snapshot.lifecycle, iTerm.snapshot.lifecycle)
        XCTAssertEqual(terminal.snapshot.renderTone, iTerm.snapshot.renderTone)
        XCTAssertEqual(terminal.snapshot.secondaryText, prompt)
        XCTAssertEqual(iTerm.snapshot.secondaryText, prompt)
    }

    func testCompletedCodexTaskCardBodyIsConsistentAcrossSupportedTerminals() throws {
        let runningTail = """
        › 提交并推送

        • Working (21s • esc to interrupt)
        """
        let doneTail = """
        >_ OpenAI Codex (v0.118.0)
        model: gpt-5.4 medium    /model to change
        directory: ~/git/buling-island

        › 提交并推送

        • 我已经确认当前在 main 分支，有一批已修改和新增文件待提交。

        ✔ You approved codex to run git push origin main this time

        • 已提交，提交号是 7690fa3，提交信息是 feat: 完善任务面板文本渲染与终端捕获一致性。

          推送没有成功完成。当前仓库状态还是 main...origin/main [ahead 1]

        › Summarize recent commits

        gpt-5.4 medium · 97% left · ~/git/buling-island
        """

        for kind in [TerminalKind.iTerm2, .iTermLegacy, .appleTerminal] {
            let snapshot = try snapshotAfterRunningThenIdle(
                terminalKind: kind,
                title: kind == .appleTerminal ? "buling-island" : "buling-island (codex)",
                runningTail: runningTail,
                idleTail: doneTail,
                nativeID: "done-\(kind.rawValue)"
            )

            XCTAssertEqual(snapshot.lifecycle, .idle, "lifecycle mismatch for \(kind.rawValue)")
            XCTAssertEqual(
                snapshot.secondaryText,
                "提交并推送\n\(TaskSessionTextToolkit.taskPanelCompletedLine)",
                "secondaryText mismatch for \(kind.rawValue)"
            )
            let lines = TaskSessionTextToolkit.taskPanelDisplayLines(from: snapshot.secondaryText)
            XCTAssertEqual(lines.primary, "提交并推送", "prompt line mismatch for \(kind.rawValue)")
            XCTAssertEqual(lines.secondary, TaskSessionTextToolkit.taskPanelCompletedLine, "status line mismatch for \(kind.rawValue)")
        }
    }

    private func evaluateFixture(named name: String, title: String) throws -> EvaluatedFixture {
        let tail = try loadFixture(named: name)
        return try evaluateInlineSession(title: title, tail: tail, nativeID: name)
    }

    private func evaluateInlineSession(title: String, tail: String, nativeID: String) throws -> EvaluatedFixture {
        try evaluateInlineSession(
            title: title,
            tail: tail,
            nativeID: nativeID,
            terminalKind: .iTerm2
        )
    }

    private func evaluateInlineSession(
        title: String,
        tail: String,
        nativeID: String,
        terminalKind: TerminalKind
    ) throws -> EvaluatedFixture {
        let session = CapturedTerminalSession(
            nativeSessionId: nativeID,
            backendIdentifier: "fixture.backend",
            terminalKind: terminalKind,
            title: title,
            tty: "ttys-fixture",
            tailOutput: tail
        )

        let strategy = TaskSessionStrategyRegistry.strategy(for: session)
        let analysis = strategy.analyze(session: session)

        let engine = TaskSessionEngine(strategies: TaskSessionStrategyRegistry.resolvedStrategies())
        let now = Date(timeIntervalSince1970: 1_764_662_400)
        engine.refresh(sessions: [session], now: now)

        let snapshot = try XCTUnwrap(engine.snapshotsBySessionID[session.id])
        let signal = TaskStrategySessionSignalParser().parse(session: session)

        return EvaluatedFixture(
            name: nativeID,
            session: session,
            strategyID: strategy.strategyID,
            prompt: TaskSessionTextToolkit.extractLatestUserPrompt(from: session.standardizedTailOutput),
            reply: TaskSessionTextToolkit.extractLatestReply(from: session.standardizedTailOutput),
            analysis: analysis,
            snapshot: snapshot,
            signal: signal
        )
    }

    private func snapshotAfterRunningThenIdle(
        terminalKind: TerminalKind,
        title: String,
        runningTail: String,
        idleTail: String,
        nativeID: String
    ) throws -> TaskSessionSnapshot {
        let engine = TaskSessionEngine(strategies: TaskSessionStrategyRegistry.resolvedStrategies())
        let sessionRunning = CapturedTerminalSession(
            nativeSessionId: nativeID,
            backendIdentifier: "fixture.backend",
            terminalKind: terminalKind,
            title: title,
            tty: "ttys-fixture",
            tailOutput: runningTail
        )
        engine.refresh(
            sessions: [sessionRunning],
            now: Date(timeIntervalSince1970: 1_764_662_400)
        )

        let sessionIdle = CapturedTerminalSession(
            nativeSessionId: nativeID,
            backendIdentifier: "fixture.backend",
            terminalKind: terminalKind,
            title: title,
            tty: "ttys-fixture",
            tailOutput: idleTail
        )
        engine.refresh(
            sessions: [sessionIdle],
            now: Date(timeIntervalSince1970: 1_764_662_410)
        )
        return try XCTUnwrap(engine.snapshotsBySessionID[sessionIdle.id])
    }

    private func availableFixtureNames() -> [String] {
        let root = repoRootURL()
        let relaURL = root.appendingPathComponent("rela", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: relaURL.path)) ?? []
        return names.filter { $0.hasSuffix(".txt") }.sorted()
    }

    private func loadFixture(named name: String) throws -> String {
        let root = repoRootURL()
        let url = root.appendingPathComponent("rela", isDirectory: true).appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
