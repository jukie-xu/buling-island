# BulingIsland 设计文档：Codex `working` 结束态判定修复

## 背景与目标

当前 Codex 会话在任务已结束后，尾部可能只剩：

- 用户最后一次任务输入
- Codex 底部固定尾行（如 `gpt-5.4 medium · 56% left · ~/git/buling-island`）

这类尾行是标准 Codex chrome，不应参与任务完成判定，也不应作为“空闲证据”本身。正确规则应是：

- `gpt-… left · …` 这类尾行始终视为 Codex 固定尾部信息并剔除
- 对 Codex 来说，是否仍在执行，核心看 `• working` 是否存在
- 如果之前同一任务出现过 `working`，现在没有了，则该任务已结束
- 如果当前就没有 `working` 标志行，则不应被判定为执行中

目标：

- 修正为仅对 `codex` 生效的状态过渡规则
- 保持所有终端宿主上的 Codex 行为一致
- 不把通用状态机逻辑污染成“靠尾部 footer 猜状态”

## 范围

包含：

- 调整 `TaskSessionEngine` 中 Codex 的 `running -> idle` 过渡判定
- 回退上一次加入的泛化“footer-only 空闲证据”逻辑
- 增加 Codex 专用回归测试

不包含：

- 修改非 Codex 策略
- 修改终端 backend 捕获逻辑
- 调整任务面板完成态文案

## 方案设计

### 1. 保留通用状态机，改为引擎侧按策略控制粘滞

`TaskSessionStateMachine` 的 `running -> idle` 粘滞窗口仍保留，但是否启用由上层决定。

对 `codex`：

- 若当前 raw lifecycle 已是 `idle`
- 且当前 prompt 与缓存任务 prompt 相同
- 且该会话之前已经进入过活动任务（出现过 `working` / waiting / success / error）

则直接关闭 `running -> idle` 粘滞，立即退出执行中。

### 2. 不再用 footer-only 作为通用空闲证据

撤销上一次新增的“prompt + footer only 即 definitive idle evidence”规则。

原因：

- 这会把 Codex 特有尾行语义错误泛化到其他终端/策略
- 用户明确要求以 `working` 是否消失作为 Codex 的完成判断依据，而不是依赖 footer

### 3. 用回归测试锁定 Codex 专用行为

新增测试覆盖：

- 同一 Codex 任务先出现 `• Working`，下一轮只剩 prompt + footer 时，应立即退出 `running`
- 普通状态机的通用 2 秒粘滞仍然存在
- footer-only 仍只作为 chrome 被剔除，不再作为共享 idle 判据

## 变更清单

- `docs/2026-04-06-codex-working-transition-fix-design.md`
- `Sources/Services/TaskEngine/TaskSessionEngine.swift`
- `Sources/Services/TaskEngine/TaskSessionTextToolkit.swift`
- `Tests/BulingIslandTests/TaskSessionPanelTextTests.swift`
- `Tests/BulingIslandTests/TaskSessionStateMachineTests.swift`
- `Tests/BulingIslandTests/TaskSessionTextToolkitTests.swift`

## 验证方案

执行：

```bash
swift test
./install-local.sh
```

检查点：

- Codex prompt + footer-only 场景不再显示执行中
- 仅 Codex 使用该过渡逻辑
- 其他共享状态机测试不回归

## 风险与回滚方案

风险：

- 如果未来某个非 Codex 策略也有类似“显式 working 结束”模型，仍需单独扩展，不应复用当前 Codex 专用规则

回滚：

- 回滚本次引擎侧 Codex 专用过渡控制与新增测试即可
