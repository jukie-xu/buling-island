# BulingIsland 架构扫描与模块化拆分路线（2026-04-02）

- 日期：2026-04-02
- 作者：Codex
- 目的：扫描当前项目，评估架构优化与模块化拆分可行性，降低耦合、提升复用与稳定性。

## 1. 当前项目画像

- Swift 文件：58
- 主要目录：`Sources/Views`、`Sources/Services`、`Sources/Models`
- 代码总行数（Swift）：约 9556
- 体量最大的文件：
  - `Sources/Views/IslandView.swift` (1731)
  - `Sources/Views/SettingsView.swift` (1415)
  - `Sources/Services/FolderManager.swift` (514)
  - `Sources/Views/LaunchpadGridView.swift` (480)

结论：当前项目可维护，但关键风险是“核心入口视图与设置视图过大、全局单例过多、跨层事件依赖隐式化”。

## 2. 主要耦合点与风险

## 2.1 视图层耦合重

- `IslandView` 同时处理：
  - Claude 面板生命周期
  - Task 面板状态渲染
  - pill 提示/闪烁/路由
  - Panel 交互同步
- 风险：改一个能力易影响其它能力，回归面大。

## 2.2 全局单例较多

- `SettingsManager.shared`
- `PanelManager.shared`
- `FolderManager.shared`
- `AppDiscoveryService.shared`
- 风险：
  - 依赖方向不透明
  - 测试替身（mock/fake）困难
  - 生命周期与状态刷新难控

## 2.3 规则分散

- 终端输出解析规则、噪音过滤、状态映射分散在多个文件。
- 当前已通过 Task Engine 统一了一部分，但 Claude Panel 与 Task Panel 仍有部分规则重复。

## 2.4 持久化与领域模型耦合

- `FolderManager` 同时承担“领域逻辑 + 存储 IO + 迁移修复”。
- 风险：后续扩展（云同步、历史版本、导入导出）困难。

## 3. 可行的模块化拆分目标

建议分三层模块（先逻辑分层，再按 SwiftPM target 物理拆分）：

## 3.1 Core（纯逻辑、可测试）

- `Domain Models`：App、Folder、Task Session Snapshot
- `Rules Engine`：Task engine、搜索匹配规则、状态机
- `Use Cases`：
  - BuildLaunchpadLayout
  - AnalyzeTaskSession
  - ResolvePillStatus

收益：可单测、可复用、可在 UI 之外运行。

## 3.2 Platform（系统集成）

- AppKit Panel/Notch/Screen 相关
- AppleScript Terminal backend
- IOKit 电量/网络读取

收益：与业务规则解耦，便于替换实现（例如不同终端后端）。

## 3.3 App/UI（装配层）

- SwiftUI 页面与组件
- ViewModel（编排）
- 配置页面

收益：UI 聚焦“展示与交互”，规则下沉到 Core。

## 4. 模块化拆分可行性评估

## 4.1 高可行（可立即做）

1. 将 Task 引擎相关完全收敛到 `Services/TaskEngine`（已完成第一版）。
2. 将 Launchpad 领域规则从 `FolderManager` 分离到 `FolderLayoutEngine`。
3. 将 Settings key/默认值集中到 `SettingsSchema`，减少散落字符串 key。

## 4.2 中可行（需阶段性改造）

1. 把 `IslandView` 的 pill/claude/task 协调逻辑迁到 `IslandCoordinator`。
2. `PanelManager` 拆分：
   - `PanelWindowHost`
   - `PanelInteractionMonitor`
   - `PanelSpaceVisibilityController`

## 4.3 长期可行（收益大）

1. 多 Target：`BulingCore` / `BulingPlatform` / `BulingApp`。
2. 建立接口注入（protocol + DI container），替代绝大多数 `.shared`。
3. 引入最小事件总线（typed event）替代散落 `NotificationCenter`。

## 5. 复用能力与规则收敛建议

## 5.1 Task 规则统一化

- 新增 `TaskSessionTextToolkit` 后，继续把 Claude panel 内与任务状态相关的文本规则迁到 toolkit。
- 保持“策略只负责识别与分析，UI 不写判定规则”。

## 5.2 设置能力复用

- 建议把 `SettingsManager` 的 key、默认值、迁移逻辑拆成：
  - `SettingsKeys`
  - `SettingsDefaults`
  - `SettingsMigration`

## 5.3 布局规则复用

- Launchpad 布局去重、修复、智能合并可沉淀到 `LaunchpadLayoutRules`。
- UI 层只调用规则执行结果。

## 6. 稳健性提升优先级（建议按阶段）

## Phase A（1~2 天）

- 引入策略注册启动入口（已实现）。
- Task 引擎加最小单元测试（状态机 + 策略匹配）。
- 给 `FolderManager` 增加存储异常日志与回退保护。

## Phase B（3~5 天）

- 拆 `IslandView` 协调逻辑到 `IslandCoordinator`。
- `SettingsSchema` 收敛。
- `PanelManager` 子组件化。

## Phase C（5~10 天）

- Core/Platform/App 三层目标拆分。
- 协议注入替代 shared。
- 基础自动化门禁：build + tests + lint。

## 7. 本次结论

- 模块化拆分可行，且应采用“先逻辑模块化，再物理拆分 target”的路线。
- 当前最关键收益点：
  - 降低 `IslandView` 与 `SettingsView` 的复杂度
  - 让规则进入 engine/toolkit
  - 减少全局单例耦合
- 若按上述路线推进，项目可显著提升稳定性、可测试性和扩展新 TUI 的速度。
