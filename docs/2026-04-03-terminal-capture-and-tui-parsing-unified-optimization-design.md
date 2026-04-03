# 终端捕获与 TUI 解析统一优化设计（iTerm2/iTerm/Terminal/Tabby）

## 背景与目标

当前任务面板在外部终端会话识别上存在以下问题：

1. iTerm2 场景下，`Codex` 的 GUI 面板内容未被稳定识别，反而展示了 shell 历史命令（如 `clear`）。
2. Tabby 会话有时无法被稳定识别或抓到有效 tail 输出，导致任务条缺失。
3. Claude TUI 在 `Interrupted · What should Claude do instead?` 场景下，任务副文案未正确显示 Claude 返回内容，误展示状态栏信息（如 `🤖 Opus ...`）。
4. 现有清洗规则偏向单一样例，对不同终端（iTerm2/iTerm/Terminal/Tabby）的兼容性不足。

目标：

- 建立统一、可扩展的“捕获 -> 清洗 -> 任务提取”链路。
- 一次性修复 iTerm2、Tabby、Claude 中断回复展示问题，并保证对系统 Terminal 与 iTerm 兼容。
- 用新增样例和单测固化规则，避免回归。

## 范围

包含：

- `TerminalIntegration` 会话捕获后端优化（iTerm2 / iTerm / Tabby）。
- `TaskSessionTextToolkit` 文本清洗与“最后输入/最后回复”抽取优化。
- `TaskStrategies/claude.json` 规则补充（结合 `rela/claude-*.txt`）。
- 回归测试补充（Toolkit / Strategy / Capture）。

不包含：

- 新增全新终端产品接入（如 Warp/Alacritty）。
- UI 样式重构（仅修复数据正确性）。

## 方案设计

### 1) 采集层：终端后端抓取策略统一增强

#### iTerm2 / iTerm（AppleScript）

- 问题：当前优先读取 `contents`，在 TUI alt-screen 场景下，可能回落到 shell 缓冲，导致抓到历史命令而非当前 UI。
- 方案：
  - 调整读取优先级为：优先 `text of session`（当前可视区）-> 失败时回退 `contents`（滚动缓冲）。
  - 保留尾窗截断逻辑（12000 字符），避免性能退化。

#### Tabby（System Events / AX）

- 问题：当前只扫描窗口浅层 `AXTextArea`，易漏掉深层文本节点；`session id` 退化为窗口名时不稳定。
- 方案：
  - 改为遍历 `entire contents of window`，优先从 `AXTextArea` 提取完整文本，失败时回退 `AXStaticText` 聚合。
  - 会话 id 策略改为“优先窗口 `id`，其次窗口名，最后 `tabby-window-<index>`”，提升稳定性与可追踪性。
  - 保留现有 activate/sendInput 行为，避免引入额外自动化权限风险。

### 2) 清洗层：统一行过滤规则增强

在 `TaskSessionTextToolkit` 增加更强的行级过滤与候选优先级：

- 新增 shell 提示行过滤（如 `user@host dir % cmd`、`$ cmd`、`# cmd`），避免将终端命令行误识别为回复。
- 新增 TUI 底部状态栏噪声过滤（如 Claude `🤖 Opus ... | ⚡ ...`、`MCP server failed · /mcp`）。
- 保留 `⎿ ...` 结果行，不作为噪声。
- 回复提取优先级：
  1. 优先选择 Claude/Codex 结果行（如 `⎿ ...`）。
  2. 其次选择非输入、非噪声、非 shell 行的最后一行。
  3. 若为空则回退“暂无可展示输出”。

### 3) 策略层：Claude 规则补强（基于 `rela` 样例）

更新 `Sources/Configs/TaskStrategies/claude.json`：

- `waitingInput` 增加 `interrupted`、`what should claude do instead` 等标记。
- `running` 增加 `sublimating` 等真实进度标记。
- 保证 `Interrupted` 优先归类为 `waitingInput`，并通过 `promptAndReply` 展示“最后提问 + Claude响应行”。

### 4) 全终端统一原则

对当前支持终端（iTerm2 / iTerm / Terminal / Tabby）统一遵循：

- 捕获层只做“尽量真实提取可见内容”，不在后端写死业务文案。
- 业务态（running/waiting/error/success）统一由 TaskStrategy 配置与 TextToolkit 判定。
- 特定终端差异（可见区 API、AX 层级）在后端吸收，不影响任务面板逻辑。

## 变更清单

- `Sources/Services/TerminalIntegration/ITerm2SessionCaptureBackend.swift`
  - 调整 `bodyText` 读取顺序：`text` 优先，`contents` 回退。
- `Sources/Services/TerminalIntegration/LegacyITermSessionCaptureBackend.swift`
  - 同步 iTerm2 读取顺序策略，增强兼容。
- `Sources/Services/TerminalIntegration/TabbySessionCaptureBackend.swift`
  - 深层 AX 文本抓取与 session id 回退策略增强。
- `Sources/Services/TaskEngine/TaskSessionTextToolkit.swift`
  - 新增 shell 行识别与状态栏噪声识别，优化 reply 抽取逻辑。
- `Sources/Configs/TaskStrategies/claude.json`
  - 基于 `rela/claude-*.txt` 增补 waiting/running 标记规则。
- `Tests/BulingIslandTests/TaskSessionTextToolkitTests.swift`
  - 新增 Claude interrupted 场景与 shell 噪声过滤用例。
- `Tests/BulingIslandTests/TaskStrategyFileConfigTests.swift`
  - 增加 claude 内置规则对 interrupted/sublimating 的断言。

## 验证方案

1. 单元测试
   - 执行 `swift test`，确保新增/原有测试全部通过。

2. 样例回放验证（文本级）
   - 使用 `rela/claude-undo-Interrupted.txt`，断言副文案第二行提取 `Interrupted · What should Claude do instead?`。
   - 使用 `rela/claude-working.txt` / `rela/claude-error.txt`，断言不会将 `🤖 Opus...` 状态栏当作回复主文。

3. 终端后端行为检查
   - iTerm2/iTerm 后端脚本编译通过（无语法错误）。
   - Tabby 后端在无 `AXTextArea` 时可回退 `AXStaticText`，确保任务条不空白。

4. 本机部署
   - 代码变更后执行 `./install-local.sh`，完成本机 app 更新。

## 风险与回滚方案

风险：

- Tabby `entire contents` 在个别机器可能较慢。
- shell 提示行正则若过宽，可能误过滤合法输出。

缓解：

- 仅在 `TaskSessionTextToolkit` 做“高置信噪声”过滤，保守匹配。
- Tabby 保留旧逻辑的回退路径（找不到文本时返回空 tail，不抛错）。

回滚：

- 若出现误判，优先回滚 `TaskSessionTextToolkit` 的新增过滤函数与 claude.json 新标记。
- 后端问题可分别回滚对应终端 backend 文件，不影响其他终端。
