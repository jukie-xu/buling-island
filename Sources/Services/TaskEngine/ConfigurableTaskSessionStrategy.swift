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
        supportsRule.matches(title: session.title, tail: session.tailOutput)
    }

    func analyze(session: CapturedTerminalSession) -> TaskSessionRawAnalysis {
        let compact = TaskSessionTextToolkit.compactTailText(session.tailOutput)
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

        return TaskSessionRawAnalysis(
            lifecycle: lifecycle,
            renderTone: toneForLifecycle(lifecycle),
            secondaryText: extraction.extract(
                lifecycle: lifecycle,
                tail: session.tailOutput,
                compact: compact
            ),
            interactionOptions: lifecycle == .waitingInput ? TaskSessionTextToolkit.interactionOptions(from: session.tailOutput) : []
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
    static func loadConfiguredStrategies() -> [any TaskSessionStrategy] {
        let urls = allCandidateFiles()
        guard !urls.isEmpty else { return [] }

        let decoder = JSONDecoder()
        var parsed: [TaskStrategyFileConfig] = []
        parsed.reserveCapacity(urls.count)

        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let config = try? decoder.decode(TaskStrategyFileConfig.self, from: data) else {
                continue
            }
            parsed.append(config)
        }

        var seen = Set<String>()
        return parsed
            .filter { seen.insert($0.strategyID).inserted }
            .map { ConfigurableTaskSessionStrategy(config: $0) as any TaskSessionStrategy }
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
