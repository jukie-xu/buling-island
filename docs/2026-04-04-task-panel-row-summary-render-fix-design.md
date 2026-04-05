# BulingIsland 设计文档：任务面板行摘要渲染修正

## 背景

当前任务面板卡片首行使用 `task.title`（终端窗口标题）渲染，正文直接渲染整段 `snapshot.secondaryText`。这会导致：

- 完成态首行显示成终端标题，而不是用户任务标题
- 正文把两行摘要整段重复渲染，视觉层级错误
- Codex 完成后即使摘要已是 `提交并推送\n任务已完成`，界面仍可能表现为首行不对、第二行重复

## 目标

将任务卡片展示统一到 `snapshot.secondaryText`：

- 第一行展示摘要首行（通常是用户任务标题）
- 第二行展示摘要次行（如 `任务已完成` / `处理中…` / 最新回复）
- `waitingInput` 继续优先展示结构化详情，但卡片首行也应与摘要首行一致

## 方案

1. 在 `TaskSessionTextToolkit` 增加任务面板摘要拆行工具，将 `secondaryText` 拆为 `primary` 与 `secondary`
2. `IslandView.taskBoardRowView` 顶部标题改为优先使用摘要首行，只有摘要为空时才回退到终端标题
3. 非 `waitingInput` 场景下，正文仅显示摘要第二行；若无第二行则不重复渲染
4. `waitingInput` 场景下，正文优先使用 `detailText`，否则回退摘要第二行

## 验证

- 新增单测覆盖 `secondaryText` 双行拆分
- 现有 `TaskSessionPanelTextTests` 持续保证完成态摘要仍为 `提交并推送\n任务已完成`
