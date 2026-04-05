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
    enum Kind: String, Codable, Hashable {
        case choice
        case confirm
        case activate
    }

    enum SpecialKey: String, Codable, Hashable {
        case enter
        case escape
        case tab
        case space
        case arrowUp
        case arrowDown
        case arrowLeft
        case arrowRight
    }

    struct Action: Codable, Hashable {
        enum Kind: String, Codable, Hashable {
            case text
            case specialKey
            case activate
        }

        let kind: Kind
        let text: String?
        let specialKey: SpecialKey?

        static func text(_ text: String) -> Action {
            Action(kind: .text, text: text, specialKey: nil)
        }

        static func key(_ key: SpecialKey) -> Action {
            Action(kind: .specialKey, text: nil, specialKey: key)
        }

        static let activate = Action(kind: .activate, text: nil, specialKey: nil)
    }

    let id: String
    let label: String
    let input: String
    let submit: Bool
    let kind: Kind
    let shortcutHint: String?
    let actions: [Action]
    let isInitiallySelected: Bool

    init(
        id: String,
        label: String,
        input: String,
        submit: Bool,
        kind: Kind = .choice,
        shortcutHint: String? = nil,
        actions: [Action] = [],
        isInitiallySelected: Bool = false
    ) {
        self.id = id
        self.label = label
        self.input = input
        self.submit = submit
        self.kind = kind
        self.shortcutHint = shortcutHint
        self.actions = actions
        self.isInitiallySelected = isInitiallySelected
    }
}

struct TaskInteractionPrompt: Codable, Hashable {
    enum SelectionMode: String, Codable, Hashable {
        case single
        case multiple
        case freeform
    }

    enum PresentationStyle: String, Codable, Hashable {
        case grid
        case navigationList
        case freeform
    }

    let title: String
    let body: String?
    let instruction: String?
    let selectionMode: SelectionMode
    let presentationStyle: PresentationStyle
    let options: [TaskInteractionOption]
    let confirmButton: TaskInteractionOption?
    let controlButtons: [TaskInteractionOption]
}

struct TaskSessionRawAnalysis: Hashable {
    let lifecycle: TaskLifecycleState
    let renderTone: TaskRenderTone
    let secondaryText: String
    let interactionOptions: [TaskInteractionOption]
    let interactionPrompt: TaskInteractionPrompt?

    init(
        lifecycle: TaskLifecycleState,
        renderTone: TaskRenderTone,
        secondaryText: String,
        interactionOptions: [TaskInteractionOption] = [],
        interactionPrompt: TaskInteractionPrompt? = nil
    ) {
        self.lifecycle = lifecycle
        self.renderTone = renderTone
        self.secondaryText = secondaryText
        self.interactionOptions = interactionOptions
        self.interactionPrompt = interactionPrompt
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
    let detailText: String?
    let interactionOptions: [TaskInteractionOption]
    let interactionPrompt: TaskInteractionPrompt?
    let refreshedAt: Date
}

/// 任务面板双行摘要所需的跨轮询缓存（按会话）。
struct TaskSessionPanelMemory: Equatable {
    var cachedUserPrompt: String?
    var cachedAgentReply: String?
    var hasActiveTask: Bool = false
}

struct TaskPanelPresentation: Equatable {
    let taskLine: String
    let statusLine: String
    let detailLine: String?
    let lifecycleLabel: String
}
