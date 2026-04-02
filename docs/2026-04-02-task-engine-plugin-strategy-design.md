# BulingIsland 设计文档：Task 引擎 + 可插拔策略（Claude/Codex）

- 日期：2026-04-02
- 作者：Codex
- 需求：将 task 面板中的检测机制、任务状态机刷新、样式渲染抽象为标准引擎与策略，并支持多策略可插拔，兼容更多 TUI（如 Codex）。

## 1. 目标

1. 将 `IslandView` 内 task 检测逻辑从 UI 代码中剥离。
2. 提供统一 `TaskSessionEngine` 负责：
   - 策略匹配
   - 状态计算
   - 状态机平滑刷新（防抖/粘滞）
3. 提供可插拔策略接口：
   - 默认内置 `ClaudeTaskSessionStrategy`
   - 新增 `CodexTaskSessionStrategy`
   - 保底 `GenericTaskSessionStrategy`
4. Task 面板仅消费引擎输出进行渲染。

## 2. 范围

### In Scope

- 新增任务引擎模型、协议、状态机、策略注册机制。
- 迁移现有 Claude 任务检测逻辑到策略层。
- 新增 Codex 策略（启发式）。
- 更新 Task 面板 UI 使用引擎快照。

### Out of Scope

- 不改终端捕获后端协议。
- 不改设置面板配置项。
- 不引入外部插件动态加载（本次为代码级可插拔）。

## 3. 架构设计

## 3.1 核心对象

- `TaskSessionEngine` (`@MainActor`, `ObservableObject`)
  - 输入：`sessions`, `activeSessionIDs`
  - 输出：`snapshotsBySessionID`
  - 能力：安装/替换策略，按优先级匹配策略，调用状态机稳定状态。

- `TaskSessionStrategy` (protocol)
  - `strategyID`
  - `displayName`
  - `priority`
  - `supports(session:)`
  - `analyze(session:) -> TaskSessionRawAnalysis`

- `TaskSessionStateMachine`
  - 管理每个 session 的上一状态、时间戳
  - 提供状态粘滞与短时平滑，减少闪烁

## 3.2 状态模型

- `TaskLifecycleState`
  - `inactiveTool`：未识别为已支持 TUI
  - `idle`：会话存在但未执行任务
  - `running`：执行中
  - `waitingInput`：等待确认/交互
  - `success`：成功完成
  - `error`：异常

- `TaskRenderTone`
  - `neutral`
  - `running`
  - `warning`
  - `success`
  - `error`
  - `inactive`

- `TaskSessionSnapshot`
  - `sessionID`
  - `strategyID`
  - `strategyDisplayName`
  - `lifecycle`
  - `renderTone`
  - `isRunning`
  - `secondaryText`
  - `refreshedAt`

## 3.3 策略可插拔机制

- 引擎初始化加载默认策略列表。
- 支持 `installStrategy(_:)`，按 `priority` 排序；同 `strategyID` 后装覆盖旧策略。
- 支持 `replaceStrategies(_:)` 全量替换，满足多策略组合。

## 3.4 默认策略

- `ClaudeTaskSessionStrategy`：迁移现有 Claude 检测与文本提取逻辑。
- `CodexTaskSessionStrategy`：识别 codex/openai codex 常见标记，复用通用错误/运行/确认判断。
- `GenericTaskSessionStrategy`：兜底，尽量给出可读状态。

## 3.5 状态机刷新规则（v1）

- `error` 粘滞 8 秒（除非检测到新 running）。
- `success` 粘滞 5 秒（除非检测到 error/running）。
- `running -> idle` 延迟 2 秒，防止短抖动。

## 4. 接入方案

1. `IslandView` 持有 `@StateObject private var taskSessionEngine`。
2. 在 `onAppear` 与 `terminalCapture.statusRevision` 变化时调用 `refreshTaskSnapshots()`。
3. Task 面板渲染从 `session + snapshot` 读取状态、文案和 tone。
4. 点击跳转逻辑按 `snapshot.lifecycle == .error` 决定是否保持任务面板展开。

## 5. 验收标准

- `swift build` 通过。
- Task 面板逻辑不再依赖 `IslandView` 中的 Claude 专属判断函数。
- 支持至少 3 策略并行注册（Claude/Codex/Generic）。
- 任务状态随轮询刷新，且有状态机平滑效果。

## 6. 后续扩展

- 为策略增加可配置关键字表（JSON/Settings）。
- 增加策略单测（状态判定与状态机转移）。
- 支持按策略类型分组展示（Claude/Codex/Other）。
