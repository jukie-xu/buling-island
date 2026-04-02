import Foundation

struct TaskSessionStateMachine {
    private struct Memory {
        var lifecycle: TaskLifecycleState
        var updatedAt: Date
    }

    private var memoryBySessionID: [String: Memory] = [:]

    mutating func purge(keepingSessionIDs: Set<String>) {
        memoryBySessionID = memoryBySessionID.filter { keepingSessionIDs.contains($0.key) }
    }

    mutating func stabilize(
        sessionID: String,
        proposed: TaskLifecycleState,
        now: Date
    ) -> TaskLifecycleState {
        defer {
            memoryBySessionID[sessionID] = Memory(lifecycle: proposed, updatedAt: now)
        }
        guard let prev = memoryBySessionID[sessionID] else {
            return proposed
        }

        if prev.lifecycle == .error,
           proposed != .running,
           now.timeIntervalSince(prev.updatedAt) <= 8 {
            return .error
        }
        if prev.lifecycle == .success,
           proposed != .running,
           proposed != .error,
           now.timeIntervalSince(prev.updatedAt) <= 5 {
            return .success
        }
        if prev.lifecycle == .running,
           proposed == .idle,
           now.timeIntervalSince(prev.updatedAt) <= 2 {
            return .running
        }
        return proposed
    }
}
