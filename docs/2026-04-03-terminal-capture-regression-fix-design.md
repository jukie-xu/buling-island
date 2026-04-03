# Terminal 会话捕获回归修复设计

## 背景与问题

经过最近几轮终端相关改造后，出现了 `Terminal.app` 存活但会话列表为空、任务面板无法显示现有会话的问题。

排查结果：

- 当前各终端 backend 的 `fetchSessions()` 先依赖 `System Events` 判断进程是否存在。
- 这会让抓取链路额外依赖一层 Accessibility / Apple Event 环境。
- 当 `System Events` 异常、不可达或授权状态不稳定时，会话抓取会在真正访问 `Terminal/iTerm` 之前直接失败。
- 由于宿主运行态本身已经由 `RunningApplicationTerminalHostProbe` 基于 `NSWorkspace` 负责，这层 `System Events` 预检属于重复且脆弱的前置条件。

## 目标

- 恢复 `Terminal.app / iTerm / iTerm2` 的会话抓取稳定性。
- 移除抓取链路对 `System Events` 的硬前置依赖。
- 保留现有宿主运行态判断与错误分类逻辑。

## 方案

### 1. `fetchSessions()` 去掉 `System Events` 预检查

对以下 backend：

- `AppleTerminalSessionCaptureBackend`
- `ITerm2SessionCaptureBackend`
- `LegacyITermSessionCaptureBackend`

改为：

- 直接执行 `tell application "<terminal>"` 枚举窗口/标签/会话。
- 若目标终端未运行，由 host probe 在 `mergeBackendFetches()` 层提前短路。
- 若极端情况下运行态探针与真实状态不一致，则由 `TerminalAppleScript.messageIndicatesTerminalAppNotRunning(...)` 把 AppleScript 错误归类为 `hostNotRunning`。

### 2. 保持激活/输入逻辑不变

- `activate` / `sendInput` 仍可保留 `System Events` 或现有激活方式，因为这两者属于“用户触发交互”，不是持续轮询主路径。
- 本次修复只收敛回归源头：会话捕获。

## 风险

- 若某些终端在未运行时被直接 `tell application` 意外唤起，需要依赖 host probe 避免进入该分支。

## 验证

1. `swift test` 全量通过。
2. 本机开启 `Terminal.app` 且有窗口标签时，任务面板能恢复显示会话数量。
3. 执行 `./install-local.sh` 更新本机 app。
