import XCTest
@testable import BulingIsland

final class TaskSessionPanelTextTests: XCTestCase {

    @MainActor
    func testWaitingInputSnapshotKeepsPromptForManualConfirmationRendering() throws {
        let codex = try XCTUnwrap(TaskStrategyFileLoader.configurableStrategy(strategyID: "codex"))
        let session = CapturedTerminalSession(
            nativeSessionId: "approve",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "codex session",
            tty: "/dev/ttys001",
            tailOutput: """
            Would you like to run the following command?

            Reason: Do you want to allow staging and creating the requested git commit in this repository?

            $ git add -A && git commit -m "feat: 完善任务面板文本渲染与终端捕获一致性"

            1. Yes, proceed (y)
            2. Yes, and don't ask again for commands that start with `git add -A` (p)
            3. No, and tell Codex what to do differently (esc)

            Press enter to confirm or esc to cancel
            """
        )

        let engine = TaskSessionEngine(strategies: [codex])
        engine.refresh(sessions: [session], now: Date(timeIntervalSince1970: 1000))

        let snapshot = try XCTUnwrap(engine.snapshotsBySessionID[session.id])
        XCTAssertEqual(snapshot.lifecycle, .waitingInput)
        XCTAssertEqual(snapshot.interactionPrompt?.title, "Would you like to run the following command?")
        XCTAssertEqual(
            snapshot.interactionPrompt?.body,
            """
            Reason: Do you want to allow staging and creating the requested git commit in this repository?
            $ git add -A && git commit -m "feat: 完善任务面板文本渲染与终端捕获一致性"
            """
        )
        XCTAssertEqual(snapshot.interactionPrompt?.options.count, 3)
        XCTAssertEqual(snapshot.interactionPrompt?.options.first?.label, "Yes, proceed")
        XCTAssertTrue(snapshot.interactionPrompt?.options[1].label.hasPrefix("Yes, and don't ask again") == true)
        XCTAssertEqual(snapshot.interactionPrompt?.options.last?.label, "No, and tell Codex what to do differently")
        XCTAssertEqual(snapshot.interactionPrompt?.instruction, "Press enter to confirm or esc to cancel")
    }

    func testNoPromptShowsSinglePlaceholder() {
        let tail = """
        Tip: New Try the Codex App
        gpt-5.4 medium · 100% left · ~/
        """

        let text = TaskSessionTextToolkit.composeTaskPanelSecondaryText(
            tail: tail,
            lifecycle: .idle,
            promptNow: TaskSessionTextToolkit.extractLatestUserPrompt(from: tail),
            replyNow: TaskSessionTextToolkit.extractLatestReply(from: tail),
            memory: TaskSessionPanelMemory()
        )

        XCTAssertEqual(text, TaskSessionTextToolkit.taskPanelNoTaskPlaceholder)
    }

    func testRunningShowsPromptAndReplyOrPlaceholder() {
        var memory = TaskSessionPanelMemory()
        let tail1 = """
        › Summarize recent commits
        • working (reading files)
        """
        let p1 = TaskSessionTextToolkit.extractLatestUserPrompt(from: tail1)
        let r1 = TaskSessionTextToolkit.extractLatestReply(from: tail1)
        TaskSessionTextToolkit.updateTaskPanelMemory(
            promptNow: p1,
            replyNow: r1,
            stabilizedLifecycle: .running,
            memory: &memory
        )

        let out1 = TaskSessionTextToolkit.composeTaskPanelSecondaryText(
            tail: tail1,
            lifecycle: .running,
            promptNow: p1,
            replyNow: r1,
            memory: memory
        )
        XCTAssertTrue(out1.contains("Summarize recent commits"))
        XCTAssertTrue(out1.contains("working"))

        let tail2 = """
        › Only prompt line
        """
        let p2 = TaskSessionTextToolkit.extractLatestUserPrompt(from: tail2)
        memory = TaskSessionPanelMemory()
        TaskSessionTextToolkit.updateTaskPanelMemory(
            promptNow: p2,
            replyNow: nil,
            stabilizedLifecycle: .running,
            memory: &memory
        )
        let out2 = TaskSessionTextToolkit.composeTaskPanelSecondaryText(
            tail: tail2,
            lifecycle: .running,
            promptNow: p2,
            replyNow: nil,
            memory: memory
        )
        XCTAssertTrue(out2.hasSuffix(TaskSessionTextToolkit.taskPanelRunningPlaceholder))
    }

    func testSuccessSecondLineIsCompleted() {
        let memory = TaskSessionPanelMemory(cachedUserPrompt: "Fix bug", cachedAgentReply: "done earlier")
        let tail = "› Fix bug\npatch applied"
        let text = TaskSessionTextToolkit.composeTaskPanelSecondaryText(
            tail: tail,
            lifecycle: .success,
            promptNow: nil,
            replyNow: nil,
            memory: memory
        )
        XCTAssertTrue(text.contains("Fix bug"))
        XCTAssertTrue(text.contains(TaskSessionTextToolkit.taskPanelCompletedLine))
    }

    func testNewPromptClearsCachedReply() {
        var memory = TaskSessionPanelMemory(cachedUserPrompt: "First", cachedAgentReply: "Old reply")
        TaskSessionTextToolkit.updateTaskPanelMemory(
            promptNow: "Second question",
            replyNow: nil,
            stabilizedLifecycle: .running,
            memory: &memory
        )
        XCTAssertEqual(memory.cachedUserPrompt, "Second question")
        XCTAssertNil(memory.cachedAgentReply)
    }

    func testRunningCodexUsesSubmittedPromptInsteadOfPlaceholderPrompt() {
        var memory = TaskSessionPanelMemory(cachedUserPrompt: "提交并推送", cachedAgentReply: nil)
        let tail = """
        >_ OpenAI Codex (v0.118.0)
        model: gpt-5.4 medium    /model to change
        directory: ~/git/buling-island

        › 提交并推送

        • Working (21s • esc to interrupt)

        › Summarize recent commits

        gpt-5.4 medium · 100% left · ~/git/buling-island
        """

        let prompt = TaskSessionTextToolkit.extractLatestUserPrompt(from: tail)
        let reply = TaskSessionTextToolkit.extractLatestReply(from: tail)
        TaskSessionTextToolkit.updateTaskPanelMemory(
            promptNow: prompt,
            replyNow: reply,
            stabilizedLifecycle: .running,
            memory: &memory
        )

        let text = TaskSessionTextToolkit.composeTaskPanelSecondaryText(
            tail: tail,
            lifecycle: .running,
            promptNow: prompt,
            replyNow: reply,
            memory: memory
        )

        XCTAssertEqual(text, "提交并推送\n• Working (21s • esc to interrupt)")
    }
}
