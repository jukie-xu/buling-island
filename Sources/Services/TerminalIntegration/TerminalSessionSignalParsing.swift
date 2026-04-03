import Foundation

struct TerminalSessionSignal {
    let summaryText: String
    let tone: String
    let interactionHint: String?
    let errorFingerprint: String?
}

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
        let builtins: [any TerminalSessionSignalParser] = [
            ClaudeCodexSessionSignalParser(),
            GenericSessionSignalParser(),
        ]
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

struct ClaudeCodexSessionSignalParser: TerminalSessionSignalParser {
    let parserID = "claude-codex"
    let priority = 260

    func supports(session: CapturedTerminalSession) -> Bool {
        let titleLower = session.title.lowercased()
        let tailLower = session.tailOutput.lowercased()
        let markers = [
            "claude", "claude code", "what should claude do",
            "billowing", "sonnet", "ask claude", "esc to interrupt",
            "codex", "openai codex", "gpt-5-codex", "responses api", "assistant",
        ]
        if titleLower.contains("claude") || titleLower.contains("codex") { return true }
        return markers.contains(where: { tailLower.contains($0) })
    }

    func parse(session: CapturedTerminalSession) -> TerminalSessionSignal {
        let compact = TaskSessionTextToolkit.compactTailText(session.tailOutput)
        let lower = compact.lowercased()

        if compact.isEmpty {
            return TerminalSessionSignal(summaryText: "暂无可分析输出", tone: "info", interactionHint: nil, errorFingerprint: nil)
        }

        if TaskSessionTextToolkit.containsErrorMarkers(lower) {
            let err = TaskSessionTextToolkit.lastErrorText(from: session.tailOutput)
            return TerminalSessionSignal(
                summaryText: err,
                tone: "error",
                interactionHint: nil,
                errorFingerprint: normalizeFingerprint(err)
            )
        }

        if TaskSessionTextToolkit.containsWaitingMarkers(lower) {
            let text = TaskSessionTextToolkit.truncate(compact, max: 88)
            return TerminalSessionSignal(
                summaryText: text,
                tone: "warn",
                interactionHint: text,
                errorFingerprint: nil
            )
        }

        if TaskSessionTextToolkit.containsSuccessMarkers(lower) {
            return TerminalSessionSignal(
                summaryText: TaskSessionTextToolkit.truncate(compact, max: 88),
                tone: "success",
                interactionHint: nil,
                errorFingerprint: nil
            )
        }

        if TaskSessionTextToolkit.containsRunningMarkers(lower) {
            return TerminalSessionSignal(
                summaryText: TaskSessionTextToolkit.truncate(compact, max: 88),
                tone: "busy",
                interactionHint: nil,
                errorFingerprint: nil
            )
        }

        return TerminalSessionSignal(
            summaryText: TaskSessionTextToolkit.truncate(compact, max: 88),
            tone: "info",
            interactionHint: nil,
            errorFingerprint: nil
        )
    }

    private func normalizeFingerprint(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "[0-9a-f]{6,}", with: "#", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\b\\d+\\b", with: "#", options: .regularExpression)
        return s
    }
}

struct GenericSessionSignalParser: TerminalSessionSignalParser {
    let parserID = "generic"
    let priority = 10

    func supports(session: CapturedTerminalSession) -> Bool {
        _ = session
        return true
    }

    func parse(session: CapturedTerminalSession) -> TerminalSessionSignal {
        let analyzed = TerminalOutputStatusAnalyzer.analyzeStatus(text: session.tailOutput)
        let compact = TaskSessionTextToolkit.compactTailText(session.tailOutput)
        if analyzed.tone == "error" {
            let err = TaskSessionTextToolkit.lastErrorText(from: session.tailOutput)
            return TerminalSessionSignal(
                summaryText: err,
                tone: "error",
                interactionHint: nil,
                errorFingerprint: normalized(err)
            )
        }
        if analyzed.tone == "warn" {
            let hint = compact.isEmpty ? analyzed.text : TaskSessionTextToolkit.truncate(compact, max: 88)
            return TerminalSessionSignal(
                summaryText: hint,
                tone: "warn",
                interactionHint: hint,
                errorFingerprint: nil
            )
        }
        let text = compact.isEmpty ? analyzed.text : TaskSessionTextToolkit.truncate(compact, max: 88)
        return TerminalSessionSignal(summaryText: text, tone: analyzed.tone, interactionHint: nil, errorFingerprint: nil)
    }

    private func normalized(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "[0-9a-f]{6,}", with: "#", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\b\\d+\\b", with: "#", options: .regularExpression)
        return s
    }
}
