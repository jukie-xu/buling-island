import Foundation

/// 管理本机 Claude Code CLI 的安装检测与会话元数据。
@MainActor
final class ClaudeCLIService: ObservableObject {

    @Published var isRunning: Bool = false
    @Published var lastError: String?

    /// 解析出的 Claude CLI 可执行路径及安装状态。
    enum InstallStatus: Equatable {
        case unknown
        case checking
        case installed(path: String)
        case missing(reason: String)
    }

    @Published private(set) var installStatus: InstallStatus = .unknown

    /// 当前选定的项目目录，作为 CLI 运行时的工作目录。
    @Published var projectDirectory: URL?

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
            let fm = FileManager.default
            let explicit = env["CLAUDE_CLI_PATH"]

            // GUI App 进程的 PATH 常常缺少 Homebrew 路径，优先做一轮常见位置硬检测。
            let pathCandidates: [String] = [
                explicit,
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                "/usr/bin/claude",
            ].compactMap { $0 }

            func publish(_ status: InstallStatus) {
                Task { @MainActor in
                    self.installStatus = status
                }
            }

            for candidate in pathCandidates {
                if fm.isExecutableFile(atPath: candidate) {
                    publish(.installed(path: candidate))
                    return
                }
            }

            // 退而求其次，通过 `which claude` 查找。
            let whichProc = Process()
            whichProc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            whichProc.arguments = ["which", "claude"]
            var whichEnv = env
            let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            if let current = whichEnv["PATH"], !current.isEmpty {
                whichEnv["PATH"] = "\(current):\(fallbackPath)"
            } else {
                whichEnv["PATH"] = fallbackPath
            }
            whichProc.environment = whichEnv
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

    /// 当前解析出的 Claude CLI 可执行路径（若已安装）。
    var resolvedExecutablePath: String? {
        if case let .installed(path) = installStatus {
            return path
        }
        return nil
    }
}

