# Changelog

All notable changes to **Buling Island**（不灵灵动岛）are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

版本字段与 macOS 包体对应关系：

| 概念 | Info.plist 键 | 约定 |
|------|----------------|------|
| 面向用户的版本号 | `CFBundleShortVersionString` | `MAJOR.MINOR.PATCH`（SemVer） |
| 构建号 | `CFBundleVersion` | 单调递增的整数字符串，每次上架/分发构建递增 |

发布流程中应同时更新本文件、`Sources/Info.plist` 中的上述两项，并保持叙述与真实用户可见变更一致。

## [Unreleased]

开发中的变更请先记在此处；发布新版本时移动到带日期的版本节，并同步更新 `Sources/Info.plist` 中的 `CFBundleShortVersionString` 与 `CFBundleVersion`。

### Fixed

- 任务面板：`extractLatestReply` 会把 Terminal 滚动缓冲里的中断残留行（如 `^C`）当成第二行摘要；已过滤 `^C`/`^D`/`^Z` 及纯控制字符行，并对缓存的回复候选做同一净化。
- Terminal.app 会话捕获：AppleScript 优先读取标签的 `history`（滚动缓冲），再回退 `contents`；此前多优先 `contents`，后台或非前台标签上常拿不到与 iTerm2 相当的尾部文本，导致 Codex/任务识别偏差。
- 终端宿主探测：补充对中文版系统显示名「终端」的识别（与 `com.apple.Terminal` 并列），避免仅靠本地化名称时误判宿主未运行。
- Codex 任务策略：`tailContains` 中宽泛的「rate limit」会命中 Codex 横幅里的「2x rate limits」营销提示并误判为异常；已改为更具体的短语 + `tailRegex`，与无 JSON 时的内置 Codex 策略保持一致。
- Codex 任务策略：移除会把空闲界面脚注 `gpt-x.x medium · n% left ·` 判为 `running` 的无锚点正则；无 `• working` 等真实执行信号时应为 `idle`，避免面板长期「处理中」。
- Codex 任务策略：以输出中出现 `• working` 作为执行中的主要启发式（`running` / `supports`，不再依赖必须带括号的形式）。
- iTerm2 会话捕获：AppleScript 中循环变量勿用 `asess`（易被拆成关键字 `as`）、勿用 `oneWin`/`oneTab`（易被拆成 `one`）；已改为 `eachWin`/`eachTab`/`sessionRef` 等标识符并略作结构加固。
- 终端轮询：各后端对应 App 未启动而导致的失败文案不再与「真脚本错误」混为一谈并刷红条；含 `syntax error` 的仍视为真故障。

### Changed

- 任务识别与菜单栏会话药丸：**统一**由 `TaskStrategies/*.json` 经 `ConfigurableTaskSessionStrategy` 解析；移除与 JSON 并行的 Swift 策略/药丸启发式，避免 Terminal 与 iTerm 分析结论不一致。
- 启动注入：`installProjectStrategies()` 前使 `TaskStrategyFileLoader` 合并缓存失效，便于本机 `~/Library/Application Support/…/TaskStrategies` 覆盖内置 JSON 后立即生效。
- iTerm / iTerm2 会话捕获：AppleScript 与 Terminal.app 对齐，**优先** `history`（滚动缓冲），为空再回退 `contents` / `text`，减轻非前台标签上尾部文本陈旧或截断的问题。
- 任务引擎：不再根据终端「近期有输出变化」(`activeSessionIDs`) 把 `idle` 强行标为 `running`；是否与 Codex 的 `• working` 等策略一致、仅由各 `TaskSessionStrategy` 判定，避免未提交输入也出现「处理中」与绿灯。
- 任务面板：`TaskSessionSnapshot.secondaryText` 由引擎统一编排：未识别到 `›`/`❯` 等用户输入行时仅显示「暂无任务」；执行中/等待输入为「提问 + 最新助手摘要（或「处理中…」）」并跨轮询缓存；成功时第二行固定「任务已完成」。`inactiveTool` 仍为策略原文案。
- 任务面板：未检测到已接入的终端宿主时，在面板正中显示浅灰提示「未检测到活动中的终端」。
- 任务面板：宿主已连通但当前没有可展示的会话时同样显示上述灰色占位，避免出现纯黑空白区域。
- 外部终端捕获（设置开启时）：应用启动后即开始轮询，不再依赖「先切到任务面板才启动监控」。
- 应用面板：应用目录扫描结果变化时递增 `appCatalogRevision` 并用于面板视图标识，首扫完成后更易触发界面刷新。
- 启动时：若未授予辅助权限则触发系统提示；在「启用外部终端捕获」时延迟发起一轮 Apple Event 探测以促发自动化授权；面板出现后即刻检测 Claude CLI。
- Claude CLI：检测路径补充 `~/.local/bin`、`~/bin`，仍支持环境变量 `CLAUDE_CLI_PATH`。

## [1.0.2] - 2026-04-05

### Fixed

- 任务策略：`codex.json` / `claude.json` / `generic.json` 的 `error` 判定去掉在「紧凑尾部」里做子串匹配的泛词（如裸 `failed` / `exception`、中文「失败」「错误」「报错」），避免产品说明里的「错误摘要」「同步失败」「no exception」等正常描述误判为 `异常`；改为更具体的短语、`"error":{` 型 JSON、工具链常见失败句式等 `tailRegex`。
- 测试：`TaskStrategyFileLoader.urlForBundledStrategyJSON` 供用例直接读取包内策略，避免本机 `~/Library/Application Support/BulingIsland/TaskStrategies/*.json` **整文件覆盖**内置合并结果导致测试与仓库行为不一致。

## [1.0.1] - 2026-04-04

### Fixed

- Codex / 任务面板：空闲态仅因底部出现 `› …` 或文案里含 “summarize recent commits” 就被判为 `running`、输入区仍显示 working；已收紧 `codex.json` 的 `running` 规则，需有真实执行信号（如 `• working`）等才为执行中。
- 任务面板：空闲/成功/错误时不再用最新 `›` 行覆盖本轮任务标题；副标题在空闲态若仍保留本轮标题缓存则固定为「任务已完成」，避免把后续跟进提问与最后一段助手输出误当作主任务摘要。

### Changed

- 任务面板：策略命中 `success` 时的固定副标题由「任务执行完毕」改为「任务已完成」，与空闲态（保留本轮标题缓存时）的完成提示一致。

## [1.0.0] - 2026-04-02

### Added

- 刘海区域展开面板：应用启动器（搜索、多种网格模式、文件夹与 Launchpad 式整理）。
- Claude 面板：内嵌终端（SwiftTerm）、Claude Code CLI 工作区与会话状态；可选 iTerm2 等外部终端捕获（实验性）。
- 任务面板、动画与外观设置、收缩态信息位、全屏时隐藏灵动岛、登录项（Launch at Login）等系统集成功能。

<!-- 后续版本在此上方追加 ## [x.y.z] - YYYY-MM-DD -->

[Unreleased]: https://github.com/jukie-xu/buling-island/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/jukie-xu/buling-island/releases/tag/v1.0.0
