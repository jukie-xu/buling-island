# BulingIsland 统一优化执行单（2026-04-02）

- 日期：2026-04-02
- 执行者：Codex
- 执行方式：用户已一次性确认，按阶段连续落地，不逐项中断确认。

## 执行目标

1. 收敛当前改动并清理冗余逻辑。
2. 建立可测试与可持续门禁（Tests + 自动化检查）。
3. 推进核心解耦（Folder 规则引擎化、Settings schema 化）。
4. 保持现有行为稳定，优先低风险高收益改造。

## 阶段计划

### Phase A（立即）

- 清理 `IslandView` 中已被 Task Engine 替代的旧任务判定 helper。
- 为 Task engine / strategy / state machine 增加测试目标与首批单测。
- 增加自动化检查（build + test）。

### Phase B（本次继续）

- 抽离 `FolderLayoutEngine`（纯规则）并接回 `FolderManager`。
- 抽离 `SettingsSchema`（keys/defaults）并接回 `SettingsManager`。

### Phase C（本次可完成范围）

- README 架构章节增量更新（测试与模块化进展）。
- 最终全量 `swift build`、`swift test`。

## 验收

- `swift build` 通过。
- `swift test` 至少包含 Task engine 相关测试并通过。
- `FolderManager` 与 `SettingsManager` 解耦落地且行为不变。
