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

struct TaskInteractionOption: Codable, Hashable {
    let id: String
    let label: String
    let input: String
    let submit: Bool
}

struct TaskSessionRawAnalysis: Hashable {
    let lifecycle: TaskLifecycleState
    let renderTone: TaskRenderTone
    let secondaryText: String
    let interactionOptions: [TaskInteractionOption]

    init(
        lifecycle: TaskLifecycleState,
        renderTone: TaskRenderTone,
        secondaryText: String,
        interactionOptions: [TaskInteractionOption] = []
    ) {
        self.lifecycle = lifecycle
        self.renderTone = renderTone
        self.secondaryText = secondaryText
        self.interactionOptions = interactionOptions
    }

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
    let interactionOptions: [TaskInteractionOption]
    let refreshedAt: Date
}
