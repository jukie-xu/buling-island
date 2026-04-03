import XCTest
@testable import BulingIsland

final class TaskSessionTextToolkitTests: XCTestCase {

    func testStandardizedTerminalTextRemovesTerminalEncodingDifferences() {
        let raw = "\u{001B}[32m❯\u{001B}[0m hi\u{00A0}\r\n\u{001B}]0;Codex\u{0007}  ⎿ reply\u{200B}\r"

        let normalized = TaskSessionTextToolkit.standardizedTerminalText(from: raw)

        XCTAssertEqual(normalized, "❯ hi \n  ⎿ reply\n")
    }

    func testInteractionOptionsFromNumberedMenu() {
        let tail = """
        Would you like to run the following command?
        git status
        1. Yes, proceed (y)
        2. Yes, and don't ask again for this command (p)
        3. No, and tell Codex what to do differently (esc)
        Press enter to confirm or esc to cancel
        """

        let options = TaskSessionTextToolkit.interactionOptions(from: tail)

        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options[0].input, "y")
        XCTAssertEqual(options[1].input, "p")
        XCTAssertEqual(options[2].kind, .choice)
        XCTAssertEqual(options[2].actions, [.key(.escape)])
    }

    func testInteractionPromptFromNumberedMenuIncludesQuestion() {
        let tail = """
        Would you like to run the following command?
        npm test
        1. Yes, proceed (y)
        2. No, and tell Codex what to do differently (esc)
        """

        let prompt = TaskSessionTextToolkit.extractInteractionPrompt(from: tail)

        XCTAssertEqual(prompt?.title, "Would you like to run the following command?")
        XCTAssertEqual(prompt?.body, "npm test")
        XCTAssertEqual(prompt?.selectionMode, .single)
        XCTAssertEqual(prompt?.options.map(\.input), ["y", ""])
    }

    func testCodexApprovalPromptKeepsQuestionReasonAndCommandSeparated() {
        let tail = """
        Would you like to run the following command?

        Reason: Do you want to allow staging and creating the requested git commit in this repository?

        $ git add -A && git commit -m "feat: 完善任务面板文本渲染与终端捕获一致性"

        1. Yes, proceed (y)
        2. Yes, and don't ask again for commands that start with `git add -A` (p)
        3. No, and tell Codex what to do differently (esc)

        Press enter to confirm or esc to cancel
        """

        let prompt = TaskSessionTextToolkit.extractInteractionPrompt(from: tail)

        XCTAssertEqual(prompt?.title, "Would you like to run the following command?")
        XCTAssertEqual(
            prompt?.body,
            """
            Reason: Do you want to allow staging and creating the requested git commit in this repository?
            $ git add -A && git commit -m "feat: 完善任务面板文本渲染与终端捕获一致性"
            """
        )
        XCTAssertEqual(prompt?.instruction, "Press enter to confirm or esc to cancel")
        XCTAssertEqual(prompt?.options.map(\.shortcutHint), ["y", "p", "esc"])
        XCTAssertEqual(prompt?.options[0].actions, [.text("y"), .key(.enter)])
        XCTAssertEqual(prompt?.options[1].actions, [.text("p"), .key(.enter)])
        XCTAssertEqual(prompt?.options[2].actions, [.key(.escape)])
    }

    func testInteractionOptionsFromYNFallback() {
        let tail = "approval required (y/n)"

        let options = TaskSessionTextToolkit.interactionOptions(from: tail)

        XCTAssertEqual(options.map(\.input), ["y", "n"])
        XCTAssertTrue(options.allSatisfy(\.submit))
    }

    func testInteractionPromptSupportsMultiSelection() {
        let tail = """
        Choose one or more actions
        1. Stage file (s)
        2. Run tests (t)
        Space to select, Enter to confirm
        """

        let prompt = TaskSessionTextToolkit.extractInteractionPrompt(from: tail)

        XCTAssertEqual(prompt?.selectionMode, .multiple)
        XCTAssertEqual(prompt?.options.map(\.submit), [false, false])
        XCTAssertEqual(prompt?.confirmButton?.label, "确认")
    }

    func testInteractionPromptSupportsClaudeInterruptedFreeform() {
        let tail = """
        ❯ hi
          ⎿ Interrupted · What should Claude do instead?
        """

        let prompt = TaskSessionTextToolkit.extractInteractionPrompt(from: tail)

        XCTAssertEqual(prompt?.title, "Interrupted · What should Claude do instead?")
        XCTAssertEqual(prompt?.selectionMode, .freeform)
        XCTAssertEqual(prompt?.confirmButton?.kind, .activate)
    }

    func testInteractionPromptParsesModeSelectionMenu() {
        let tail = """
        How would you like Codex to handle requests to execute shell commands?
        1) Read Only (current)
        2) Auto
        3) Full Access
        Use arrow keys to choose
        """

        let prompt = TaskSessionTextToolkit.extractInteractionPrompt(from: tail)

        XCTAssertEqual(prompt?.title, "How would you like Codex to handle requests to execute shell commands?")
        XCTAssertEqual(prompt?.options.map(\.label), ["Read Only", "Auto", "Full Access"])
        XCTAssertEqual(prompt?.presentationStyle, .navigationList)
        XCTAssertEqual(prompt?.options[0].isInitiallySelected, true)
        XCTAssertEqual(prompt?.options[1].actions, [.key(.arrowDown), .key(.enter)])
        XCTAssertEqual(prompt?.instruction, "Use arrow keys to choose")
    }

    func testExtractLatestReplyPrefersClaudeInterruptedLine() {
        let tail = """
        ❯ hi
          ⎿  Interrupted · What should Claude do instead?

          🤖 Opus 4.6 | 📁 buling-island | 🌿 main ● | ⚡️ 0% · 0 tokens
        """

        let reply = TaskSessionTextToolkit.extractLatestReply(from: tail)

        XCTAssertEqual(reply, "Interrupted · What should Claude do instead?")
    }

    func testExtractLatestReplySkipsCaretCScrollbackArtifact() {
        let tail = """
        › hiss

          gpt-5.4 medium · 100% left · ~/
        ^C
        """

        let reply = TaskSessionTextToolkit.extractLatestReply(from: tail)

        XCTAssertNil(reply)
    }

    func testCompactTailTextSkipsShellPromptLines() {
        let tail = """
        jukie@Jukies-MacBook-Pro-16-inc buling-island % clear
        jukie@Jukies-MacBook-Pro-16-inc buling-island % codex
        >_ OpenAI Codex (v0.118.0)
        Find and fix a bug
        """

        let compact = TaskSessionTextToolkit.compactTailText(tail)

        XCTAssertFalse(compact.contains("buling-island % clear"))
        XCTAssertFalse(compact.contains("buling-island % codex"))
        XCTAssertTrue(compact.contains("Find and fix a bug"))
    }

    func testPromptReplyAndCompactAreStableAcrossTerminalVariants() {
        let canonical = """
        ❯ hi
          ⎿ Interrupted · What should Claude do instead?
        """
        let decorated = "\u{001B}[33m❯\u{001B}[0m hi\u{00A0}\r\n  \u{001B}[2m⎿\u{001B}[0m Interrupted · What should Claude do instead?\r\n"

        XCTAssertEqual(
            TaskSessionTextToolkit.extractLatestUserPrompt(from: canonical),
            TaskSessionTextToolkit.extractLatestUserPrompt(from: decorated)
        )
        XCTAssertEqual(
            TaskSessionTextToolkit.extractLatestReply(from: canonical),
            TaskSessionTextToolkit.extractLatestReply(from: decorated)
        )
        XCTAssertEqual(
            TaskSessionTextToolkit.compactTailText(canonical),
            TaskSessionTextToolkit.compactTailText(decorated)
        )
        XCTAssertEqual(
            TaskSessionTextToolkit.extractInteractionPrompt(from: canonical)?.title,
            TaskSessionTextToolkit.extractInteractionPrompt(from: decorated)?.title
        )
    }

    func testCodexBannerLineIsNotTreatedAsUserInput() {
        let tail = """
        >_ OpenAI Codex (v0.118.0)
        model: gpt-5.4 medium    /model to change
        directory: ~/git/buling-island
        """

        let compact = TaskSessionTextToolkit.compactTailText(tail)

        XCTAssertTrue(compact.contains("OpenAI Codex"))
        XCTAssertFalse(TaskSessionTextToolkit.isUserInputCommandLine(">_ OpenAI Codex (v0.118.0)"))
    }

    func testTerminalBoxedCodexBannerIsUnwrappedIntoAnalysisText() {
        let tail = """
        ╭──────────────────────────────────────────────╮
        │ >_ OpenAI Codex (v0.118.0)                   │
        │                                              │
        │ model:     gpt-5.4 medium   /model to change │
        │ directory: ~/git/buling-island               │
        ╰──────────────────────────────────────────────╯
        """

        let compact = TaskSessionTextToolkit.compactTailText(tail)

        XCTAssertTrue(compact.contains("OpenAI Codex"))
        XCTAssertTrue(compact.contains("/model to change"))
        XCTAssertTrue(compact.contains("~/git/buling-island"))
    }

    func testExtractLatestUserPromptSkipsCodexPlaceholderPromptBelowRunningLine() {
        let tail = """
        › 提交并推送

        • Working (21s • esc to interrupt)

        › Summarize recent commits

          gpt-5.4 medium · 100% left · ~/git/buling-island
        """

        let prompt = TaskSessionTextToolkit.extractLatestUserPrompt(from: tail)

        XCTAssertEqual(prompt, "提交并推送")
    }
}
