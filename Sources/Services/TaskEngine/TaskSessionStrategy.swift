import Foundation

protocol TaskSessionStrategy {
    var strategyID: String { get }
    var displayName: String { get }
    var priority: Int { get }

    func supports(session: CapturedTerminalSession) -> Bool
    func analyze(session: CapturedTerminalSession) -> TaskSessionRawAnalysis
}

/// 任务会话策略注册表；**引擎与药丸解析共用** `loadConfiguredStrategies()` / `replaceExtras` 的解析结果，保证与终端宿主无关的分析一致。
enum TaskSessionStrategyRegistry {
    private static let lock = NSLock()
    private static var extraStrategies: [any TaskSessionStrategy] = []

    static func register(_ strategy: any TaskSessionStrategy) {
        lock.lock()
        defer { lock.unlock() }
        extraStrategies.removeAll { $0.strategyID == strategy.strategyID }
        extraStrategies.append(strategy)
    }

    static func replaceExtras(_ strategies: [any TaskSessionStrategy]) {
        lock.lock()
        defer { lock.unlock() }
        var seen = Set<String>()
        extraStrategies = strategies.filter { seen.insert($0.strategyID).inserted }
    }

    static func resolvedStrategies() -> [any TaskSessionStrategy] {
        lock.lock()
        let extras = extraStrategies
        lock.unlock()
        let base = extras.isEmpty ? TaskStrategyFileLoader.loadConfiguredStrategies() : extras
        return sortedUniqueStrategies(base)
    }

    private static func sortedUniqueStrategies(_ list: [any TaskSessionStrategy]) -> [any TaskSessionStrategy] {
        var seen = Set<String>()
        let unique = list.filter { seen.insert($0.strategyID).inserted }
        return unique.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.strategyID < rhs.strategyID
        }
    }

    /// 与 `TaskSessionEngine` 一致：先按 `supports` 命中专用策略，否则落到 `generic`（须存在于内置/用户策略 JSON）。
    static func strategy(for session: CapturedTerminalSession) -> any TaskSessionStrategy {
        let strategies = resolvedStrategies()
        if let match = strategies.first(where: { $0.supports(session: session) }) {
            return match
        }
        if let generic = strategies.first(where: { $0.strategyID == "generic" }) {
            return generic
        }
        if let fallback = TaskStrategyFileLoader.configurableStrategy(strategyID: "generic") {
            return fallback
        }
        fatalError("TaskStrategies: missing generic.json")
    }
}
