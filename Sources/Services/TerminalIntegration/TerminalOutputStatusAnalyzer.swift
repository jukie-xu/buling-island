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

        if lower.contains("error") || lower.contains("failed") || lower.contains("exception")
            || lower.contains("auth_error") || lower.contains("401") || lower.contains("unauthorized")
            || lower.contains("报错") || lower.contains("失败") || lower.contains("错误") {
            return ("错误: \(truncate(compact, max: 42))", "error")
        }
        if lower.contains("allow") || lower.contains("approve") || lower.contains("[y/n]") || lower.contains("(y/n)")
            || lower.contains("请确认") || lower.contains("请选择") || lower.contains("是否允许") {
            return ("等待确认: \(truncate(compact, max: 42))", "warn")
        }
        if lower.contains("billowing") || lower.contains("thinking") || lower.contains("analyzing")
            || lower.contains("executing") || lower.contains("processing") || lower.contains("处理中") {
            return ("执行中: \(truncate(compact, max: 42))", "busy")
        }
        if lower.contains("done") || lower.contains("completed") || lower.contains("success")
            || lower.contains("已完成") || lower.contains("成功") {
            return ("已完成: \(truncate(compact, max: 42))", "success")
        }
        if lower.contains("running") || lower.contains("processing") || lower.contains("executing")
            || lower.contains("thinking") || lower.contains("处理中") || lower.contains("执行中") {
            return ("执行中: \(truncate(compact, max: 42))", "busy")
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
