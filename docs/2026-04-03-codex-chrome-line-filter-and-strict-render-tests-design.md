# BulingIsland 设计文档：Codex chrome 文案过滤与严格渲染一致性测试

## 背景与目标

当前 `Terminal` 会话已经能识别为 `Codex`，但副文案错误地展示了：

- `directory: ~/git/buling-island`

这说明：

- Codex banner 进入策略层是对的
- 但任务面板在抽取“最新回复”时，把 banner/chrome 行误当成了回复内容

同时，现有跨终端测试仍然不够严格，之前只验证：

- 命中 `codex`
- 不是 `Generic TUI`

这不足以拦住“同样识别成 Codex，但副文案错误”的问题。

目标：

- 把 `OpenAI Codex`、`model:`、`directory:`、Codex Tip 等都视为 chrome，不再作为回复文案
- 将 Terminal / iTerm 等价测试收紧到精确断言 `secondaryText`

## 范围

包含：

- 增强 Codex chrome 过滤
- 强化测试断言
- 明确当前交互按钮能力边界

不包含：

- 本次不扩展 pill 区域为交互按钮承载区

## 方案设计

### 1. Codex chrome 行过滤

在 `TaskSessionTextToolkit` 中，把以下内容视为辅助 chrome：

- `>_ OpenAI Codex (...)`
- `model: ...`
- `directory: ...`
- `Tip: Run codex app ...`
- `Tip: New Try the Codex App ...`
- `gpt-x.x ... left · ...`

这些行可以用于策略识别，但不能作为任务面板回复文案。

### 2. 严格一致性测试

将 Terminal / iTerm 等价样例测试改为精确断言：

- `strategyID`
- `lifecycle`
- `renderTone`
- `secondaryText`

并新增同 prompt 的 Terminal / iTerm 样例，要求最终 `secondaryText` 完全一致。

## 当前交互按钮能力确认

当前能力：

- 已支持把 Claude / Codex 的等待交互解析成结构化问题和选项按钮
- 已在展开后的任务面板中渲染按钮，并可触发 `sendInput/sendActions`

当前未完成：

- pill 扩展区域动态承载这些交互按钮

该能力需要单独设计与实现，不在本次修复范围内。

## 变更清单

- `docs/2026-04-03-codex-chrome-line-filter-and-strict-render-tests-design.md`
- `Sources/Services/TaskEngine/TaskSessionTextToolkit.swift`
- `Tests/BulingIslandTests/RelaFixtureConsistencyTests.swift`
- `Tests/BulingIslandTests/TaskSessionPanelTextTests.swift`

## 验证方案

- `swift test`
- `./install-local.sh`
- 复测 Terminal / iTerm 的 Codex 会话：
  - 识别都为 `Codex`
  - 副文案不再出现 `directory: ...`

## 风险与回滚方案

风险：

- 过滤过宽会把真实回复误删

缓解：

- 仅针对已确认的 Codex chrome 固定模式过滤

回滚：

- 仅回滚新加入的 chrome 过滤条件与更严格测试
