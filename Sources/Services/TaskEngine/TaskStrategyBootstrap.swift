import Foundation

@MainActor
enum TaskStrategyBootstrap {
    /// Project-level strategy registration entrypoint.
    /// Call once during app launch before `IslandView` is created.
    static func installProjectStrategies() {
        let configured = TaskStrategyFileLoader.loadConfiguredStrategies()
        if !configured.isEmpty {
            TaskSessionStrategyRegistry.replaceExtras(configured)
        }
    }
}
