## 现象

任务面板在出现 `waitingInput` 场景时明显卡顿，连带 pill 和动画也一起掉帧。

## 根因

排查后发现不是单一 UI 控件问题，而是三类主线程重复工作叠加：

1. `CapturedTerminalSession.standardizedTailOutput` 是计算属性，上层每次访问都会重新做整段文本标准化。
2. `IslandView` 在 `terminalCapture.sessions`、`activeSessionIDs`、`statusRevision` 三个来源上重复调用 `taskSessionEngine.refresh(...)`。
3. `TerminalCaptureService.consume(...)` 即便 pill 状态没有变化，也会在每轮轮询后递增 `statusRevision`，持续驱动主线程刷新。

`waitingInput` 场景更容易放大问题，因为它会额外解析交互文案、确认内容和提示文本。

## 修复

1. `CapturedTerminalSession`
   - 改为在初始化时一次性计算并存储 `standardizedTailOutput`。
2. `IslandView`
   - 任务快照只在 `sessions` 变化时刷新；
   - `activeSessionIDs` 和 `statusRevision` 仅用于 pill/提醒层，不再触发整套任务引擎重算。
3. `TerminalCaptureService`
   - 只有当 `latestStatusText / tone / source / interactionHint / lastError / activeSessionIDs` 实际变化时才递增 `statusRevision`。

## 预期效果

1. 终端轮询仍保持实时，但不会在每个 poll tick 都重复重建任务快照。
2. waiting-input 卡片只在内容真正变化时重算。
3. pill 动画与面板滚动不再被持续的主线程文本解析拖慢。
