import Foundation

struct TerminalSessionSignal {
    let summaryText: String
    let tone: String
    let interactionHint: String?
    let errorFingerprint: String?
}

private let manualConfirmationReminder = "您的任务需要手工确认。"

protocol TerminalSessionSignalParser {
    var parserID: String { get }
    var priority: Int { get }

    func supports(session: CapturedTerminalSession) -> Bool
    func parse(session: CapturedTerminalSession) -> TerminalSessionSignal
}

@MainActor
enum TerminalSessionSignalParserRegistry {
    private static var extraParsers: [any TerminalSessionSignalParser] = []

    static func register(_ parser: any TerminalSessionSignalParser) {
        extraParsers.removeAll { $0.parserID == parser.parserID }
        extraParsers.append(parser)
    }

    static func replaceExtras(_ parsers: [any TerminalSessionSignalParser]) {
        var seen = Set<String>()
        extraParsers = parsers.filter { seen.insert($0.parserID).inserted }
    }

    static func resolvedParsers() -> [any TerminalSessionSignalParser] {
        let builtins: [any TerminalSessionSignalParser] = [TaskStrategySessionSignalParser()]
        var seen = Set<String>()
        let merged = extraParsers + builtins
        return merged
            .filter { seen.insert($0.parserID).inserted }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.parserID < rhs.parserID
                }
                return lhs.priority > rhs.priority
            }
    }
}

/// 菜单栏药丸等与任务引擎共用 `TaskStrategies/*.json` 解析，避免 Swift 内重复一套 running/error 启发式。
struct TaskStrategySessionSignalParser: TerminalSessionSignalParser {
    let parserID = "task-strategies"
    let priority = 500

    func supports(session: CapturedTerminalSession) -> Bool {
        _ = session
        return true
    }

    func parse(session: CapturedTerminalSession) -> TerminalSessionSignal {
        let strategy = TaskSessionStrategyRegistry.strategy(for: session)
        let analysis = strategy.analyze(session: session)
        let normalizedTail = session.standardizedTailOutput
        let compact = TaskSessionTextToolkit.analysisCompactTailText(normalizedTail)

        if compact.isEmpty {
            let summary = analysis.secondaryText.isEmpty ? "暂无可分析输出" : analysis.secondaryText
            return TerminalSessionSignal(summaryText: summary, tone: "info", interactionHint: nil, errorFingerprint: nil)
        }

        switch analysis.lifecycle {
        case .error:
            let err = TaskSessionTextToolkit.lastErrorText(from: normalizedTail)
            let summary = err.isEmpty ? analysis.secondaryText : err
            return TerminalSessionSignal(
                summaryText: summary,
                tone: "error",
                interactionHint: nil,
                errorFingerprint: normalizeFingerprint(summary)
            )
        case .waitingInput:
            return TerminalSessionSignal(
                summaryText: manualConfirmationReminder,
                tone: "warn",
                interactionHint: manualConfirmationReminder,
                errorFingerprint: nil
            )
        case .success:
            let summary = analysis.secondaryText.isEmpty
                ? TaskSessionTextToolkit.truncate(compact, max: 88)
                : analysis.secondaryText
            return TerminalSessionSignal(summaryText: summary, tone: "success", interactionHint: nil, errorFingerprint: nil)
        case .running:
            let summary = analysis.secondaryText.isEmpty
                ? TaskSessionTextToolkit.truncate(compact, max: 88)
                : analysis.secondaryText
            return TerminalSessionSignal(summaryText: summary, tone: "busy", interactionHint: nil, errorFingerprint: nil)
        case .idle, .inactiveTool:
            let summary = analysis.secondaryText.isEmpty
                ? TaskSessionTextToolkit.truncate(compact, max: 88)
                : analysis.secondaryText
            return TerminalSessionSignal(summaryText: summary, tone: "info", interactionHint: nil, errorFingerprint: nil)
        }
    }

    private func normalizeFingerprint(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "[0-9a-f]{6,}", with: "#", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\b\\d+\\b", with: "#", options: .regularExpression)
        return s
    }
}
