import Foundation

enum TaskSessionTextToolkit {
    /// 终端后端可保留各自的捕获实现，但一旦进入任务分析链路，必须先经过这一层标准化。
    /// 目标不是“修饰”文本，而是尽可能消除不同终端 API 在换行、ANSI、控制字符、空白字符上的差异。
    static func standardizedTerminalText(from tail: String) -> String {
        guard !tail.isEmpty else { return "" }
        var text = tail
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        let ansiPatterns = [
            "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",     // CSI
            "\u{001B}\\][\\s\\S]*?(?:\u{0007}|\u{001B}\\\\)", // OSC
            "\u{001B}[()][A-Za-z0-9]",            // charset / mode switch
        ]
        for pattern in ansiPatterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        text = String(text.unicodeScalars.filter { scalar in
            if scalar == "\n" || scalar == "\t" { return true }
            return !CharacterSet.controlCharacters.contains(scalar)
        })

        let normalizedLines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { rawLine in
                normalizeFramedTerminalLine(String(rawLine))
                    .replacingOccurrences(of: "\t", with: "    ")
                    .replacingOccurrences(of: "[ ]{2,}$", with: "", options: .regularExpression)
            }

        return normalizedLines.joined(separator: "\n")
    }

    private static func normalizeFramedTerminalLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return line }

        if matchesRegex(#"^[╭╰╮╯┌└┐┘─═━]+$"#, in: trimmed) {
            return ""
        }

        if let range = line.range(of: #"^[\s│┃]+(.*?)[\s│┃]+$"#, options: .regularExpression) {
            let candidate = String(line[range])
            if let inner = firstCapturedGroup(in: candidate, pattern: #"^[\s│┃]+(.*?)[\s│┃]+$"#, group: 1),
               shouldUnwrapFramedTerminalInnerText(inner) {
                return inner
            }
        }

        return line
    }

    private static func shouldUnwrapFramedTerminalInnerText(_ inner: String) -> Bool {
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("openai codex") { return true }
        if lower.hasPrefix("model:") { return true }
        if lower.hasPrefix("directory:") { return true }
        return false
    }

    static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
    }

    static func normalizedOutputLines(from tail: String) -> [String] {
        standardizedTerminalText(from: tail)
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isUserInputCommandLine($0) }
            .filter { !isShellPromptLine($0) }
            .filter { !isNoiseLine($0) }
            .filter { !isInputAreaLine($0) }
    }

    static func normalizedDisplayLines(from tail: String) -> [String] {
        standardizedTerminalText(from: tail)
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
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

    static func analysisOutputLines(from tail: String, maxTailLines: Int = 24) -> [String] {
        let lines = normalizedOutputLines(from: tail)
        guard lines.count > maxTailLines else { return lines }
        return Array(lines.suffix(maxTailLines))
    }

    static func analysisCompactTailText(_ tail: String, maxTailLines: Int = 24) -> String {
        analysisOutputLines(from: tail, maxTailLines: maxTailLines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractLatestUserPrompt(from tail: String) -> String? {
        let lines = standardizedTerminalText(from: tail)
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for index in lines.indices.reversed() {
            let line = lines[index]
            guard isUserInputCommandLine(line) else { continue }
            var prompt = line
                .replacingOccurrences(of: "^[❯›»>]\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.isEmpty { continue }
            if isNoiseLine(prompt) || isInputAreaLine(prompt) { continue }
            if isCodexUserInputNoise(prompt) { continue }
            if isCodexPlaceholderPrompt(promptLineIndex: index, in: lines) { continue }
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
            if cleaned.isEmpty { continue }
            if isTerminalScrollbackArtifactLine(cleaned) { continue }
            if isAuxiliaryTaskChromeLine(cleaned) { continue }
            return cleaned
        }
        for line in lines.reversed() {
            let cleaned = normalizeReplyLine(line)
            if cleaned.isEmpty { continue }
            if isUserInputCommandLine(cleaned) { continue }
            if isShellPromptLine(cleaned) { continue }
            if isNoiseLine(cleaned) || isInputAreaLine(cleaned) { continue }
            if isTerminalScrollbackArtifactLine(cleaned) { continue }
            if isAuxiliaryTaskChromeLine(cleaned) { continue }
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

    // MARK: - 任务面板摘要（双行：提问 / 回复或状态）

    /// 未识别到用户输入行（如 `›` / `❯`）时任务面板副文案。
    static let taskPanelNoTaskPlaceholder = "暂无任务"

    /// 任务策略判定为成功后的第二行固定文案。
    static let taskPanelCompletedLine = "任务执行完毕"

    /// 已识别提问但尚未解析到助手输出时的第二行占位。
    static let taskPanelRunningPlaceholder = "处理中…"

    static let taskPanelPromptMaxLength = 120
    static let taskPanelReplyMaxLength = 88

    static func composeWaitingInputDisplayText(
        interactionPrompt: TaskInteractionPrompt?,
        interactionOptions: [TaskInteractionOption],
        fallback: String
    ) -> String {
        if let prompt = interactionPrompt {
            var lines: [String] = [prompt.title]
            if let body = prompt.body, !body.isEmpty {
                lines.append(body)
            }
            if !prompt.options.isEmpty {
                lines.append(
                    prompt.options.enumerated().map { index, option in
                        "\(index + 1). \(option.label)"
                    }.joined(separator: "\n")
                )
            } else if !interactionOptions.isEmpty {
                lines.append(
                    interactionOptions.enumerated().map { index, option in
                        "\(index + 1). \(option.label)"
                    }.joined(separator: "\n")
                )
            }
            if let instruction = prompt.instruction, !instruction.isEmpty {
                lines.append(instruction)
            }
            let joined = lines
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
            if !joined.isEmpty { return joined }
        }
        return fallback
    }

    /// 根据终端尾部与生命周期编排任务面板 `secondaryText`（策略层原始 extraction 在引擎中可被此项覆盖）。
    static func composeTaskPanelSecondaryText(
        tail: String,
        lifecycle: TaskLifecycleState,
        promptNow: String?,
        replyNow: String?,
        memory: TaskSessionPanelMemory
    ) -> String {
        let prompt = trimNonEmpty(promptNow) ?? trimNonEmpty(memory.cachedUserPrompt)

        guard let prompt else {
            if lifecycle == .error {
                return truncate(lastErrorText(from: tail), max: taskPanelReplyMaxLength)
            }
            return taskPanelNoTaskPlaceholder
        }

        let reply = sanitizedPanelReply(replyNow) ?? sanitizedPanelReply(memory.cachedAgentReply)

        switch lifecycle {
        case .running, .waitingInput:
            let second = reply ?? taskPanelRunningPlaceholder
            return "\(truncate(prompt, max: taskPanelPromptMaxLength))\n\(truncate(second, max: taskPanelReplyMaxLength))"
        case .success:
            return "\(truncate(prompt, max: taskPanelPromptMaxLength))\n\(taskPanelCompletedLine)"
        case .error:
            let err = truncate(lastErrorText(from: tail), max: taskPanelReplyMaxLength)
            return "\(truncate(prompt, max: taskPanelPromptMaxLength))\n\(err)"
        case .idle, .inactiveTool:
            if let reply {
                return "\(truncate(prompt, max: taskPanelPromptMaxLength))\n\(truncate(reply, max: taskPanelReplyMaxLength))"
            }
            return truncate(prompt, max: taskPanelPromptMaxLength)
        }
    }

    /// 在每轮刷新、状态机稳定之后更新缓存（`running` / `waitingInput` 时写入最新回复摘要）。
    static func updateTaskPanelMemory(
        promptNow: String?,
        replyNow: String?,
        stabilizedLifecycle: TaskLifecycleState,
        memory: inout TaskSessionPanelMemory
    ) {
        if let p = trimNonEmpty(promptNow) {
            if memory.cachedUserPrompt != p {
                memory.cachedAgentReply = nil
            }
            memory.cachedUserPrompt = p
        }

        switch stabilizedLifecycle {
        case .running, .waitingInput:
            if let r = sanitizedPanelReply(replyNow) {
                memory.cachedAgentReply = r
            }
        case .success, .error, .idle, .inactiveTool:
            break
        }
    }

    private static func trimNonEmpty(_ string: String?) -> String? {
        guard let t = string?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// 滚动缓冲里可能出现、但不应作为助手摘要的残留（如 Ctrl+C 显示为 `^C`）；Terminal.app 的 `history` 常含较早会话内容。
    private static func isTerminalScrollbackArtifactLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if t.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) { return true }
        // Shell/终端把 Ctrl+C 等显示成字面量 `^C`（history 里常见，非当前可见「回复」）
        if matchesRegex(#"(?i)^\^(c|d|z)\s*$"#, in: t) { return true }
        if matchesRegex(#"(?i)^(\^[cdz])(\s+\^[cdz])*\s*$"#, in: t) { return true }
        return false
    }

    private static func sanitizedPanelReply(_ string: String?) -> String? {
        guard let t = trimNonEmpty(string) else { return nil }
        if isTerminalScrollbackArtifactLine(t) { return nil }
        return t
    }

    /// 不参与「助手最新回复」摘要的营销横幅、状态脚注等（不影响用于生命周期判断的 compact）。
    private static func isAuxiliaryTaskChromeLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("openai codex") { return true }
        if lower.hasPrefix(">_ openai codex") { return true }
        if lower.hasPrefix("model:") { return true }
        if lower.hasPrefix("directory:") { return true }
        if lower.contains("tip: run codex app") { return true }
        if lower.contains("tip: new try the codex app") { return true }
        if lower.contains("tip: new try the codex") { return true }
        if lower.contains("try the codex app with 2x rate") { return true }
        if matchesRegex(#"(?i)\bgpt-[0-9.]+\s+\S+\s+·\s*\d+%\s+left\s+·"#, in: line) { return true }
        return false
    }

    /// 排除 Codex 顶栏命令（非用户任务提问），避免误当作「用户输入」缓存。
    private static func isCodexUserInputNoise(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if lower == "/init" || lower.hasPrefix("/init ") { return true }
        if lower == "/model" || lower.hasPrefix("/model ") { return true }
        return false
    }

    private static func isCodexPlaceholderPrompt(promptLineIndex index: Int, in lines: [String]) -> Bool {
        guard index >= 0 && index < lines.count else { return false }

        let nextNonEmpty = lines[(index + 1)...].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let previousNonEmpty = index > 0
            ? lines[..<index].reversed().first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            : nil

        guard let nextNonEmpty else { return false }
        let nextLower = nextNonEmpty.lowercased()
        let hasCodexFooterAfterPrompt = matchesRegex(#"(?i)\bgpt-[0-9.]+\s+\S+\s+·\s*\d+%\s+left\s+·"#, in: nextNonEmpty)
            || nextLower.contains("/model to change")

        guard hasCodexFooterAfterPrompt else { return false }

        guard let previousNonEmpty else { return false }
        let previousLower = previousNonEmpty.lowercased()
        let hasRunningLineBeforePrompt = previousLower.contains("working (")
            || previousLower.contains("• working")
            || previousLower.contains("running (")
            || previousLower.contains("处理中")

        return hasRunningLineBeforePrompt
    }

    static func interactionOptions(from tail: String) -> [TaskInteractionOption] {
        extractInteractionPrompt(from: tail)?.options ?? []
    }

    static func extractInteractionPrompt(from tail: String) -> TaskInteractionPrompt? {
        let lines = standardizedTerminalText(from: tail)
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let relevantLines = interactionRelevantLines(from: lines)

        if let menuPrompt = parseStructuredMenuPrompt(from: relevantLines) {
            return menuPrompt
        }

        if let freeformPrompt = parseFreeformPrompt(from: relevantLines) {
            return freeformPrompt
        }

        let compact = compactTailText(tail).lowercased()
        if compact.contains("[y/n]") || compact.contains("(y/n)") {
            let question = extractInteractionQuestion(from: relevantLines) ?? "需要你的确认"
            let options = [
                TaskInteractionOption(id: "yes", label: "Yes", input: "y", submit: true, shortcutHint: "y"),
                TaskInteractionOption(id: "no", label: "No", input: "n", submit: true, shortcutHint: "n"),
            ]
            return TaskInteractionPrompt(
                title: truncate(question, max: 90),
                body: extractInteractionBody(from: relevantLines, question: question, options: options),
                instruction: extractInteractionInstruction(from: relevantLines),
                selectionMode: .single,
                presentationStyle: .grid,
                options: options,
                confirmButton: nil,
                controlButtons: []
            )
        }

        return nil
    }

    private static func interactionRelevantLines(from lines: [String]) -> [String] {
        guard !lines.isEmpty else { return [] }

        let triggerMatchers: [(String) -> Bool] = [
            { $0.localizedCaseInsensitiveContains("would you like to run the following command?") },
            { $0.localizedCaseInsensitiveContains("how would you like") },
            { $0.localizedCaseInsensitiveContains("which mode") },
            { $0.localizedCaseInsensitiveContains("what should claude do instead") },
            { $0.localizedCaseInsensitiveContains("what should codex do instead") },
            { $0.localizedCaseInsensitiveContains("approval required") },
            { $0.localizedCaseInsensitiveContains("awaiting approval") },
            { $0.localizedCaseInsensitiveContains("choose one or more") },
            { $0.contains("[y/n]") || $0.contains("(y/n)") },
        ]

        for index in lines.indices.reversed() {
            let line = lines[index]
            if triggerMatchers.contains(where: { $0(line) }) {
                return Array(lines[index...])
            }
        }
        return lines
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
            "what should claude do instead", "what should codex do instead",
            "would you like to run the following command?",
            "how would you like", "which mode",
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
        if trimmed.hasPrefix("❯") || trimmed.hasPrefix("›") || trimmed.hasPrefix("»") {
            return true
        }
        if trimmed == ">" { return true }
        if trimmed.hasPrefix("> ") { return true }
        return false
    }

    static func isNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if isStructuredCodeExcerptLine(line) {
            return true
        }
        let noiseMarkers = [
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
        if lower.contains("esc to interrupt"),
           !lower.contains("working"),
           !lower.contains("sublimating"),
           !lower.contains("retrying") {
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
        ]
        if inputMarkers.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower.contains("esc to interrupt"),
           !lower.contains("working"),
           !lower.contains("sublimating"),
           !lower.contains("retrying") {
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

    private static func isStructuredCodeExcerptLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if matchesRegex(#"^\d+\s+[+\-].*$"#, in: trimmed) { return true }
        if matchesRegex(#"^\d+\s+[│└].*$"#, in: trimmed) { return true }
        if matchesRegex(#"^[│└].*$"#, in: trimmed) { return true }
        if trimmed == "⋮" { return true }
        if matchesRegex(#"^…\s+\+\d+\s+lines$"#, in: trimmed) { return true }
        return false
    }

    private static func matchesRegex(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func firstCapturedGroup(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        let capture = match.range(at: group)
        guard capture.location != NSNotFound, let swiftRange = Range(capture, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func parseStructuredMenuPrompt(from lines: [String]) -> TaskInteractionPrompt? {
        let question = extractInteractionQuestion(from: lines)
        var options: [TaskInteractionOption] = []
        options.reserveCapacity(6)

        for line in lines.reversed() {
            guard let option = parseMenuOptionLine(line) else { continue }
            if options.contains(where: { $0.id == option.id || (!option.input.isEmpty && $0.input == option.input) }) {
                continue
            }
            options.append(option)
            if options.count >= 8 { break }
        }

        let orderedOptions = options.reversed()
        guard !orderedOptions.isEmpty else { return nil }

        let mode = detectSelectionMode(from: lines)
        let presentationStyle: TaskInteractionPrompt.PresentationStyle = {
            if mode == .freeform { return .freeform }
            return isArrowNavigationMenu(lines) ? .navigationList : .grid
        }()
        let normalizedOptions: [TaskInteractionOption] = orderedOptions.map { option in
            TaskInteractionOption(
                id: option.id,
                label: option.label,
                input: option.input,
                submit: mode == .single ? option.submit : false,
                kind: option.kind,
                shortcutHint: option.shortcutHint,
                actions: option.actions,
                isInitiallySelected: option.isInitiallySelected
            )
        }

        let selectedIndex = normalizedOptions.firstIndex(where: \.isInitiallySelected) ?? 0
        let navigationOptions = presentationStyle == .navigationList
            ? buildNavigationOptions(from: normalizedOptions, selectedIndex: selectedIndex)
            : normalizedOptions
        let controlButtons = presentationStyle == .navigationList
            ? buildNavigationControlButtons(from: lines)
            : []

        return TaskInteractionPrompt(
            title: truncate(question ?? "请选择下一步操作", max: 90),
            body: extractInteractionBody(from: lines, question: question, options: navigationOptions),
            instruction: extractInteractionInstruction(from: lines),
            selectionMode: mode,
            presentationStyle: presentationStyle,
            options: Array(navigationOptions),
            confirmButton: mode == .multiple
                ? TaskInteractionOption(id: "confirm-selection", label: "确认", input: "", submit: true, kind: .confirm)
                : nil,
            controlButtons: controlButtons
        )
    }

    private static func parseFreeformPrompt(from lines: [String]) -> TaskInteractionPrompt? {
        guard let question = extractInteractionQuestion(from: lines) else { return nil }
        let lower = question.lowercased()
        let freeformMarkers = [
            "what should claude do instead",
            "what should codex do instead",
            "tell codex what to do differently",
            "tell claude what to do differently",
            "describe what to do next",
            "请说明",
            "请描述",
            "请补充",
        ]
        guard question.contains("?")
                || question.contains("？")
                || freeformMarkers.contains(where: { lower.contains($0) }) else {
            return nil
        }

        return TaskInteractionPrompt(
            title: truncate(question, max: 90),
            body: extractInteractionBody(from: lines, question: question, options: []),
            instruction: extractInteractionInstruction(from: lines),
            selectionMode: .freeform,
            presentationStyle: .freeform,
            options: [],
            confirmButton: TaskInteractionOption(
                id: "activate-session",
                label: "前往终端回复",
                input: "",
                submit: false,
                kind: .activate,
                actions: [.activate]
            ),
            controlButtons: []
        )
    }

    private static func parseMenuOptionLine(_ line: String) -> TaskInteractionOption? {
        parseNumberedOptionLine(line)
            ?? parseBulletOptionLine(line)
            ?? parseCursorOptionLine(line)
    }

    private static func parseNumberedOptionLine(_ line: String) -> TaskInteractionOption? {
        let pattern = #"^\s*(?:[>›❯]\s*)?(?:\[(\d+)\]|(\d+)[\.\)])\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)),
              match.numberOfRanges >= 4,
              let labelRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let number = firstCapturedGroup(in: line, match: match, indexes: [1, 2]) ?? ""
        let rawLabel = String(line[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawLabel.isEmpty, rawLabel.lowercased() != "other" else { return nil }

        let isInitiallySelected = containsSelectionMarker(rawLabel)
        let shortcut = trailingShortcutKey(in: rawLabel)
        let label = normalizedOptionLabel(rawLabel)
        let action = actionForOption(label: label, number: number, shortcut: shortcut)
        return TaskInteractionOption(
            id: "opt-\(number)-\(slug(label))",
            label: truncate(label, max: 42),
            input: action.input,
            submit: action.submit,
            kind: action.kind,
            shortcutHint: shortcut ?? (!number.isEmpty ? number : nil),
            actions: action.actions,
            isInitiallySelected: isInitiallySelected
        )
    }

    private static func parseBulletOptionLine(_ line: String) -> TaskInteractionOption? {
        let pattern = #"^\s*(?:[-*•●○◯▪▫]|-\s*\[[ xX]\])\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)),
              match.numberOfRanges >= 2,
              let labelRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let rawLabel = String(line[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawLabel.isEmpty else { return nil }
        let shortcut = trailingShortcutKey(in: rawLabel)
        let label = normalizedOptionLabel(rawLabel)
        let action = actionForOption(label: label, number: "", shortcut: shortcut)
        return TaskInteractionOption(
            id: "opt-\(slug(label))",
            label: truncate(label, max: 42),
            input: action.input,
            submit: action.submit,
            kind: action.kind,
            shortcutHint: shortcut,
            actions: action.actions,
            isInitiallySelected: containsSelectionMarker(rawLabel)
        )
    }

    private static func parseCursorOptionLine(_ line: String) -> TaskInteractionOption? {
        let pattern = #"^\s*(?:[>›❯→]|[✓✔])\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)),
              match.numberOfRanges >= 2,
              let labelRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let rawLabel = String(line[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawLabel.isEmpty, rawLabel.count <= 42 else { return nil }
        let lower = rawLabel.lowercased()
        let menuMarkers = [
            "read only", "auto", "full access", "allow", "approve", "deny",
            "continue", "cancel", "current", "selected", "mode", "access",
            "on-request", "on-failure", "workspace-write", "danger-full-access",
        ]
        guard menuMarkers.contains(where: { lower.contains($0) }) else { return nil }
        let shortcut = trailingShortcutKey(in: rawLabel)
        let label = normalizedOptionLabel(rawLabel)
        let action = actionForOption(label: label, number: "", shortcut: shortcut)
        return TaskInteractionOption(
            id: "opt-\(slug(label))",
            label: label,
            input: action.input,
            submit: action.submit,
            kind: action.kind,
            shortcutHint: shortcut,
            actions: action.actions,
            isInitiallySelected: true
        )
    }

    private static func extractInteractionQuestion(from lines: [String]) -> String? {
        let filtered = lines
            .map { normalizeReplyLine($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let skipPrefixes = ["1.", "2.", "3.", "4.", "5.", "6.", "7.", "8.", "1)", "2)", "3)"]
        let priorityMatchers: [(String) -> Bool] = [
            { $0.hasPrefix("would you like to run the following command?") },
            { $0.hasPrefix("how would you like") },
            { $0.hasPrefix("which mode") },
            { $0.contains("what should claude do instead") },
            { $0.contains("what should codex do instead") },
            { $0.hasPrefix("approval required") },
            { $0.hasPrefix("awaiting approval") },
            { $0.hasPrefix("please confirm") },
            { $0.hasPrefix("choose") },
            { $0.hasPrefix("select") },
            { $0.hasPrefix("pick") },
            { $0.hasPrefix("是否") },
            { $0.hasPrefix("请确认") },
            { $0.hasPrefix("请选择") },
        ]

        for line in filtered {
            let lower = line.lowercased()
            if skipPrefixes.contains(where: { line.hasPrefix($0) }) { continue }
            if parseMenuOptionLine(line) != nil { continue }
            if isNoiseLine(line) || isInputAreaLine(line) || isShellPromptLine(line) { continue }
            if extractInstructionLine(from: line) != nil { continue }
            if lower.hasPrefix("reason:") { continue }
            if priorityMatchers.contains(where: { $0(lower) }) {
                return line
            }
        }

        for line in filtered.reversed() {
            let lower = line.lowercased()
            if skipPrefixes.contains(where: { line.hasPrefix($0) }) { continue }
            if parseMenuOptionLine(line) != nil { continue }
            if isNoiseLine(line) || isInputAreaLine(line) || isShellPromptLine(line) { continue }
            if extractInstructionLine(from: line) != nil { continue }
            if lower.contains("would you like")
                || lower.contains("do you want")
                || lower.contains("what should")
                || lower.contains("please confirm")
                || lower.contains("choose")
                || lower.contains("select")
                || lower.contains("pick")
                || lower.contains("continue?")
                || lower.contains("how would you like")
                || lower.contains("which mode")
                || lower.contains("是否")
                || lower.contains("请确认")
                || lower.contains("请选择")
            {
                return line
            }
        }
        return nil
    }

    private static func extractInteractionBody(
        from lines: [String],
        question: String?,
        options: [TaskInteractionOption]
    ) -> String? {
        var bodyLines: [String] = []
        var afterQuestion = question == nil
        let optionLabels = Set(options.map(\.label))

        for line in lines {
            let normalized = normalizeReplyLine(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty { continue }
            if let question, normalized == question {
                afterQuestion = true
                continue
            }
            guard afterQuestion else { continue }
            if parseMenuOptionLine(normalized) != nil { continue }
            if extractInstructionLine(from: normalized) != nil { continue }
            if isNoiseLine(normalized) || isInputAreaLine(normalized) { continue }
            if isShellPromptLine(normalized), !normalized.hasPrefix("$ ") { continue }
            if optionLabels.contains(normalized) { continue }
            bodyLines.append(normalized)
            if bodyLines.count >= 4 { break }
        }

        guard !bodyLines.isEmpty else { return nil }
        return truncate(bodyLines.joined(separator: "\n"), max: 220)
    }

    private static func extractInteractionInstruction(from lines: [String]) -> String? {
        for line in lines.reversed() {
            let normalized = normalizeReplyLine(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if let instruction = extractInstructionLine(from: normalized) {
                return truncate(instruction, max: 120)
            }
        }
        return nil
    }

    private static func detectSelectionMode(from lines: [String]) -> TaskInteractionPrompt.SelectionMode {
        let lower = lines.joined(separator: "\n").lowercased()
        let multipleMarkers = [
            "select one or more",
            "choose one or more",
            "choose multiple",
            "select multiple",
            "space to select",
            "可多选",
            "多选",
        ]
        if multipleMarkers.contains(where: { lower.contains($0) }) {
            return .multiple
        }
        return .single
    }

    private static func isArrowNavigationMenu(_ lines: [String]) -> Bool {
        let lower = lines.joined(separator: "\n").lowercased()
        return lower.contains("arrow keys")
            || lower.contains("方向键")
            || lower.contains("use j/k")
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
        if key.count == 1 || ["esc", "enter", "return", "space", "tab"].contains(key) {
            return key
        }
        return nil
    }

    private static func normalizedOptionLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\s*\\((?:current|selected)\\)\\s*$", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s*\\([^)]+\\)\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func actionForOption(
        label: String,
        number: String,
        shortcut: String?
    ) -> (input: String, submit: Bool, kind: TaskInteractionOption.Kind, actions: [TaskInteractionOption.Action]) {
        let lower = label.lowercased()
        if let shortcut {
            switch shortcut {
            case "esc", "enter", "return", "space", "tab":
                let key = specialKey(for: shortcut)
                return ("", false, key == nil ? .activate : .choice, key.map { [.key($0)] } ?? [.activate])
            default:
                return (shortcut, true, .choice, [.text(shortcut), .key(.enter)])
            }
        }
        if !number.isEmpty {
            return (number, true, .choice, [.text(number), .key(.enter)])
        }
        if lower.hasPrefix("yes") {
            return ("y", true, .choice, [.text("y"), .key(.enter)])
        }
        if lower.hasPrefix("no") {
            return ("n", true, .choice, [.text("n"), .key(.enter)])
        }
        return ("", false, .activate, [.activate])
    }

    private static func buildNavigationOptions(
        from options: [TaskInteractionOption],
        selectedIndex: Int
    ) -> [TaskInteractionOption] {
        guard !options.isEmpty else { return [] }
        return options.enumerated().map { index, option in
            let delta = index - selectedIndex
            var actions: [TaskInteractionOption.Action] = []
            if delta < 0 {
                actions.append(contentsOf: Array(repeating: .key(.arrowUp), count: abs(delta)))
            } else if delta > 0 {
                actions.append(contentsOf: Array(repeating: .key(.arrowDown), count: delta))
            }
            actions.append(.key(.enter))
            return TaskInteractionOption(
                id: option.id,
                label: option.label,
                input: option.input,
                submit: option.submit,
                kind: .choice,
                shortcutHint: option.shortcutHint,
                actions: actions,
                isInitiallySelected: index == selectedIndex
            )
        }
    }

    private static func buildNavigationControlButtons(from lines: [String]) -> [TaskInteractionOption] {
        let lower = lines.joined(separator: "\n").lowercased()
        var buttons: [TaskInteractionOption] = [
            TaskInteractionOption(
                id: "nav-up",
                label: "上一项",
                input: "",
                submit: false,
                kind: .choice,
                shortcutHint: "↑",
                actions: [.key(.arrowUp)]
            ),
            TaskInteractionOption(
                id: "nav-down",
                label: "下一项",
                input: "",
                submit: false,
                kind: .choice,
                shortcutHint: "↓",
                actions: [.key(.arrowDown)]
            ),
            TaskInteractionOption(
                id: "nav-confirm",
                label: "确认",
                input: "",
                submit: true,
                kind: .confirm,
                shortcutHint: "↵",
                actions: [.key(.enter)]
            ),
        ]
        if lower.contains("esc") || lower.contains("cancel") || lower.contains("取消") {
            buttons.append(
                TaskInteractionOption(
                    id: "nav-cancel",
                    label: "取消",
                    input: "",
                    submit: false,
                    kind: .choice,
                    shortcutHint: "ESC",
                    actions: [.key(.escape)]
                )
            )
        }
        buttons.append(
            TaskInteractionOption(
                id: "nav-focus",
                label: "前往终端",
                input: "",
                submit: false,
                kind: .activate,
                actions: [.activate]
            )
        )
        return buttons
    }

    private static func extractInstructionLine(from line: String) -> String? {
        let lower = line.lowercased()
        let markers = [
            "press enter to confirm",
            "press enter to submit",
            "esc to cancel",
            "space to select",
            "use arrow keys",
            "press tab",
            "按回车确认",
            "按 enter 确认",
            "空格选择",
            "方向键",
        ]
        return markers.contains(where: { lower.contains($0) }) ? line : nil
    }

    private static func containsSelectionMarker(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("(current)")
            || lower.contains("(selected)")
            || lower.contains(" current")
            || lower.contains(" selected")
    }

    private static func specialKey(for shortcut: String) -> TaskInteractionOption.SpecialKey? {
        switch shortcut {
        case "enter", "return": return .enter
        case "esc": return .escape
        case "tab": return .tab
        case "space": return .space
        default: return nil
        }
    }

    private static func slug(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func firstCapturedGroup(
        in text: String,
        match: NSTextCheckingResult,
        indexes: [Int]
    ) -> String? {
        for index in indexes {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let r = Range(range, in: text) else { continue }
            let value = String(text[r])
            if !value.isEmpty { return value }
        }
        return nil
    }
}
