import Foundation
import Combine

@MainActor
final class TaskSessionEngine: ObservableObject {
    @Published private(set) var snapshotsBySessionID: [String: TaskSessionSnapshot] = [:]

    private var strategies: [any TaskSessionStrategy]
    private var stateMachine = TaskSessionStateMachine()

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

    func refresh(
        sessions: [CapturedTerminalSession],
        activeSessionIDs: Set<String>,
        now: Date = Date()
    ) {
        let liveIDs = Set(sessions.map(\.id))
        stateMachine.purge(keepingSessionIDs: liveIDs)

        var next: [String: TaskSessionSnapshot] = [:]
        next.reserveCapacity(sessions.count)

        for session in sessions {
            let strategy = resolveStrategy(for: session)
            var analysis = strategy.analyze(session: session)

            var lifecycle = analysis.lifecycle
            if activeSessionIDs.contains(session.id), lifecycle != .error, lifecycle != .success {
                lifecycle = (lifecycle == .waitingInput) ? .waitingInput : .running
                if lifecycle == .running {
                    analysis = TaskSessionRawAnalysis(
                        lifecycle: .running,
                        renderTone: .running,
                        secondaryText: analysis.secondaryText,
                        interactionOptions: analysis.interactionOptions
                    )
                }
            }

            let stabilized = stateMachine.stabilize(
                sessionID: session.id,
                proposed: lifecycle,
                now: now
            )
            let tone = renderTone(for: stabilized, fallback: analysis.renderTone)
            let running = (stabilized == .running || stabilized == .waitingInput)

            next[session.id] = TaskSessionSnapshot(
                sessionID: session.id,
                strategyID: strategy.strategyID,
                strategyDisplayName: strategy.displayName,
                lifecycle: stabilized,
                renderTone: tone,
                isRunning: running,
                secondaryText: analysis.secondaryText,
                interactionOptions: analysis.interactionOptions,
                refreshedAt: now
            )
        }

        snapshotsBySessionID = next
    }

    private func resolveStrategy(for session: CapturedTerminalSession) -> any TaskSessionStrategy {
        strategies.first(where: { $0.supports(session: session) }) ?? GenericTaskSessionStrategy()
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
