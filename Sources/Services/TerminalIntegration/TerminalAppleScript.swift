import Foundation

enum TerminalAppleScriptError: Error {
    case hostUnreachable
    case scriptFailed(String)
}

enum TerminalAppleScript {
    /// 运行 AppleScript，返回标准输出整段文本（已 trim）。
    static func runReturningStdout(_ source: String) -> Result<String, TerminalAppleScriptError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let errorText = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus != 0 {
                if classifyOsascriptAsHostUnreachable(stderr: errorText, stdout: output) {
                    return .failure(.hostUnreachable)
                }
                let msg = errorText.isEmpty ? "osascript 退出码 \(process.terminationStatus)" : errorText
                return .failure(.scriptFailed(msg))
            }
            return .success(output)
        } catch {
            return .failure(.scriptFailed(error.localizedDescription))
        }
    }

    private static func classifyOsascriptAsHostUnreachable(stderr: String, stdout: String) -> Bool {
        let bundle = [stderr, stdout].joined(separator: "\n")
        return messageIndicatesTerminalAppNotRunning(bundle)
    }

    /// 将「目标终端进程未启动 / 未响应 Apple Event」与真脚本错误区分，供轮询合并时消抖。
    static func messageIndicatesTerminalAppNotRunning(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("syntax error") { return false }
        if text.contains("__NOT_RUNNING__") { return true }
        // AppleScript / Apple Event 常见：应用未运行时返回 -600
        if lower.contains("(-600)") || lower.contains(" error -600") { return true }
        if lower.contains("application isn't running")
            || lower.contains("application is not running")
            || lower.contains("isn't running")
            || lower.contains("is not running")
        {
            return true
        }
        if text.contains("未能找到")
            || text.contains("没有运行")
            || text.contains("找不到应用程序")
            || text.contains("未运行")
        {
            return true
        }
        return false
    }

    /// 解析由 `fieldSep` / `recordSep` 拼接的快照表。
    static func parseSnapshotTable(_ output: String, dropSentinel: String? = "__NOT_RUNNING__") -> [TerminalSessionRow]? {
        if let sentinel = dropSentinel, output == sentinel {
            return nil
        }
        if output.isEmpty {
            return []
        }
        let recordSeparator = Character("\u{001E}")
        let fieldSeparator = String(Character("\u{001F}"))
        return output
            .split(separator: recordSeparator)
            .map { String($0) }
            .compactMap { line -> TerminalSessionRow? in
                let parts = line.components(separatedBy: fieldSeparator)
                guard parts.count >= 5,
                      let kind = TerminalKind(rawValue: parts[1])
                else { return nil }
                let tail = parts.dropFirst(4).joined(separator: "||")
                return TerminalSessionRow(
                    nativeSessionId: parts[0],
                    terminalKind: kind,
                    title: parts[2],
                    tty: parts[3],
                    tail: tail
                )
            }
    }
}
