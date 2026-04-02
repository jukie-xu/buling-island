import Foundation

protocol TaskSessionStrategy {
    var strategyID: String { get }
    var displayName: String { get }
    var priority: Int { get }

    func supports(session: CapturedTerminalSession) -> Bool
    func analyze(session: CapturedTerminalSession) -> TaskSessionRawAnalysis
}

@MainActor
enum TaskSessionStrategyRegistry {
    private static var extraStrategies: [any TaskSessionStrategy] = []

    static func register(_ strategy: any TaskSessionStrategy) {
        extraStrategies.removeAll { $0.strategyID == strategy.strategyID }
        extraStrategies.append(strategy)
    }

    static func replaceExtras(_ strategies: [any TaskSessionStrategy]) {
        var seen = Set<String>()
        extraStrategies = strategies.filter { seen.insert($0.strategyID).inserted }
    }

    static func resolvedStrategies() -> [any TaskSessionStrategy] {
        var seen = Set<String>()
        let builtins: [any TaskSessionStrategy] = [
            ClaudeTaskSessionStrategy(),
            CodexTaskSessionStrategy(),
            GenericTaskSessionStrategy(),
        ]
        let merged = extraStrategies + builtins
        return merged.filter { seen.insert($0.strategyID).inserted }
    }
}

struct ClaudeTaskSessionStrategy: TaskSessionStrategy {
    let strategyID = "claude"
    let displayName = "Claude"
    let priority = 300

    func supports(session: CapturedTerminalSession) -> Bool {
        let titleLower = session.title.lowercased()
        let tailLower = session.tailOutput.lowercased()
        let markers = [
            "claude", "claude code", "what should claude do",
            "billowing", "sonnet", "ask claude", "esc to interrupt",
        ]
        if titleLower.contains("claude") { return true }
        return markers.contains(where: { tailLower.contains($0) })
    }

    func analyze(session: CapturedTerminalSession) -> TaskSessionRawAnalysis {
        let compact = TaskSessionTextToolkit.compactTailText(session.tailOutput)
        let lower = compact.lowercased()
        if compact.isEmpty {
            return TaskSessionRawAnalysis(
                lifecycle: .idle,
                renderTone: .neutral,
                secondaryText: "当前未运行任务"
            )
        }
        if TaskSessionTextToolkit.containsErrorMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .error,
                renderTone: .error,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndError(from: session.tailOutput)
            )
        }
        if TaskSessionTextToolkit.containsWaitingMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .waitingInput,
                renderTone: .warning,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        if TaskSessionTextToolkit.containsRunningMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .running,
                renderTone: .running,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        if TaskSessionTextToolkit.containsSuccessMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .success,
                renderTone: .success,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        return TaskSessionRawAnalysis(
            lifecycle: .idle,
            renderTone: .neutral,
            secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
        )
    }
}

struct CodexTaskSessionStrategy: TaskSessionStrategy {
    let strategyID = "codex"
    let displayName = "Codex"
    let priority = 260

    func supports(session: CapturedTerminalSession) -> Bool {
        let titleLower = session.title.lowercased()
        let tailLower = session.tailOutput.lowercased()
        let markers = [
            "codex",
            "openai codex",
            "gpt-5-codex",
            "responses api",
            "agent",
            "assistant",
        ]
        if titleLower.contains("codex") { return true }
        return markers.contains(where: { tailLower.contains($0) })
    }

    func analyze(session: CapturedTerminalSession) -> TaskSessionRawAnalysis {
        let compact = TaskSessionTextToolkit.compactTailText(session.tailOutput)
        let lower = compact.lowercased()
        if compact.isEmpty {
            return TaskSessionRawAnalysis(
                lifecycle: .idle,
                renderTone: .neutral,
                secondaryText: "当前未运行任务"
            )
        }
        if TaskSessionTextToolkit.containsErrorMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .error,
                renderTone: .error,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndError(from: session.tailOutput)
            )
        }
        if TaskSessionTextToolkit.containsWaitingMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .waitingInput,
                renderTone: .warning,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        if TaskSessionTextToolkit.containsRunningMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .running,
                renderTone: .running,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        if TaskSessionTextToolkit.containsSuccessMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .success,
                renderTone: .success,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        return TaskSessionRawAnalysis(
            lifecycle: .idle,
            renderTone: .neutral,
            secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
        )
    }
}

struct GenericTaskSessionStrategy: TaskSessionStrategy {
    let strategyID = "generic"
    let displayName = "Generic TUI"
    let priority = 10

    func supports(session: CapturedTerminalSession) -> Bool {
        _ = session
        return true
    }

    func analyze(session: CapturedTerminalSession) -> TaskSessionRawAnalysis {
        let compact = TaskSessionTextToolkit.compactTailText(session.tailOutput)
        let lower = compact.lowercased()
        if compact.isEmpty {
            return TaskSessionRawAnalysis.inactive("当前会话未匹配 Claude/Codex 策略")
        }
        if TaskSessionTextToolkit.containsErrorMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .error,
                renderTone: .error,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndError(from: session.tailOutput)
            )
        }
        if TaskSessionTextToolkit.containsWaitingMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .waitingInput,
                renderTone: .warning,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        if TaskSessionTextToolkit.containsRunningMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .running,
                renderTone: .running,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        if TaskSessionTextToolkit.containsSuccessMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .success,
                renderTone: .success,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        return TaskSessionRawAnalysis(
            lifecycle: .idle,
            renderTone: .neutral,
            secondaryText: TaskSessionTextToolkit.truncate(compact, max: 88)
        )
    }
}
