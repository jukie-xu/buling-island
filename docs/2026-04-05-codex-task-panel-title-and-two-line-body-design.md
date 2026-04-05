# BulingIsland 设计文档：Codex 任务卡片标题与双行正文统一

## 背景

当前 Codex 任务卡片把“顶部标题”和“正文两行摘要”的职责混在一起，导致：

- session 标题可能被任务提问覆盖
- 第一行/第二行的语义在不同状态下不稳定
- 测试多数只校验 `secondaryText`，没有校验最终卡片展示契约

## 目标

针对 Codex 任务卡片，统一遵循以下规则：

1. 顶部始终展示终端 session 的 `title`
2. 正文第一行展示该 session 最近一次真实用户发问，并在轮询间缓存
3. 正文第二行展示任务结果
   - `running` / `waitingInput`：展示当前最后一条有效输出
   - `success` / 已结束回到 `idle`：展示 `任务已完成`
   - `error`：展示错误摘要

## 实现

1. 继续由 `TaskSessionTextToolkit.composeTaskPanelSecondaryText` 生成正文双行文本
2. `IslandView.taskBoardRowView` 顶部标题改回 `task.title`
3. 任务卡片正文统一使用 `TaskSessionTextToolkit.taskPanelDisplayLines` 拆分后的两行
4. 补充跨终端测试，直接断言 iTerm2 / iTerm / Terminal 的最终卡片展示 contract

## 验证

- `TaskSessionPanelTextTests`
- `RelaFixtureConsistencyTests`
- `swift build`
