import Foundation

enum TaskLifecycleState: String, Codable, Hashable {
    case inactiveTool
    case idle
    case running
    case waitingInput
    case success
    case error
}

enum TaskRenderTone: String, Codable, Hashable {
    case neutral
    case running
    case warning
    case success
    case error
    case inactive
}

struct TaskSessionRawAnalysis: Hashable {
    let lifecycle: TaskLifecycleState
    let renderTone: TaskRenderTone
    let secondaryText: String

    static func inactive(_ text: String) -> TaskSessionRawAnalysis {
        TaskSessionRawAnalysis(
            lifecycle: .inactiveTool,
            renderTone: .inactive,
            secondaryText: text
        )
    }
}

struct TaskSessionSnapshot: Hashable {
    let sessionID: String
    let strategyID: String
    let strategyDisplayName: String
    let lifecycle: TaskLifecycleState
    let renderTone: TaskRenderTone
    let isRunning: Bool
    let secondaryText: String
    let refreshedAt: Date
}
