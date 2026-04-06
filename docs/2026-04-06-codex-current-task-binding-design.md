# BulingIsland 设计文档：Codex 当前任务块绑定与完成态修复

## 背景与目标

当前 Codex 任务状态判定仍然会把一些已完成任务误判为 `running`。根因有两类：

- `codex.json` 的 `running` 规则过宽，历史残留里的 `esc to interrupt`、工具调用词、footer 等会误触发执行中
- 现有逻辑没有把 `• working` 绑定到“当前任务块”，导致旧任务的工作标志会污染后续底部 prompt

目标：

- `• working` / `reconnecting` 只在“最后一个用户 input 框的上一条有效行”时才认定为当前任务仍在执行
- 如果最后一个用户 input 框上一条有效行不是活动状态行，则该任务视为已完成，不再显示进行中
- `gpt-… left · …` 这类 Codex footer 只作为 chrome 过滤，不参与任务状态判断
- 规则仅针对 `codex`，并对所有终端宿主一致生效

## 范围

包含：

- 新增 Codex 当前任务块活跃态 helper
- 收紧 `codex.json` 的 `running` 规则
- 引擎与 signal parser 共用同一套 Codex running/idle 纠偏
- 新增/更新回归测试

不包含：

- 修改 Claude 策略
- 修改终端捕获 backend
- 调整非 Codex 通用状态机语义

## 方案设计

### 1. 提取 Codex 当前任务块 helper

在 `TaskSessionTextToolkit` 中：

- 先识别最后一个用户 input 行（允许它是底部 placeholder 输入框）
- 再向上回看第一条有效行，只有它是 `• Working` 或 `Reconnecting` 时，才认定当前任务仍在执行
- 展示标题继续使用“最后一个真实提交任务 prompt”，避免把底部 placeholder prompt 当成当前执行任务

这样不再基于整段尾部做模糊 running 判断，而是基于 Codex 当前输入框邻接结构做判定。

### 2. Engine 与 Signal 统一纠偏

在 `TaskSessionEngine` 与 `TaskStrategySessionSignalParser` 中：

- 对 `codex` 策略先调用 `codexCurrentTaskIsActive`
- 若 helper 返回 `false`，则即使原始 JSON 结果是 `running`，也纠偏为 `idle`
- 若 helper 返回 `true`，则对 `idle` 原始结果抬升为 `running`

### 3. Prompt-only 的 Codex 卡片展示完成态

对于 `codex`：

- 若识别到真实 prompt
- 且当前任务块无活动状态行

则任务面板按“已完成”展示，即 `prompt + 任务已完成`。

### 4. 收紧策略 JSON

`codex.json` 的 `running` 规则去掉会误伤已完成任务的宽泛项：

- `esc to interrupt`
- `exec_command`
- `apply_patch`
- `update_plan`
- `wait_agent`
- `tool call`
- `compiling`
- `building for debugging`
- `running tests`
- footer regex

保留：

- `• working`
- `reconnecting`

## 变更清单

- `docs/2026-04-06-codex-current-task-binding-design.md`
- `Sources/Services/TaskEngine/TaskSessionTextToolkit.swift`
- `Sources/Services/TaskEngine/TaskSessionEngine.swift`
- `Sources/Services/TerminalIntegration/TerminalSessionSignalParsing.swift`
- `Sources/Configs/TaskStrategies/codex.json`
- `Tests/BulingIslandTests/TaskSessionStrategyTests.swift`
- `Tests/BulingIslandTests/TaskSessionPanelTextTests.swift`
- `Tests/BulingIslandTests/RelaFixtureConsistencyTests.swift`

## 验证方案

执行：

```bash
swift test
./install-local.sh
```

检查点：

- prompt-only 的 Codex 尾部不再显示 `running`
- `working` 只有在最后一个 input 框上一条有效行时才算运行中
- `working` 位于上一任务块时，仍绑定到该任务，不被底部 placeholder prompt 抢走
- Terminal / iTerm 的 Codex 等价样例在完成态展示上一致

## 风险与回滚方案

风险：

- 若未来 Codex 增加新的活动状态行样式，需要同步扩充 `isCodexActiveStatusLine`

回滚：

- 回滚本次 helper、engine/signal 纠偏和 JSON 收紧即可
