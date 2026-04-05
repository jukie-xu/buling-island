import Foundation

struct TaskBoardRow: Hashable {
    let session: CapturedTerminalSession
    let snapshot: TaskSessionSnapshot
}

struct TaskBoardGroup: Hashable {
    let id: String
    let name: String
    let isPinned: Bool
    let tasks: [TaskBoardRow]
}

enum TaskSortBucket: String, Hashable {
    case abnormal
    case running
    case completed
    case notRunning
    case pinned
}

@MainActor
final class TaskPanelStateStore: ObservableObject {
    @Published private(set) var groups: [TaskBoardGroup] = []

    private(set) var pinnedSessionIDs: Set<String> = []
    private(set) var pinnedOrder: [String] = []
    private(set) var orderByGroupBucket: [String: [String]] = [:]

    private let defaults: UserDefaults
    private var sortStateLoaded = false

    private static let pinnedSessionIDsDefaultsKey = "taskPanel.pinned.sessionIDs.v1"
    private static let pinnedOrderDefaultsKey = "taskPanel.pinned.order.v1"
    private static let groupBucketOrderDefaultsKey = "taskPanel.groupBucket.order.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadIfNeeded() {
        guard !sortStateLoaded else { return }
        sortStateLoaded = true
        if let pinned = defaults.array(forKey: Self.pinnedSessionIDsDefaultsKey) as? [String] {
            pinnedSessionIDs = Set(pinned)
        }
        if let order = defaults.array(forKey: Self.pinnedOrderDefaultsKey) as? [String] {
            pinnedOrder = order
        }
        if let map = defaults.dictionary(forKey: Self.groupBucketOrderDefaultsKey) as? [String: [String]] {
            orderByGroupBucket = map
        }
    }

    func rebuild(
        sessions: [CapturedTerminalSession],
        snapshotsBySessionID: [String: TaskSessionSnapshot]
    ) {
        let liveIDs = Set(sessions.map(\.id))
        reconcileSortState(liveIDs: liveIDs)

        let rows: [TaskBoardRow] = sessions.compactMap { session in
            guard let snapshot = snapshotsBySessionID[session.id] else { return nil }
            return TaskBoardRow(session: session, snapshot: snapshot)
        }

        let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.session.id, $0) })
        let pinnedRows = pinnedOrder.compactMap { rowsByID[$0] }
        let pinnedIDs = Set(pinnedRows.map(\.session.id))
        let nonPinnedRows = rows.filter { !pinnedIDs.contains($0.session.id) }
        let rowsByGroup = Dictionary(grouping: nonPinnedRows, by: taskGroupDisplayName(for:))

        var nextGroups: [TaskBoardGroup] = []
        if !pinnedRows.isEmpty {
            nextGroups.append(TaskBoardGroup(id: "task-group-pinned", name: "置顶", isPinned: true, tasks: pinnedRows))
        }

        let preferred = ["iTerm", "Terminal"]
        for name in preferred where rowsByGroup[name] != nil {
            nextGroups.append(
                TaskBoardGroup(
                    id: "task-group-\(name)",
                    name: name,
                    isPinned: false,
                    tasks: sortedRowsForGroup(rowsByGroup[name] ?? [], groupName: name)
                )
            )
        }
        for name in rowsByGroup.keys.filter({ !preferred.contains($0) }).sorted() {
            nextGroups.append(
                TaskBoardGroup(
                    id: "task-group-\(name)",
                    name: name,
                    isPinned: false,
                    tasks: sortedRowsForGroup(rowsByGroup[name] ?? [], groupName: name)
                )
            )
        }

        if groups != nextGroups {
            groups = nextGroups
        }
    }

    func togglePinned(sessionID: String) {
        if pinnedSessionIDs.contains(sessionID) {
            pinnedSessionIDs.remove(sessionID)
            pinnedOrder.removeAll { $0 == sessionID }
        } else {
            pinnedSessionIDs.insert(sessionID)
            if !pinnedOrder.contains(sessionID) {
                pinnedOrder.append(sessionID)
            }
        }
        persist()
    }

    func rowLookup(sessionID: String) -> (item: TaskBoardRow, group: TaskBoardGroup)? {
        for group in groups {
            if let item = group.tasks.first(where: { $0.session.id == sessionID }) {
                return (item, group)
            }
        }
        return nil
    }

    func visibleRowIDs(groupName: String, bucket: TaskSortBucket) -> [String] {
        groups
            .first(where: { $0.name == groupName })?
            .tasks
            .filter { row in
                let rowBucket = bucket == .pinned ? TaskSortBucket.pinned : taskSortBucket(for: row.snapshot)
                return rowBucket == bucket
            }
            .map(\.session.id) ?? []
    }

    func applyPinnedReorder(ids: [String]) {
        pinnedOrder = ids
        persist()
    }

    func applyGroupBucketReorder(groupName: String, bucket: TaskSortBucket, ids: [String]) {
        orderByGroupBucket[taskGroupBucketStorageKey(groupName: groupName, bucket: bucket)] = ids
        persist()
    }

    func isPinned(sessionID: String) -> Bool {
        pinnedSessionIDs.contains(sessionID)
    }

    func taskSortBucket(for snapshot: TaskSessionSnapshot) -> TaskSortBucket {
        Self.taskSortBucket(for: snapshot)
    }

    func taskGroupBucketStorageKey(groupName: String, bucket: TaskSortBucket) -> String {
        "\(groupName)|\(bucket.rawValue)"
    }

    private func taskGroupDisplayName(for row: TaskBoardRow) -> String {
        let app = row.session.captureGroupKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.isEmpty ? "iTerm" : app
    }

    private func sortedRowsForGroup(_ rows: [TaskBoardRow], groupName: String) -> [TaskBoardRow] {
        let byBucket = Dictionary(grouping: rows, by: { Self.taskSortBucket(for: $0.snapshot) })
        let statusOrder: [TaskSortBucket] = [.abnormal, .running, .completed, .notRunning]
        return statusOrder.flatMap { bucket in
            let base = (byBucket[bucket] ?? []).sorted {
                $0.session.title.localizedStandardCompare($1.session.title) == .orderedAscending
            }
            let key = taskGroupBucketStorageKey(groupName: groupName, bucket: bucket)
            return applyCustomOrder(base, orderedIDs: orderByGroupBucket[key] ?? [])
        }
    }

    private func applyCustomOrder(_ rows: [TaskBoardRow], orderedIDs: [String]) -> [TaskBoardRow] {
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.session.id, $0) })
        var result: [TaskBoardRow] = []
        var used = Set<String>()
        for id in orderedIDs {
            guard let row = byID[id] else { continue }
            result.append(row)
            used.insert(id)
        }
        for row in rows where !used.contains(row.session.id) {
            result.append(row)
        }
        return result
    }

    private func reconcileSortState(liveIDs: Set<String>) {
        guard sortStateLoaded else { return }
        pinnedSessionIDs = pinnedSessionIDs.intersection(liveIDs)
        pinnedOrder = pinnedOrder.filter { pinnedSessionIDs.contains($0) }

        var cleaned: [String: [String]] = [:]
        for (key, ids) in orderByGroupBucket {
            let kept = ids.filter { liveIDs.contains($0) && !pinnedSessionIDs.contains($0) }
            if !kept.isEmpty {
                cleaned[key] = kept
            }
        }
        orderByGroupBucket = cleaned
        persist()
    }

    private func persist() {
        guard sortStateLoaded else { return }
        defaults.set(Array(pinnedSessionIDs), forKey: Self.pinnedSessionIDsDefaultsKey)
        defaults.set(pinnedOrder, forKey: Self.pinnedOrderDefaultsKey)
        defaults.set(orderByGroupBucket, forKey: Self.groupBucketOrderDefaultsKey)
    }

    private static func taskSortBucket(for snapshot: TaskSessionSnapshot) -> TaskSortBucket {
        switch snapshot.lifecycle {
        case .error, .waitingInput: return .abnormal
        case .running: return .running
        case .success: return .completed
        case .idle, .inactiveTool: return .notRunning
        }
    }
}
