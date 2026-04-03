import Foundation

/// 对各终端回传的原始缓冲区做与宿主无关的启发式分析（可随产品迭代统一调参）。
enum TerminalOutputStatusAnalyzer {

    static func analyzeStatus(text: String) -> (text: String, tone: String) {
        let outputLines = normalizedOutputLines(from: text)
        let compact = outputLines.suffix(6).joined(separator: " ")
        let lower = compact.lowercased()

        if compact.isEmpty {
            return ("暂无可分析输出", "info")
        }

        if TaskSessionTextToolkit.containsErrorMarkers(lower) {
            return ("错误: \(truncate(compact, max: 42))", "error")
        }
        if TaskSessionTextToolkit.containsWaitingMarkers(lower) {
            return ("等待确认: \(truncate(compact, max: 42))", "warn")
        }
        if TaskSessionTextToolkit.containsRunningMarkers(lower) {
            return ("执行中: \(truncate(compact, max: 42))", "busy")
        }
        if TaskSessionTextToolkit.containsSuccessMarkers(lower) {
            return ("已完成: \(truncate(compact, max: 42))", "success")
        }
        return (truncate(compact, max: 42), "info")
    }

    private static func normalizedOutputLines(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isUserInputCommandLine($0) }
    }

    private static func isUserInputCommandLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("❯") || trimmed.hasPrefix(">") {
            return true
        }
        return false
    }

    private static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
    }
}
