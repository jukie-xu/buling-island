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
        if containsClaudeErrorMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .error,
                renderTone: .error,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndError(from: session.tailOutput)
            )
        }
        if containsClaudeWaitingMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .waitingInput,
                renderTone: .warning,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput),
                interactionOptions: TaskSessionTextToolkit.interactionOptions(from: session.tailOutput)
            )
        }
        if containsClaudeRunningMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .running,
                renderTone: .running,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        if containsClaudeSuccessMarkers(lower) {
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

    private func containsClaudeErrorMarkers(_ textLowercased: String) -> Bool {
        [
            "error", "failed", "exception", "auth_error", "unauthorized", "401",
            "timeout", "timed out", "报错", "失败", "错误", "超时",
            "anthropicerror", "invalid api key", "credit balance",
        ].contains(where: { textLowercased.contains($0) })
    }

    private func containsClaudeWaitingMarkers(_ textLowercased: String) -> Bool {
        [
            "allow", "approve", "confirm", "[y/n]", "(y/n)",
            "please confirm", "continue?", "是否允许", "请确认", "请选择",
        ].contains(where: { textLowercased.contains($0) })
    }

    private func containsClaudeRunningMarkers(_ textLowercased: String) -> Bool {
        [
            "esc to interrupt", "thinking", "analyzing", "processing", "executing",
            "claude is", "处理中", "执行中", "思考中",
        ].contains(where: { textLowercased.contains($0) })
    }

    private func containsClaudeSuccessMarkers(_ textLowercased: String) -> Bool {
        [
            "done", "completed", "finished", "success", "all set",
            "已完成", "成功", "完成",
        ].contains(where: { textLowercased.contains($0) })
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
            "exec_command",
            "apply_patch",
            "update_plan",
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
        if containsCodexErrorMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .error,
                renderTone: .error,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndError(from: session.tailOutput)
            )
        }
        if containsCodexWaitingMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .waitingInput,
                renderTone: .warning,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput),
                interactionOptions: TaskSessionTextToolkit.interactionOptions(from: session.tailOutput)
            )
        }
        if containsCodexRunningMarkers(lower) {
            return TaskSessionRawAnalysis(
                lifecycle: .running,
                renderTone: .running,
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput)
            )
        }
        if containsCodexSuccessMarkers(lower) {
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

    private func containsCodexErrorMarkers(_ textLowercased: String) -> Bool {
        [
            "error", "failed", "exception", "traceback", "permission denied",
            "sandbox denied", "network access is restricted", "rate limit", "429",
            "报错", "失败", "错误",
        ].contains(where: { textLowercased.contains($0) })
    }

    private func containsCodexWaitingMarkers(_ textLowercased: String) -> Bool {
        [
            "approval required", "awaiting approval", "allow this action",
            "sandbox_permissions", "require_escalated", "do you want to allow",
            "[y/n]", "(y/n)", "请确认", "是否允许",
        ].contains(where: { textLowercased.contains($0) })
    }

    private func containsCodexRunningMarkers(_ textLowercased: String) -> Bool {
        [
            "exec_command", "apply_patch", "update_plan", "wait_agent",
            "tool call", "patching", "analyzing repository", "running tests",
            "执行命令", "应用补丁",
        ].contains(where: { textLowercased.contains($0) })
    }

    private func containsCodexSuccessMarkers(_ textLowercased: String) -> Bool {
        [
            "patch applied", "tests passed", "implemented", "done", "completed",
            "finished", "成功", "已完成", "完成",
        ].contains(where: { textLowercased.contains($0) })
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
                secondaryText: TaskSessionTextToolkit.twoLinesPromptAndReply(from: session.tailOutput),
                interactionOptions: TaskSessionTextToolkit.interactionOptions(from: session.tailOutput)
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
