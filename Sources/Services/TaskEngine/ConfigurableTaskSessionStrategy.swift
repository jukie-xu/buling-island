import Foundation

struct ConfigurableTaskSessionStrategy: TaskSessionStrategy {
    let strategyID: String
    let displayName: String
    let priority: Int

    private let supportsRule: TaskStrategyMatchRule
    private let lifecycleRules: TaskStrategyLifecycleRules
    private let defaultLifecycle: TaskLifecycleState
    private let emptyOutput: TaskStrategyEmptyOutputRule
    private let extraction: TaskStrategyExtractionRules

    init(config: TaskStrategyFileConfig) {
        self.strategyID = config.strategyID
        self.displayName = config.displayName
        self.priority = config.priority
        self.supportsRule = config.supports
        self.lifecycleRules = config.lifecycleRules
        self.defaultLifecycle = config.defaultLifecycle
        self.emptyOutput = config.emptyOutput
        self.extraction = config.extraction
    }

    func supports(session: CapturedTerminalSession) -> Bool {
        supportsRule.matches(
            title: session.title,
            tail: TaskSessionTextToolkit.analysisCompactTailText(session.standardizedTailOutput, maxTailLines: 40)
        )
    }

    func analyze(session: CapturedTerminalSession) -> TaskSessionRawAnalysis {
        let normalizedTail = session.standardizedTailOutput
        let compact = TaskSessionTextToolkit.analysisCompactTailText(normalizedTail)
        let lower = compact.lowercased()

        if compact.isEmpty {
            return TaskSessionRawAnalysis(
                lifecycle: emptyOutput.lifecycle,
                renderTone: emptyOutput.renderTone,
                secondaryText: emptyOutput.secondaryText
            )
        }

        let lifecycle: TaskLifecycleState = {
            if lifecycleRules.error.matches(textLowercased: lower) { return .error }
            if lifecycleRules.waitingInput.matches(textLowercased: lower) { return .waitingInput }
            if lifecycleRules.running.matches(textLowercased: lower) { return .running }
            if lifecycleRules.success.matches(textLowercased: lower) { return .success }
            return defaultLifecycle
        }()

        let interactionPrompt = lifecycle == .waitingInput
            ? TaskSessionTextToolkit.extractInteractionPrompt(from: normalizedTail)
            : nil

        return TaskSessionRawAnalysis(
            lifecycle: lifecycle,
            renderTone: toneForLifecycle(lifecycle),
            secondaryText: extraction.extract(
                lifecycle: lifecycle,
                tail: normalizedTail,
                compact: compact
            ),
            interactionOptions: interactionPrompt?.options
                ?? (lifecycle == .waitingInput ? TaskSessionTextToolkit.interactionOptions(from: normalizedTail) : []),
            interactionPrompt: interactionPrompt
        )
    }

    private func toneForLifecycle(_ lifecycle: TaskLifecycleState) -> TaskRenderTone {
        switch lifecycle {
        case .inactiveTool: return .inactive
        case .idle: return .neutral
        case .running: return .running
        case .waitingInput: return .warning
        case .success: return .success
        case .error: return .error
        }
    }
}

struct TaskStrategyFileConfig: Codable {
    let strategyID: String
    let displayName: String
    let priority: Int
    let supports: TaskStrategyMatchRule
    let lifecycleRules: TaskStrategyLifecycleRules
    let defaultLifecycle: TaskLifecycleState
    let emptyOutput: TaskStrategyEmptyOutputRule
    let extraction: TaskStrategyExtractionRules
}

struct TaskStrategyMatchRule: Codable {
    let titleContains: [String]
    let titleRegex: [String]
    let tailContains: [String]
    let tailRegex: [String]

    init(
        titleContains: [String] = [],
        titleRegex: [String] = [],
        tailContains: [String] = [],
        tailRegex: [String] = []
    ) {
        self.titleContains = titleContains
        self.titleRegex = titleRegex
        self.tailContains = tailContains
        self.tailRegex = tailRegex
    }

    func matches(title: String, tail: String) -> Bool {
        let titleLower = title.lowercased()
        let tailLower = tail.lowercased()

        if titleContains.contains(where: { titleLower.contains($0.lowercased()) }) { return true }
        if tailContains.contains(where: { tailLower.contains($0.lowercased()) }) { return true }
        if matchesAnyRegex(titleRegex, in: title) { return true }
        if matchesAnyRegex(tailRegex, in: tail) { return true }
        return false
    }

    func matches(textLowercased: String) -> Bool {
        if tailContains.contains(where: { textLowercased.contains($0.lowercased()) }) { return true }
        if matchesAnyRegex(tailRegex, in: textLowercased) { return true }
        return false
    }

    private func matchesAnyRegex(_ patterns: [String], in text: String) -> Bool {
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(location: 0, length: text.utf16.count)
            if re.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }
}

struct TaskStrategyLifecycleRules: Codable {
    let error: TaskStrategyMatchRule
    let waitingInput: TaskStrategyMatchRule
    let running: TaskStrategyMatchRule
    let success: TaskStrategyMatchRule
}

struct TaskStrategyEmptyOutputRule: Codable {
    let lifecycle: TaskLifecycleState
    let renderTone: TaskRenderTone
    let secondaryText: String
}

struct TaskStrategyExtractionRules: Codable {
    let fallbackText: String
    let fallbackMaxLength: Int
    let byLifecycle: [String: TaskStrategyExtractionRule]

    func extract(lifecycle: TaskLifecycleState, tail: String, compact: String) -> String {
        let rule = byLifecycle[lifecycle.rawValue] ?? TaskStrategyExtractionRule(mode: .truncateCompact)
        return rule.extract(tail: tail, compact: compact, fallbackText: fallbackText, fallbackMaxLength: fallbackMaxLength)
    }
}

struct TaskStrategyExtractionRule: Codable {
    enum Mode: String, Codable {
        case promptAndReply
        case promptAndError
        case truncateCompact
        case compact
        case fixedText
    }

    let mode: Mode
    let maxLength: Int?
    let text: String?

    init(mode: Mode, maxLength: Int? = nil, text: String? = nil) {
        self.mode = mode
        self.maxLength = maxLength
        self.text = text
    }

    func extract(tail: String, compact: String, fallbackText: String, fallbackMaxLength: Int) -> String {
        switch mode {
        case .promptAndReply:
            return TaskSessionTextToolkit.twoLinesPromptAndReply(from: tail)
        case .promptAndError:
            return TaskSessionTextToolkit.twoLinesPromptAndError(from: tail)
        case .truncateCompact:
            let base = compact.isEmpty ? fallbackText : compact
            return TaskSessionTextToolkit.truncate(base, max: maxLength ?? fallbackMaxLength)
        case .compact:
            return compact.isEmpty ? fallbackText : compact
        case .fixedText:
            return text ?? fallbackText
        }
    }
}

enum TaskStrategyFileLoader {
    /// 合并各 JSON；同 `strategyID` 以后出现的文件覆盖先前（用户目录在 `allCandidateFiles` 中位于内置之后）。
    static func loadConfiguredStrategies() -> [any TaskSessionStrategy] {
        configurationsByStrategyID().values
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.strategyID < rhs.strategyID
            }
            .map { ConfigurableTaskSessionStrategy(config: $0) as any TaskSessionStrategy }
    }

    static func configurableStrategy(strategyID: String) -> ConfigurableTaskSessionStrategy? {
        configurationsByStrategyID()[strategyID].map { ConfigurableTaskSessionStrategy(config: $0) }
    }

    /// 包内 `Configs` 资源中的策略文件 URL（不受 `~/Library/.../TaskStrategies` 覆盖影响）；供测试断言内置 JSON 行为。
    static func urlForBundledStrategyJSON(strategyID: String) -> URL? {
        Bundle.module.url(forResource: strategyID, withExtension: "json")
    }

    static func invalidateBundledStrategyCaches() {
        mergeLock.lock()
        mergedConfigurationsCache = nil
        mergeLock.unlock()
    }

    private static let mergeLock = NSLock()
    private static var mergedConfigurationsCache: [String: TaskStrategyFileConfig]?

    private static func configurationsByStrategyID() -> [String: TaskStrategyFileConfig] {
        mergeLock.lock()
        defer { mergeLock.unlock() }
        if let mergedConfigurationsCache { return mergedConfigurationsCache }

        let urls = allCandidateFiles()
        var byId: [String: TaskStrategyFileConfig] = [:]
        let decoder = JSONDecoder()
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let config = try? decoder.decode(TaskStrategyFileConfig.self, from: data) else {
                continue
            }
            byId[config.strategyID] = config
        }
        mergedConfigurationsCache = byId
        return byId
    }

    private static func allCandidateFiles() -> [URL] {
        var files: [URL] = []
        files.append(contentsOf: bundledStrategyFiles())
        files.append(contentsOf: strategyFiles(in: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BulingIsland/TaskStrategies")))
        return files
    }

    private static func bundledStrategyFiles() -> [URL] {
        guard let base = Bundle.module.resourceURL else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "json" else { continue }
            files.append(url)
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func strategyFiles(in directory: URL?) -> [URL] {
        guard let directory else { return [] }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return items
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
