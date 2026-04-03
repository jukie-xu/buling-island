import Foundation
import Combine

@MainActor
final class TaskSessionEngine: ObservableObject {
    @Published private(set) var snapshotsBySessionID: [String: TaskSessionSnapshot] = [:]

    private var strategies: [any TaskSessionStrategy]
    private var stateMachine = TaskSessionStateMachine()
    private var taskPanelMemoryBySessionID: [String: TaskSessionPanelMemory] = [:]

    init(strategies: [any TaskSessionStrategy]) {
        self.strategies = Self.sortedStrategies(strategies)
    }

    convenience init() {
        self.init(strategies: TaskSessionStrategyRegistry.resolvedStrategies())
    }

    func replaceStrategies(_ newStrategies: [any TaskSessionStrategy]) {
        strategies = Self.sortedStrategies(newStrategies)
    }

    func installStrategy(_ strategy: any TaskSessionStrategy) {
        let existing = strategies.filter { $0.strategyID != strategy.strategyID }
        strategies = Self.sortedStrategies(existing + [strategy])
    }

    /// 任务生命周期完全由各 `TaskSessionStrategy`（及 JSON 策略）依据终端尾部判定，不再根据「近期有输出」等启发式抬升为 `running`，避免未提交输入也被标为执行中。
    func refresh(
        sessions: [CapturedTerminalSession],
        now: Date = Date()
    ) {
        let liveIDs = Set(sessions.map(\.id))
        stateMachine.purge(keepingSessionIDs: liveIDs)
        taskPanelMemoryBySessionID = taskPanelMemoryBySessionID.filter { liveIDs.contains($0.key) }

        var next: [String: TaskSessionSnapshot] = [:]
        next.reserveCapacity(sessions.count)

        for session in sessions {
            let strategy = resolveStrategy(for: session)
            let analysis = strategy.analyze(session: session)
            let normalizedTail = session.standardizedTailOutput
            let lifecycle = analysis.lifecycle

            let stabilized = stateMachine.stabilize(
                sessionID: session.id,
                proposed: lifecycle,
                now: now
            )
            let tone = renderTone(for: stabilized, fallback: analysis.renderTone)
            let running = (stabilized == .running)

            var panelMem = taskPanelMemoryBySessionID[session.id] ?? TaskSessionPanelMemory()
            let promptNow = TaskSessionTextToolkit.extractLatestUserPrompt(from: normalizedTail)
            let replyNow = TaskSessionTextToolkit.extractLatestReply(from: normalizedTail)
            TaskSessionTextToolkit.updateTaskPanelMemory(
                promptNow: promptNow,
                replyNow: replyNow,
                stabilizedLifecycle: stabilized,
                memory: &panelMem
            )
            taskPanelMemoryBySessionID[session.id] = panelMem

            let panelSecondaryText: String = {
                if stabilized == .inactiveTool {
                    return analysis.secondaryText
                }
                return TaskSessionTextToolkit.composeTaskPanelSecondaryText(
                    tail: normalizedTail,
                    lifecycle: stabilized,
                    promptNow: promptNow,
                    replyNow: replyNow,
                    memory: panelMem
                )
            }()
            let detailText: String? = stabilized == .waitingInput
                ? TaskSessionTextToolkit.composeWaitingInputDisplayText(
                    interactionPrompt: analysis.interactionPrompt,
                    interactionOptions: analysis.interactionOptions,
                    fallback: panelSecondaryText
                )
                : nil

            next[session.id] = TaskSessionSnapshot(
                sessionID: session.id,
                strategyID: strategy.strategyID,
                strategyDisplayName: strategy.displayName,
                lifecycle: stabilized,
                renderTone: tone,
                isRunning: running,
                secondaryText: panelSecondaryText,
                detailText: detailText,
                interactionOptions: analysis.interactionOptions,
                interactionPrompt: analysis.interactionPrompt,
                refreshedAt: now
            )
        }

        snapshotsBySessionID = next
    }

    private func resolveStrategy(for session: CapturedTerminalSession) -> any TaskSessionStrategy {
        if let match = strategies.first(where: { $0.supports(session: session) }) {
            return match
        }
        return strategies.first(where: { $0.strategyID == "generic" }) ?? strategies.last
            ?? TaskSessionStrategyRegistry.strategy(for: session)
    }

    private func renderTone(for state: TaskLifecycleState, fallback: TaskRenderTone) -> TaskRenderTone {
        switch state {
        case .inactiveTool: return .inactive
        case .idle: return .neutral
        case .running: return .running
        case .waitingInput: return .warning
        case .success: return .success
        case .error: return .error
        }
    }

    private static func sortedStrategies(_ list: [any TaskSessionStrategy]) -> [any TaskSessionStrategy] {
        list.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.strategyID < rhs.strategyID
            }
            return lhs.priority > rhs.priority
        }
    }
}
