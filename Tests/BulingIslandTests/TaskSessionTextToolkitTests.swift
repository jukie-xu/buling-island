import XCTest
@testable import BulingIsland

final class TaskSessionTextToolkitTests: XCTestCase {

    func testInteractionOptionsFromNumberedMenu() {
        let tail = """
        Would you like to run the following command?
        1. Yes, proceed (y)
        2. Yes, and don't ask again for this command (p)
        3. No, and tell Codex what to do differently (esc)
        Press enter to confirm or esc to cancel
        """

        let options = TaskSessionTextToolkit.interactionOptions(from: tail)

        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options[0].input, "y")
        XCTAssertEqual(options[1].input, "p")
        XCTAssertEqual(options[2].input, "n")
    }

    func testInteractionOptionsFromYNFallback() {
        let tail = "approval required (y/n)"

        let options = TaskSessionTextToolkit.interactionOptions(from: tail)

        XCTAssertEqual(options.map(\.input), ["y", "n"])
        XCTAssertTrue(options.allSatisfy(\.submit))
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
}
