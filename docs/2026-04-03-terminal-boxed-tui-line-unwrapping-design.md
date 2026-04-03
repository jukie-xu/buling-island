# BulingIsland 设计文档：Terminal 框线 TUI 文本解包修复

## 背景与目标

通过直接抓取 `Terminal.app` 当前会话原始文本，已经确认：

- `contents` 为空
- `history` 中实际包含完整的 Codex 文本
- 但 `OpenAI Codex` / `model:` / `directory:` 这些信息位于框线 TUI 中，格式为：
  - `│ >_ OpenAI Codex (...) │`
  - `│ model: ... │`

当前清洗逻辑会把包含 `│/╭/╰/─` 的整行直接视为输入区或边框噪声删除，导致：

- Terminal 明明抓到了 Codex 原文
- 但进入策略层前就被自己删掉
- 最终只能落到 `Generic TUI`

目标：

- 保留框线 TUI 行中的正文
- 仅删除纯边框线
- 让 Terminal 中的 Codex 框内文本与 iTerm 一样进入统一解析链路

## 范围

包含：

- 对 `│ ... │` 这类行做正文解包
- 保留 `OpenAI Codex` / `model:` / `directory:` 等关键信息
- 纯边框行继续丢弃

不包含：

- 修改策略 JSON
- 修改 UI 渲染逻辑

## 方案设计

### 1. 增加框线正文解包

在标准化文本阶段，对每一行执行：

- 若是 `│ ... │` / `┃ ... ┃` 这类框线包裹行
  - 提取中间正文
  - 保留正文参与后续清洗
- 若是纯边框线（如 `╭────╮` / `╰────╯` / `────`）
  - 丢弃

### 2. 保持统一后处理

解包后的文本继续走现有统一链路：

- `standardizedTerminalText`
- `normalizedOutputLines`
- `TaskSessionStrategy`
- `TaskEngine`
- `pill`

## 变更清单

- `docs/2026-04-03-terminal-boxed-tui-line-unwrapping-design.md`
- `Sources/Services/TaskEngine/TaskSessionTextToolkit.swift`
- `Tests/BulingIslandTests/TaskSessionTextToolkitTests.swift`

## 验证方案

- `swift test`
- 复测 Terminal 中 Codex 会话不再落到 `Generic TUI`

## 风险与回滚方案

风险：

- 个别真正的装饰行可能被保留下来

缓解：

- 仅对有明确正文的框线包裹行解包
- 纯边框线仍然剔除

回滚：

- 仅回滚框线解包逻辑
