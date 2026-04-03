# BulingIsland 设计文档：`rela/` 样例驱动的跨终端一致性回归

## 背景与目标

当前终端捕获层允许不同终端使用不同能力与脚本，但一旦拿到终端文本，后续的提炼、状态判定、交互抽取、pill 文案、任务面板文案都必须保持一致。

仓库中的 `rela/` 目录已经沉淀了 Claude / Codex 的真实 TUI 输出样例。需要把这些样例从“人工参考材料”升级为“强制回归规范”：

- 每个样例都必须有固定测试覆盖。
- 相同语义、不同终端渲染差异的样例，必须验证最终解析结果一致。
- 未来所有涉及终端文本解析、任务状态、pill、交互提取、文案展示的改动，都必须通过这组样例测试。

## 范围

包含：

- 为 `rela/*.txt` 建立统一 fixture 读取层。
- 为每个样例建立显式测试用例。
- 为可配对的跨终端/跨渲染样例建立“一致性断言”。
- 更新 `CODEX_RULES.md`，把 `rela/` 回归测试纳入强制开发规范。

不包含：

- 修改 `rela/` 样例内容本身。
- 为所有未来样例建立自动推导规则；本次先建立可维护的显式规范。
- 改动终端捕获 backend。

## 方案设计

### 1. fixture 读取层

在测试目录中新增 `rela` fixture helper：

- 负责从仓库根目录读取 `rela/*.txt`
- 屏蔽测试运行目录差异
- 为后续新增样例提供统一入口

### 2. 单样例规范测试

为每个样例定义一份期望：

- `strategyID`
- `lifecycle`
- `renderTone`
- `prompt`
- `reply`
- `interactionPrompt.title`
- `interaction options`
- `secondaryText` 的关键片段

执行链路统一按真实业务路径走：

1. 构造 `CapturedTerminalSession`
2. 用 `TaskSessionStrategyRegistry.strategy(for:)`
3. 用 `TaskSessionEngine.refresh(...)`
4. 校验 `TaskSessionSnapshot`
5. 用 `TaskStrategySessionSignalParser.parse(...)` 校验 pill 侧输出

这样可以保证测试覆盖：

- TaskEngine
- 策略匹配
- 状态判定
- 交互抽取
- pill 解析
- 任务面板文案

### 3. 跨终端一致性测试

对可明确视为“同一语义的不同渲染版本”的样例，新增配对断言：

- 比较标准化文本产物
- 比较 `prompt / reply / interactionPrompt / lifecycle / tone`
- 比较最终 `TaskSessionSnapshot.secondaryText`

本次首批以 `Codex running` 变体样例为主建立配对断言。

### 4. 规则文件强化

在 `CODEX_RULES.md` 中新增强制规则：

- 任何涉及终端文本解析、任务状态、交互提取、pill 或任务面板文案的改动，必须新增或更新 `rela/` 样例测试。
- 如果新增真实终端样例，必须同步补测试。
- 任务完成前必须验证不同终端样例的最终渲染结果一致。

## 变更清单

- `docs/2026-04-03-rela-cross-terminal-consistency-test-design.md`
- `Tests/BulingIslandTests/RelaFixtureConsistencyTests.swift`
- `CODEX_RULES.md`

如测试实现需要，可附带新增测试内 helper 文件。

## 验证方案

执行：

```bash
swift test
./install-local.sh
```

验证点：

- 每个 `rela` 样例均被测试读取并断言。
- Claude / Codex 的关键状态与交互样例断言通过。
- 跨终端/跨渲染等价样例的一致性断言通过。
- 规则文件已明确要求未来改动必须维护这套样例测试。

## 风险与回滚方案

风险：

- 某些样例包含长文本与历史输出，当前策略可能暴露出旧的误判。
- 个别样例名称未完整表达语义，需在测试代码中人工定义期望。

回滚：

- 若新测试暴露旧逻辑问题，优先修解析逻辑，不回退测试规范。
- 如需临时回滚，仅回滚新增测试与规则文件改动，不影响现有运行时功能。
