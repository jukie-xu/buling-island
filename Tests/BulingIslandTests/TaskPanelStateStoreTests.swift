import XCTest
@testable import BulingIsland

@MainActor
final class TaskPanelStateStoreTests: XCTestCase {

    func testRebuildCreatesPreferredGroupsAndPinnedSection() {
        let store = TaskPanelStateStore(defaults: testDefaults())
        store.loadIfNeeded()
        store.togglePinned(sessionID: "backend|term-1")

        let iTermSession = CapturedTerminalSession(
            nativeSessionId: "term-1",
            backendIdentifier: "backend",
            terminalKind: .iTerm2,
            title: "codex-a",
            tty: "ttys001",
            tailOutput: ""
        )
        let terminalSession = CapturedTerminalSession(
            nativeSessionId: "term-2",
            backendIdentifier: "backend",
            terminalKind: .appleTerminal,
            title: "codex-b",
            tty: "ttys002",
            tailOutput: ""
        )

        let snapshots = [
            iTermSession.id: TaskSessionSnapshot(
                sessionID: iTermSession.id,
                strategyID: "codex",
                strategyDisplayName: "Codex",
                lifecycle: .running,
                renderTone: .running,
                isRunning: true,
                secondaryText: "任务A\n处理中…",
                detailText: nil,
                interactionOptions: [],
                interactionPrompt: nil,
                refreshedAt: Date(timeIntervalSince1970: 1)
            ),
            terminalSession.id: TaskSessionSnapshot(
                sessionID: terminalSession.id,
                strategyID: "codex",
                strategyDisplayName: "Codex",
                lifecycle: .idle,
                renderTone: .neutral,
                isRunning: false,
                secondaryText: "任务B",
                detailText: nil,
                interactionOptions: [],
                interactionPrompt: nil,
                refreshedAt: Date(timeIntervalSince1970: 1)
            ),
        ]

        store.rebuild(sessions: [iTermSession, terminalSession], snapshotsBySessionID: snapshots)

        XCTAssertEqual(store.groups.map(\.name), ["置顶", "Terminal"])
        XCTAssertEqual(store.groups.first?.tasks.first?.session.id, iTermSession.id)
        XCTAssertEqual(store.groups.last?.tasks.first?.session.id, terminalSession.id)
    }

    func testRebuildDropsDeadPinnedAndBucketOrderEntries() {
        let store = TaskPanelStateStore(defaults: testDefaults())
        store.loadIfNeeded()
        store.togglePinned(sessionID: "backend|dead")
        store.applyGroupBucketReorder(groupName: "Terminal", bucket: .notRunning, ids: ["backend|dead"])

        let liveSession = CapturedTerminalSession(
            nativeSessionId: "live",
            backendIdentifier: "backend",
            terminalKind: .appleTerminal,
            title: "live",
            tty: "ttys003",
            tailOutput: ""
        )
        let snapshots = [
            liveSession.id: TaskSessionSnapshot(
                sessionID: liveSession.id,
                strategyID: "codex",
                strategyDisplayName: "Codex",
                lifecycle: .idle,
                renderTone: .neutral,
                isRunning: false,
                secondaryText: "任务C",
                detailText: nil,
                interactionOptions: [],
                interactionPrompt: nil,
                refreshedAt: Date(timeIntervalSince1970: 1)
            )
        ]

        store.rebuild(sessions: [liveSession], snapshotsBySessionID: snapshots)

        XCTAssertFalse(store.isPinned(sessionID: "backend|dead"))
        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups.first?.name, "Terminal")
    }

    private func testDefaults() -> UserDefaults {
        let suiteName = "TaskPanelStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
