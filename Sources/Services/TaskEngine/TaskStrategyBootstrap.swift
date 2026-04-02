import Foundation

@MainActor
enum TaskStrategyBootstrap {
    /// Project-level strategy registration entrypoint.
    /// Call once during app launch before `IslandView` is created.
    static func installProjectStrategies() {
        // Example extension point:
        // - Keep built-in Claude/Codex/Generic strategies.
        // - Add project-specific aliases/heuristics here.
        TaskSessionStrategyRegistry.register(ProjectCodexAliasStrategy())
    }
}

/// Example project strategy:
/// Accepts extra Codex-related markers and reuses the Codex analyzer.
struct ProjectCodexAliasStrategy: TaskSessionStrategy {
    let strategyID = "project.codex.alias"
    let displayName = "Codex"
    let priority = 275

    func supports(session: CapturedTerminalSession) -> Bool {
        let title = session.title.lowercased()
        let tail = session.tailOutput.lowercased()
        let markers = [
            "codex",
            "openai codex",
            "codex cli",
            "openclaw",
            "gpt-5.4-codex",
            "gpt-5-codex",
        ]
        if title.contains("codex") || title.contains("openclaw") {
            return true
        }
        return markers.contains(where: { tail.contains($0) })
    }

    func analyze(session: CapturedTerminalSession) -> TaskSessionRawAnalysis {
        CodexTaskSessionStrategy().analyze(session: session)
    }
}
