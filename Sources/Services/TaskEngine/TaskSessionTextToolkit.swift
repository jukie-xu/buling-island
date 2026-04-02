import Foundation

enum TaskSessionTextToolkit {
    static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
    }

    static func normalizedOutputLines(from tail: String) -> [String] {
        tail
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isUserInputCommandLine($0) }
            .filter { !isNoiseLine($0) }
            .filter { !isInputAreaLine($0) }
    }

    static func normalizedDisplayLines(from tail: String) -> [String] {
        tail
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isNoiseLine($0) }
            .filter { !isInputAreaLine($0) }
    }

    static func compactTailText(_ tail: String) -> String {
        normalizedOutputLines(from: tail)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractLatestUserPrompt(from tail: String) -> String? {
        let lines = tail
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            guard isUserInputCommandLine(line) else { continue }
            var prompt = line
                .replacingOccurrences(of: "^[❯›»>]\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.isEmpty { continue }
            if isNoiseLine(prompt) || isInputAreaLine(prompt) { continue }
            if prompt.lowercased().contains("what should claude do") { continue }
            if prompt.count > 120 {
                prompt = String(prompt.prefix(120))
            }
            return prompt
        }
        return nil
    }

    static func extractLatestReply(from tail: String) -> String? {
        normalizedDisplayLines(from: tail)
            .reversed()
            .first(where: { !isUserInputCommandLine($0) })
    }

    static func lastErrorText(from tail: String) -> String {
        let lines = normalizedOutputLines(from: tail)
        let markers = [
            "error", "failed", "exception", "unauthorized", "auth_error", "401", "timeout",
            "报错", "失败", "错误", "超时",
        ]
        for line in lines.reversed() {
            let lower = line.lowercased()
            if markers.contains(where: { lower.contains($0) }) {
                return truncate(line, max: 88)
            }
        }
        if let last = lines.last {
            return truncate(last, max: 88)
        }
        return "检测到异常"
    }

    static func twoLinesPromptAndReply(from tail: String) -> String {
        let prompt = extractLatestUserPrompt(from: tail)
        let reply = extractLatestReply(from: tail)
        if let prompt, let reply {
            return "\(truncate(prompt, max: 30))\n\(truncate(reply, max: 88))"
        }
        if let reply {
            return "（未识别到提问）\n\(truncate(reply, max: 88))"
        }
        return "暂无可展示输出"
    }

    static func twoLinesPromptAndError(from tail: String) -> String {
        let prompt = extractLatestUserPrompt(from: tail)
        let err = lastErrorText(from: tail)
        if let prompt {
            return "\(truncate(prompt, max: 30))\n\(truncate(err, max: 88))"
        }
        return "（未识别到提问）\n\(truncate(err, max: 88))"
    }

    static func containsErrorMarkers(_ textLowercased: String) -> Bool {
        [
            "error", "failed", "exception", "auth_error", "unauthorized", "401",
            "timeout", "timed out", "报错", "失败", "错误", "超时",
        ].contains(where: { textLowercased.contains($0) })
    }

    static func containsWaitingMarkers(_ textLowercased: String) -> Bool {
        [
            "allow", "approve", "confirm", "[y/n]", "(y/n)",
            "请确认", "请选择", "是否允许",
        ].contains(where: { textLowercased.contains($0) })
    }

    static func containsRunningMarkers(_ textLowercased: String) -> Bool {
        [
            "running", "executing", "processing", "thinking", "analyzing",
            "处理中", "执行中", "思考中",
        ].contains(where: { textLowercased.contains($0) })
    }

    static func containsSuccessMarkers(_ textLowercased: String) -> Bool {
        [
            "done", "completed", "finished", "success", "已完成", "成功", "完成",
        ].contains(where: { textLowercased.contains($0) })
    }

    static func isUserInputCommandLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("❯") || trimmed.hasPrefix("›") || trimmed.hasPrefix("»") || trimmed.hasPrefix(">")
    }

    static func isNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let noiseMarkers = [
            "esc to interrupt",
            "image in clipboard",
            "ctrl+v to paste",
            "for shortcuts",
            "update available",
            "run: brew upgrade claude-code",
            "claude code (",
            "claude code v",
            "sonnet",
            "api usage",
            "recent activity",
            "tips for getting started",
            "welcome back",
        ]
        if noiseMarkers.contains(where: { lower.contains($0) }) {
            return true
        }
        let stripped = lower.replacingOccurrences(of: " ", with: "")
        if stripped.allSatisfy({ "-_=|·•:".contains($0) }) {
            return true
        }
        return false
    }

    static func isInputAreaLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let inputMarkers = [
            "send message",
            "shift+enter",
            "press enter",
            "type a message",
            "ask claude",
            "esc to interrupt",
        ]
        if inputMarkers.contains(where: { lower.contains($0) }) {
            return true
        }
        if line.contains("╭") || line.contains("╰")
            || line.contains("┌") || line.contains("└")
            || line.contains("│") || line.contains("┃")
            || line.contains("┆") || line.contains("─") {
            return true
        }
        if line == ":" || line == ">" || line.hasPrefix("> ") {
            return true
        }
        return false
    }
}
