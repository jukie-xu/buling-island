import XCTest
@testable import BulingIsland

@MainActor
final class TaskSessionTranscriptCacheTests: XCTestCase {

    func testObserveMergesIncrementalTailAndCachesPrompt() throws {
        let cache = TaskSessionTranscriptCache(storageURL: tempFileURL())

        let first = cache.observe(
            sessionID: "session-1",
            normalizedTail: """
            › 提交并推送

            • Working (21s • esc to interrupt)
            """,
            extractedPrompt: "提交并推送",
            now: Date(timeIntervalSince1970: 1)
        )
        let second = cache.observe(
            sessionID: "session-1",
            normalizedTail: """
            • Working (21s • esc to interrupt)

            • 已提交，提交号是 7690fa3。
            """,
            extractedPrompt: nil,
            now: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(first.latestSubmittedPrompt, "提交并推送")
        XCTAssertEqual(second.latestSubmittedPrompt, "提交并推送")
        XCTAssertTrue(second.mergedTail.contains("› 提交并推送"))
        XCTAssertTrue(second.mergedTail.contains("• 已提交，提交号是 7690fa3。"))
        XCTAssertEqual(second.incrementalTail, "• 已提交，提交号是 7690fa3。")
    }

    func testObserveSkipsPlaceholderPromptAndKeepsLastSubmittedPrompt() throws {
        let cache = TaskSessionTranscriptCache(storageURL: tempFileURL())

        _ = cache.observe(
            sessionID: "session-2",
            normalizedTail: """
            › 提交并推送

            • Working (21s • esc to interrupt)
            """,
            extractedPrompt: "提交并推送",
            now: Date(timeIntervalSince1970: 1)
        )
        let snapshot = cache.observe(
            sessionID: "session-2",
            normalizedTail: """
            › 提交并推送

            • 已提交，提交号是 7690fa3。

            › Summarize recent commits

            gpt-5.4 medium · 97% left · ~/git/buling-island
            """,
            extractedPrompt: "提交并推送",
            now: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(snapshot.latestSubmittedPrompt, "提交并推送")
    }

    func testFlushAndReloadPreserveCachedPrompt() throws {
        let url = tempFileURL()
        let cache = TaskSessionTranscriptCache(storageURL: url)
        _ = cache.observe(
            sessionID: "session-3",
            normalizedTail: """
            › 修复任务面板

            • Working (reading files)
            """,
            extractedPrompt: "修复任务面板",
            now: Date(timeIntervalSince1970: 1)
        )
        cache.flushIfNeeded()

        let reloaded = TaskSessionTranscriptCache(storageURL: url)
        let snapshot = reloaded.observe(
            sessionID: "session-3",
            normalizedTail: "• 已完成",
            extractedPrompt: nil,
            now: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(snapshot.latestSubmittedPrompt, "修复任务面板")
    }

    func testStableSessionCondensesAfterTwoUnchangedPolls() throws {
        let cache = TaskSessionTranscriptCache(storageURL: tempFileURL())
        let longTail = (1...80).map { "line-\($0)" }.joined(separator: "\n")

        _ = cache.observe(
            sessionID: "session-4",
            normalizedTail: longTail,
            extractedPrompt: nil,
            now: Date(timeIntervalSince1970: 1)
        )
        _ = cache.observe(
            sessionID: "session-4",
            normalizedTail: longTail,
            extractedPrompt: nil,
            now: Date(timeIntervalSince1970: 2)
        )
        let snapshot = cache.observe(
            sessionID: "session-4",
            normalizedTail: longTail,
            extractedPrompt: nil,
            now: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(snapshot.phase, .condensed)
        XCTAssertFalse(snapshot.mergedTail.contains("line-1"))
        XCTAssertTrue(snapshot.mergedTail.contains("line-80"))
    }

    func testMissingSessionIsEvictedAfterTwoReconcilePasses() throws {
        let cache = TaskSessionTranscriptCache(storageURL: tempFileURL())

        _ = cache.observe(
            sessionID: "session-5",
            normalizedTail: "› hi",
            extractedPrompt: "hi",
            now: Date(timeIntervalSince1970: 1)
        )
        cache.reconcileLiveSessions([], now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(cache.snapshot(for: "session-5")?.phase, .missing)

        cache.reconcileLiveSessions([], now: Date(timeIntervalSince1970: 3))
        XCTAssertNil(cache.snapshot(for: "session-5"))
    }

    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
