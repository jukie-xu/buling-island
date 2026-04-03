# BulingIsland 设计文档：Codex 占位输入提示抑制

## 背景与目标

当前在 Codex 运行中会出现这样一种场景：

- 历史上真正提交过的用户问题：`提交并推送`
- 当前输入框中的占位建议：`Summarize recent commits`
- 同时存在运行状态：`• Working (21s • esc to interrupt)`

现有逻辑会直接取“最后一个 `› ...` 行”作为用户问题，导致：

- 第一行被错误展示为 `Summarize recent commits`
- 正确结果应为：
  - 第一行：`提交并推送`
  - 第二行：`Working (21s • esc to interrupt)`

目标：

- 识别 Codex 当前输入框里的占位建议行
- 不把占位建议当成真实用户问题
- 优先展示真正已提交、且与当前运行状态相关联的用户问题

## 范围

包含：

- 修正 `extractLatestUserPrompt`
- 新增针对该场景的严格测试

不包含：

- 修改 Claude 逻辑
- 修改 pill 交互展示结构

## 方案设计

### 1. 识别 Codex placeholder prompt

判定为 placeholder 的条件：

- 行本身是用户输入前缀 `› ...`
- 其后紧跟的是 Codex 底部模型脚注，如：
  - `gpt-5.4 medium · 100% left · ...`
- 且其前一个有效行是运行状态，如：
  - `• Working (...)`

这种情况下，这条 `› ...` 不是用户刚提交的任务，而是当前输入框里的建议文案，应跳过。

### 2. 继续向前回溯真实用户问题

当最新 prompt 被判定为 placeholder 时：

- 继续向前寻找上一条真实 prompt
- 用上一条真实 prompt 作为任务面板第一行

## 变更清单

- `docs/2026-04-03-codex-placeholder-prompt-suppression-design.md`
- `Sources/Services/TaskEngine/TaskSessionTextToolkit.swift`
- `Tests/BulingIslandTests/TaskSessionTextToolkitTests.swift`
- `Tests/BulingIslandTests/TaskSessionPanelTextTests.swift`

## 验证方案

- `swift test`
- 运行中场景下：
  - 第一行应展示真实历史问题
  - 第二行应展示 `Working (...)`

## 风险与回滚方案

风险：

- 误把真实新输入当成 placeholder

缓解：

- 仅在“后跟底部脚注 + 前有 running 状态”时生效

回滚：

- 仅回滚 placeholder prompt 判定逻辑与相关测试
