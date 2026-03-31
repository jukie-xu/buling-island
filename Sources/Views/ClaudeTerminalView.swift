import SwiftUI
import AppKit
import SwiftTerm

struct ClaudeTerminalView: NSViewRepresentable {
    let cliPath: String
    let workingDirectory: URL
    @Binding var isRunning: Bool
    @Binding var lastError: String?
    @Binding var interactionHint: String?
    @Binding var latestStatusText: String?
    @Binding var latestStatusTone: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ClaudeLocalTerminalView {
        let view = ClaudeLocalTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        // Claude Code inspired palette (warmer slate)
        view.nativeBackgroundColor = NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.10, alpha: 1) // #171419
        view.nativeForegroundColor = NSColor(calibratedRed: 0.95, green: 0.92, blue: 0.88, alpha: 1) // warm light
        view.caretColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.52, alpha: 1) // #FFDB85
        view.caretTextColor = NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.10, alpha: 1)
        // Keep caret visible even when focus briefly hops to toolbar buttons.
        view.caretViewTracksFocus = false
        view.applyClaudeCodePalette()
        view.onPlainText = { [weak coordinator = context.coordinator] plain in
            coordinator?.inspectPotentialInteraction(plainText: plain)
        }
        context.coordinator.attach(view: view)
        context.coordinator.sync(
            cliPath: cliPath,
            workingDirectory: workingDirectory,
            desiredRunning: isRunning
        )
        return view
    }

    func updateNSView(_ nsView: ClaudeLocalTerminalView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(view: nsView)
        context.coordinator.sync(
            cliPath: cliPath,
            workingDirectory: workingDirectory,
            desiredRunning: isRunning
        )
        if isRunning {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.hasFocus = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                nsView.window?.makeFirstResponder(nsView)
                nsView.hasFocus = true
            }
        }
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var parent: ClaudeTerminalView
        private weak var terminalView: ClaudeLocalTerminalView?
        private var lastLaunchKey: String?
        private var recentlySeenPlainText = ""
        private var stickyCriticalUntil: Date = .distantPast
        private var stickyCriticalText: String?
        private var stickyCriticalTone: String = "info"

        init(parent: ClaudeTerminalView) {
            self.parent = parent
        }

        func attach(view: ClaudeLocalTerminalView) {
            terminalView = view
        }

        func sync(cliPath: String, workingDirectory: URL, desiredRunning: Bool) {
            guard let terminalView else { return }
            let launchKey = "\(cliPath)|\(workingDirectory.path)"

            if !desiredRunning {
                terminateIfRunning()
                return
            }

            // Start only when needed; restart if executable/dir changed.
            if lastLaunchKey != launchKey {
                terminateIfRunning()
                doStart(cliPath: cliPath, workingDirectory: workingDirectory, terminalView: terminalView)
                return
            }

            // If user asked running=true but process died, start again.
            if !terminalView.isProcessRunning {
                doStart(cliPath: cliPath, workingDirectory: workingDirectory, terminalView: terminalView)
            }
        }

        private func doStart(cliPath: String, workingDirectory: URL, terminalView: ClaudeLocalTerminalView) {
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = env["TERM"] ?? "xterm-256color"
            env["COLORTERM"] = env["COLORTERM"] ?? "truecolor"
            env["CLICOLOR"] = "1"
            env["CLICOLOR_FORCE"] = "1"
            env.removeValue(forKey: "NO_COLOR")

            do {
                terminalView.applyClaudeCodePalette()
                try terminalView.startClaude(
                    executable: cliPath,
                    environment: env,
                    workingDirectory: workingDirectory.path
                )
                // SwiftTerm/CLI 在切到 alt-screen 后可能覆盖初始渲染状态，延迟再刷一轮主题确保生效。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    terminalView.applyClaudeCodePalette()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    terminalView.applyClaudeCodePalette()
                }
                lastLaunchKey = "\(cliPath)|\(workingDirectory.path)"
                recentlySeenPlainText = ""
                Task { @MainActor in
                    self.parent.lastError = nil
                    self.parent.interactionHint = nil
                    self.parent.latestStatusText = nil
                    self.parent.latestStatusTone = "info"
                    self.parent.isRunning = true
                }
                DispatchQueue.main.async {
                    terminalView.window?.makeFirstResponder(terminalView)
                    terminalView.hasFocus = true
                }
            } catch {
                Task { @MainActor in
                    self.parent.lastError = "启动 Claude TUI 失败：\(error.localizedDescription)"
                    self.parent.latestStatusText = "Claude 启动失败"
                    self.parent.latestStatusTone = "error"
                    self.parent.isRunning = false
                }
            }
        }

        private func terminateIfRunning() {
            guard let terminalView else { return }
            if terminalView.isProcessRunning {
                terminalView.terminate()
            }
            Task { @MainActor in
                self.parent.isRunning = false
                self.parent.interactionHint = nil
                self.parent.latestStatusText = nil
                self.parent.latestStatusTone = "info"
            }
        }

        // MARK: - Interaction hint detection
        func inspectPotentialInteraction(plainText: String) {
            guard !plainText.isEmpty else { return }
            recentlySeenPlainText += plainText
            if recentlySeenPlainText.count > 6000 {
                recentlySeenPlainText.removeFirst(recentlySeenPlainText.count - 6000)
            }
            if let line = latestMeaningfulLine(in: recentlySeenPlainText) {
                let analysis = analyzeStatus(from: line, allText: recentlySeenPlainText)
                Task { @MainActor in
                    if Date() < self.stickyCriticalUntil,
                       let sticky = self.stickyCriticalText,
                       self.stickyCriticalTone == "error" {
                        self.parent.latestStatusText = sticky
                        self.parent.latestStatusTone = self.stickyCriticalTone
                    } else {
                        self.parent.latestStatusText = analysis.text
                        self.parent.latestStatusTone = analysis.tone
                    }
                }
            }
            let lower = recentlySeenPlainText.lowercased()
            let markers = [
                "allow", "approve", "permission", "confirm", "continue", "y/n",
                "[y/n]", "(y/n)", "select", "choose", "pick", "enter to confirm",
                "需要确认", "请确认", "是否允许", "请选择", "继续吗"
            ]
            if markers.contains(where: { lower.contains($0) }) {
                Task { @MainActor in
                    self.parent.interactionHint = "检测到 Claude 可能在等待确认/选择，请直接在终端中输入。"
                }
            } else {
                Task { @MainActor in
                    self.parent.interactionHint = nil
                }
            }
        }

        private func analyzeStatus(from line: String, allText: String) -> (text: String, tone: String) {
            let lowerLine = line.lowercased()
            let lowerAll = allText.lowercased()
            let recentContext = recentJoinedLines(from: allText, maxLines: 18).lowercased()

            if recentContext.contains("validate certification failed")
                || recentContext.contains("auth_error")
                || recentContext.contains("invalid_request_error")
                || recentContext.contains("\"code\":\"auth_error\"")
                || recentContext.contains("401 ")
                || recentContext.contains(" 401")
                || recentContext.contains("unauthorized")
                || recentContext.contains("certificate")
                || lowerLine.contains("error") || lowerLine.contains("failed") || lowerLine.contains("exception")
                || lowerLine.contains("denied") || lowerLine.contains("traceback")
                || lowerLine.contains("报错") || lowerLine.contains("失败") || lowerLine.contains("错误") {
                let text: String
                if recentContext.contains("validate certification failed") || recentContext.contains("certificate") {
                    text = "错误: 证书校验失败"
                } else if recentContext.contains("auth_error") || recentContext.contains("unauthorized") || recentContext.contains("401") {
                    text = "错误: 认证失败（401）"
                } else {
                    text = "错误: \(truncate(line, max: 24))"
                }
                stickyCriticalUntil = Date().addingTimeInterval(8)
                stickyCriticalText = text
                stickyCriticalTone = "error"
                return (text, "error")
            }

            if lowerAll.contains("plan") && (lowerAll.contains("approve") || lowerAll.contains("confirm")
                || lowerAll.contains("确认") || lowerAll.contains("继续吗")) {
                return ("计划待确认", "warn")
            }

            if lowerAll.contains("allow") || lowerAll.contains("approve") || lowerAll.contains("permission")
                || lowerAll.contains("[y/n]") || lowerAll.contains("(y/n)")
                || lowerAll.contains("请选择") || lowerAll.contains("请确认") || lowerAll.contains("是否允许") {
                return ("等待你的确认", "warn")
            }

            if lowerLine.contains("done") || lowerLine.contains("completed") || lowerLine.contains("finished")
                || lowerLine.contains("success") || lowerLine.contains("已完成") || lowerLine.contains("完成") || lowerLine.contains("成功") {
                return ("已完成: \(truncate(line, max: 22))", "success")
            }

            if lowerLine.contains("running") || lowerLine.contains("executing") || lowerLine.contains("processing")
                || lowerLine.contains("thinking") || lowerLine.contains("analyzing")
                || lowerLine.contains("执行") || lowerLine.contains("处理中") || lowerLine.contains("思考中") {
                return ("执行中: \(truncate(line, max: 22))", "busy")
            }

            return (truncate(line, max: 28), "info")
        }

        private func recentJoinedLines(from text: String, maxLines: Int) -> String {
            let lines = text
                .split(whereSeparator: \.isNewline)
                .map { String($0) }
            guard !lines.isEmpty else { return "" }
            let start = max(0, lines.count - maxLines)
            return lines[start...].joined(separator: "\n")
        }

        private func truncate(_ text: String, max: Int) -> String {
            if text.count <= max { return text }
            return String(text.prefix(max)) + "…"
        }

        private func latestMeaningfulLine(in text: String) -> String? {
            let lines = text
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for line in lines.reversed() {
                if line.hasPrefix(">") || line.hasPrefix("$") || line == ":" {
                    continue
                }
                let compact = line
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                if compact.count <= 2 { continue }
                if compact.hasPrefix("│") || compact.hasPrefix("╭") || compact.hasPrefix("╰") {
                    continue
                }
                if compact.count > 28 {
                    let prefix = compact.prefix(28)
                    return String(prefix) + "…"
                }
                return compact
            }
            return nil
        }

        // MARK: - LocalProcessTerminalViewDelegate
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                self.parent.isRunning = false
                self.parent.latestStatusText = nil
                self.parent.latestStatusTone = "info"
                if let code = exitCode, code != 0 {
                    self.parent.lastError = "Claude TUI 已退出（代码 \(code)）"
                    self.parent.latestStatusText = "Claude 异常退出（\(code)）"
                    self.parent.latestStatusTone = "error"
                }
            }
        }
    }
}

final class ClaudeLocalTerminalView: LocalProcessTerminalView {
    var onPlainText: ((String) -> Void)?
    private var focusKeeper: Timer?

    var isProcessRunning: Bool {
        process.running
    }

    func startClaude(executable: String, environment: [String: String], workingDirectory: String) throws {
        startProcess(
            executable: executable,
            args: [],
            environment: environment.map { "\($0.key)=\($0.value)" },
            execName: nil,
            currentDirectory: workingDirectory
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        startFocusKeeper()
    }

    deinit {
        focusKeeper?.invalidate()
        focusKeeper = nil
    }

    func applyClaudeCodePalette() {
        let ansi: [(UInt8, UInt8, UInt8)] = [
            (0x1a, 0x17, 0x1f), // black
            (0xf3, 0x8b, 0xa8), // red
            (0xa6, 0xe3, 0xa1), // green
            (0xf9, 0xe2, 0xaf), // yellow
            (0x89, 0xb4, 0xfa), // blue
            (0xf5, 0xc2, 0xe7), // magenta
            (0x94, 0xe2, 0xd5), // cyan
            (0xe9, 0xe5, 0xdc), // white
            (0x57, 0x52, 0x6b), // bright black
            (0xff, 0xb4, 0xc4), // bright red
            (0xc0, 0xf0, 0xb7), // bright green
            (0xff, 0xed, 0xbf), // bright yellow
            (0xad, 0xcc, 0xff), // bright blue
            (0xff, 0xd5, 0xf2), // bright magenta
            (0xb0, 0xed, 0xe3), // bright cyan
            (0xff, 0xf8, 0xec), // bright white
        ]
        let palette = ansi.map { rgb in
            Color(
                red: UInt16(rgb.0) * 257,
                green: UInt16(rgb.1) * 257,
                blue: UInt16(rgb.2) * 257
            )
        }
        terminal.installPalette(colors: palette)
        // Force redraw so new palette takes effect immediately.
        needsDisplay = true
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        if let chunk = String(bytes: slice, encoding: .utf8), !chunk.isEmpty {
            onPlainText?(stripANSI(from: chunk))
        }
        super.dataReceived(slice: slice)
    }

    private func startFocusKeeper() {
        guard focusKeeper == nil else { return }
        focusKeeper = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isProcessRunning else { return }
            if self.window?.firstResponder !== self {
                self.window?.makeFirstResponder(self)
                self.hasFocus = true
            }
        }
    }

    private func stripANSI(from text: String) -> String {
        var result = ""
        var inEscape = false
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if inEscape {
                if (v >= 0x40 && v <= 0x7e) || v == 0x07 {
                    inEscape = false
                }
                continue
            }
            if v == 0x1b {
                inEscape = true
                continue
            }
            if v >= 0x20 || v == 0x0a || v == 0x0d || v == 0x09 {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
