import Foundation

/// 通过本机 Claude Code CLI 运行命令，并将输出流式推送到 UI。
@MainActor
final class ClaudeCLIService: ObservableObject {

    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var lastError: String?

    /// 最近一次尝试的命令描述（便于 UI 提示）。
    @Published var lastCommandDescription: String?

    /// 解析出的 Claude CLI 可执行路径及安装状态。
    enum InstallStatus {
        case unknown
        case checking
        case installed(path: String)
        case missing(reason: String)
    }

    @Published private(set) var installStatus: InstallStatus = .unknown

    /// 当前选定的项目目录，作为 CLI 运行时的工作目录。
    @Published var projectDirectory: URL?

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var inputPipe: Pipe?

    // MARK: - Install detection

    func ensureDetected() {
        switch installStatus {
        case .unknown:
            detectInstallStatus()
        case .checking, .installed, .missing:
            return
        }
    }

    private func detectInstallStatus() {
        installStatus = .checking

        DispatchQueue.global(qos: .userInitiated).async {
            let env = ProcessInfo.processInfo.environment
            let candidate = env["CLAUDE_CLI_PATH"] ?? "/usr/local/bin/claude"
            let fm = FileManager.default

            func publish(_ status: InstallStatus) {
                Task { @MainActor in
                    self.installStatus = status
                }
            }

            if fm.isExecutableFile(atPath: candidate) {
                publish(.installed(path: candidate))
                return
            }

            // 退而求其次，通过 `which claude` 查找。
            let whichProc = Process()
            whichProc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            whichProc.arguments = ["which", "claude"]
            let pipe = Pipe()
            whichProc.standardOutput = pipe

            do {
                try whichProc.run()
                whichProc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let raw = String(data: data, encoding: .utf8) ?? ""
                let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if whichProc.terminationStatus == 0, !path.isEmpty, fm.isExecutableFile(atPath: path) {
                    publish(.installed(path: path))
                } else {
                    publish(.missing(reason: "未检测到 Claude CLI。请先安装 claude 命令行工具，并确保可在终端执行 `claude`。"))
                }
            } catch {
                publish(.missing(reason: "检测 Claude CLI 失败：\(error.localizedDescription)"))
            }
        }
    }

    /// 在选定目录中启动 Claude Code CLI（交互会话）。
    func runInteractiveSession(in workingDirectory: URL) {
        if isRunning {
            // 已在运行时忽略重复启动，避免进程叠加。
            return
        }

        guard case let .installed(cliPath) = installStatus else {
            lastError = "尚未检测到 Claude CLI，请确认已安装并可在终端执行 `claude`。"
            return
        }

        output = ""
        lastError = nil
        lastCommandDescription = "cd \(workingDirectory.path) && claude"

        let proc = Process()
        // Use `script` to allocate a pseudo-TTY so Claude can render interactive UI.
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        proc.arguments = ["-q", "/dev/null", cliPath]

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = inPipe

        proc.currentDirectoryURL = workingDirectory

        outputPipe = outPipe
        errorPipe = errPipe
        inputPipe = inPipe

        isRunning = true

        let handleStdout = outPipe.fileHandleForReading
        handleStdout.readabilityHandler = { [weak self] h in
            guard let self else { return }
            let data = h.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            Task { @MainActor in
                self.output.append(chunk)
            }
        }

        let handleStderr = errPipe.fileHandleForReading
        handleStderr.readabilityHandler = { [weak self] h in
            guard let self else { return }
            let data = h.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            Task { @MainActor in
                self.output.append(chunk)
            }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = false
                self.cleanupPipes()
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            isRunning = false
            lastError = "启动 Claude CLI 失败：\(error.localizedDescription)\n请确认已安装，并在环境变量 CLAUDE_CLI_PATH 或 `/usr/local/bin/claude` 中可用。"
            cleanupPipes()
        }
    }

    func cancel() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        process = nil
        isRunning = false
        cleanupPipes()
    }

    /// 向当前 Claude 会话写入一行输入（自动附加换行）。
    func sendLine(_ line: String) {
        guard isRunning, let input = inputPipe else { return }
        let text = line + "\n"
        guard let data = text.data(using: .utf8) else { return }
        input.fileHandleForWriting.write(data)
    }

    private func cleanupPipes() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe = nil
        inputPipe = nil
    }
}

