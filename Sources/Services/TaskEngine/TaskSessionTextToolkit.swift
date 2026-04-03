import Foundation

enum TaskSessionTextToolkit {
    static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
    }

    static func normalizedOutputLines(from tail: String) -> [String] {
        tail
            .split(whereSeparator: \.isNewline)
            .map { sanitizeLine(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isUserInputCommandLine($0) }
            .filter { !isShellPromptLine($0) }
            .filter { !isNoiseLine($0) }
            .filter { !isInputAreaLine($0) }
    }

    static func normalizedDisplayLines(from tail: String) -> [String] {
        tail
            .split(whereSeparator: \.isNewline)
            .map { sanitizeLine(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isShellPromptLine($0) }
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
        let lines = normalizedDisplayLines(from: tail)
        for line in lines.reversed() where line.contains("⎿") {
            let cleaned = normalizeReplyLine(line)
            if !cleaned.isEmpty { return cleaned }
        }
        for line in lines.reversed() {
            let cleaned = normalizeReplyLine(line)
            if cleaned.isEmpty { continue }
            if isUserInputCommandLine(cleaned) { continue }
            if isShellPromptLine(cleaned) { continue }
            if isNoiseLine(cleaned) || isInputAreaLine(cleaned) { continue }
            return cleaned
        }
        return nil
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

    static func interactionOptions(from tail: String) -> [TaskInteractionOption] {
        let lines = tail
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var options: [TaskInteractionOption] = []
        options.reserveCapacity(4)
        var parsedFromNumberedMenu = false

        for line in lines.reversed() {
            guard let option = parseNumberedOptionLine(line) else { continue }
            parsedFromNumberedMenu = true
            if options.contains(where: { $0.id == option.id || $0.input == option.input }) {
                continue
            }
            options.append(option)
            if options.count >= 6 { break }
        }

        if options.isEmpty {
            let compact = compactTailText(tail).lowercased()
            if compact.contains("[y/n]") || compact.contains("(y/n)") {
                options = [
                    TaskInteractionOption(id: "yes", label: "Yes", input: "y", submit: true),
                    TaskInteractionOption(id: "no", label: "No", input: "n", submit: true),
                ]
            }
        }

        return parsedFromNumberedMenu ? options.reversed() : options
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
            "mcp server failed",
            "· /mcp",
        ]
        if noiseMarkers.contains(where: { lower.contains($0) }) {
            return true
        }
        if line.contains("🤖"), line.contains("⚡") {
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

    static func isShellPromptLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$ ") || trimmed.hasPrefix("# ") || trimmed.hasPrefix("% ") {
            return true
        }
        if matchesRegex(#"^[A-Za-z0-9._-]+@[^ ]+\s+.+\s[%#$](\s+.*)?$"#, in: trimmed) {
            return true
        }
        return false
    }

    private static func normalizeReplyLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*⎿\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeLine(_ line: String) -> String {
        var s = line.replacingOccurrences(of: "\u{00A0}", with: " ")
        let ansiPattern = "\u{001B}\\[[0-9;?]*[ -/]*[@-~]"
        s = s.replacingOccurrences(
            of: ansiPattern,
            with: "",
            options: .regularExpression
        )
        return s
    }

    private static func matchesRegex(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func parseNumberedOptionLine(_ line: String) -> TaskInteractionOption? {
        let pattern = #"^\s*(\d+)\.\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)),
              match.numberOfRanges >= 3,
              let numberRange = Range(match.range(at: 1), in: line),
              let labelRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let number = String(line[numberRange])
        var label = String(line[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty { return nil }
        let lower = label.lowercased()
        if lower == "other" { return nil }

        var input = ""
        if let shortcut = trailingShortcutKey(in: label) {
            input = shortcut
        } else if lower.hasPrefix("yes") {
            input = "y"
        } else if lower.hasPrefix("no") {
            input = "n"
        }
        if input.isEmpty { return nil }

        label = label.replacingOccurrences(of: "\\s*\\([^)]+\\)\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TaskInteractionOption(
            id: "opt-\(number)-\(input.lowercased())",
            label: truncate(label, max: 42),
            input: input,
            submit: true
        )
    }

    private static func trailingShortcutKey(in text: String) -> String? {
        let pattern = #"\(([^)]+)\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
              match.numberOfRanges >= 2,
              let keyRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let key = text[keyRange]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if key.count == 1 { return key }
        return nil
    }
}
