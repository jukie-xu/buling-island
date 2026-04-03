# 任务面板副文案（secondaryText）编排设计

## 背景与目标

任务行原先直接使用策略 JSON 的 `truncateCompact` 或 `promptAndReply`，易把横幅、脚注等终端装饰整段塞进面板。目标：在**未识别到用户输入行**时只显示单行「暂无任务」；执行中显示「用户提问 + 最新助手摘要」；成功时第二行固定为「任务执行完毕」。

## 范围

- **In**：`TaskSessionEngine` 产出的 `TaskSessionSnapshot.secondaryText`（任务面板展示）。
- **Out**：收缩药丸、TerminalCapture 的其它摘要逻辑；策略生命周期判定（仍用 compact/rules）。

## 设计

0. **生命周期**：仅以各策略对终端尾部的匹配结果为准（如 Codex 的 `• working` 等）；引擎**不**再根据 `TerminalCaptureService.activeSessionIDs`（近期有输出变化）将 `idle` 抬升为 `running`，以免未提交的输入也显示「处理中」。
1. **状态缓存**（按 `sessionID`）：`TaskSessionPanelMemory` 存 `cachedUserPrompt`、`cachedAgentReply`。
2. **每轮刷新**：在状态机 `stabilize` 之后，用 `extractLatestUserPrompt` / `extractLatestReply` 更新缓存；若最新提问与缓存不同，清空旧 `cachedAgentReply`。
3. **编排规则**（`TaskSessionTextToolkit.composeTaskPanelSecondaryText`）：
   - 无提问且无缓存：`error` → 仅错误摘要；其它 → 「暂无任务」。
   - `running` / `waitingInput`：第 1 行提问，第 2 行最新回复或「处理中…」。
   - `success`：第 1 行提问，第 2 行「任务执行完毕」。
   - `error`：第 1 行提问（若有），第 2 行错误摘要。
   - `idle`：有回复则双行；仅提问则单行提问。
4. **`inactiveTool`**：沿用策略原文案，不覆盖。
5. **Chrome 过滤**：营销 Tip、`gpt-x.x medium · n% left ·` 脚注仅从 `extractLatestReply` 路径排除，**不**写入全局 `isNoiseLine`，以免掏空 `compact` 破坏 Codex `running` 匹配。

## 验收

- [ ] 无 `›`/`❯` 等用户输入、无缓存时面板副文案仅为「暂无任务」。
- [ ] 执行中：双行，第二行为助手最新一行合理摘要或「处理中…」。
- [ ] 成功：第二行为「任务执行完毕」。
- [ ] Codex 仅 Tip+脚注时生命周期仍能判为 `running`（回归）。

## 风险与回滚

- 回滚：删除引擎内 `composeTaskPanelSecondaryText` 覆盖，恢复 `analysis.secondaryText`。
- 风险：`extractLatestUserPrompt` 依赖前缀启发式，非标输入格式的终端可能仍显示「暂无任务」。

## 实施步骤

1. `TaskSessionTypes` + `TaskSessionTextToolkit` 编排与缓存更新。
2. `TaskSessionEngine` 接入。
3. 单测 `TaskSessionPanelTextTests`。
