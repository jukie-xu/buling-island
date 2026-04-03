# 静音会话硬屏蔽、Tabby 下线与结构化交互设计

## 背景与目标

当前外部终端任务面板仍有三类问题：

- 被 `mute` 的任务仍可能间接触发 pill 的状态提醒、异常路由或底部提示。
- Tabby 终端没有稳定的会话内容接口，当前实现长期处于不可靠状态。
- Claude / Codex 的等待交互场景只提取了简单按钮列表，没有结构化展示“问题 + 选项”，也无法区分单选和多选。

目标：

- 被静音任务不再触发任何 pill 通知、异常展开路由、底部提示、闪烁或状态文本。
- 若 Tabby 无法稳定支持，则彻底移除相关模块与对外宣传，避免误导用户。
- 对 Claude / Codex / Generic TUI 的等待交互场景建立统一结构化模型，渲染为问题卡片与操作按钮，支持单选和多选。

## 范围

包含：

- `TerminalCaptureService` 的静音过滤收紧。
- `Tabby` 终端类型、后端注册、设置文案、测试清理。
- `TaskSessionTextToolkit` 的交互问题解析。
- `TaskSessionTypes` / `TaskSessionEngine` / `IslandView` 的结构化交互 UI。

不包含：

- 新增替代 Tabby 的抓取实现。
- Claude 内置终端（本地面板）完整交互重构，本次以外部终端任务面板为主。

## 方案设计

### 1. 静音会话：从聚合源头硬屏蔽

问题：

- 当前仅在 `bestStatus` 选择阶段跳过静音会话，但 `interactionHint`、异常路由、上层 pill 状态同步仍可能受历史状态或非严格过滤影响。

方案：

- 在 `TerminalCaptureService.consume` 中，对静音会话统一跳过：
  - `hintText`
  - `bestStatus`
  - `error acknowledgement / fingerprint`
  - `activeSessionIDs`
- 若本轮所有异常来源都来自静音会话，则输出应被视为“无状态可推送”。
- `IslandView` 中消费 `terminalCapture` 状态时，若 `latestStatusSourceSessionID` 对应会话已静音，也不再进入 pill 文案与 abnormal routing。

结果：

- mute 的任务只在任务面板内存在，不再影响任何 pill 展示。

### 2. Tabby：整体下线

结论：

- Tabby 没有稳定的 AppleScript / 官方会话 API。
- 依赖 Accessibility 树抓内容无法保证长期可用，且窗口结构易变，维护成本高于收益。

方案：

- 删除 `TabbySessionCaptureBackend` 的注册。
- 从 `TerminalKind` 移除 `.tabby`。
- 更新设置页文案，不再宣称支持 Tabby。
- 删除 Tabby 相关测试。

结果：

- 产品对外只保留当前稳定支持的 `iTerm2 / iTerm / Terminal.app`。

### 3. 结构化交互模型

新增统一数据结构：

- `TaskInteractionPrompt`
  - `title`: 问题文案
  - `selectionMode`: `single` / `multiple`
  - `options`: `[TaskInteractionOption]`
  - `confirmButton`: 可选；用于多选场景提交

扩展 `TaskInteractionOption`：

- `kind`: `choice` / `confirm`
- 保留 `input` / `submit`

解析策略：

- 从 tail 文本中先提取问题行：
  - 例如 `Would you like to run the following command?`
  - `What should Claude do instead?`
  - `Please confirm`
- 再提取选项：
  - 编号菜单：`1. ... (y)`
  - Y/N fallback
  - 多选标记词：`select one or more`、`choose multiple`、`space to select`
- 多选场景：
  - 选项按钮点击后仅发送对应快捷键，不回车。
  - 额外渲染“确认”按钮，发送回车或专用 confirm key。
- 单选场景：
  - 点击选项立即发送对应输入。

### 4. UI 渲染

在任务卡片等待输入场景中替换原有横向按钮条：

- 顶部显示问题标题。
- 下方显示选项按钮网格或横向按钮组。
- 多选场景增加本地选中态与“确认”按钮。

## 变更清单

- `Sources/Services/TerminalIntegration/TerminalCaptureService.swift`
- `Sources/Services/TerminalIntegration/TerminalKind.swift`
- `Sources/Services/TerminalIntegration/TerminalCapturePluginRegistry.swift`
- 删除 `Sources/Services/TerminalIntegration/TabbySessionCaptureBackend.swift`
- `Sources/Views/SettingsView.swift`
- `Sources/Services/TaskEngine/TaskSessionTypes.swift`
- `Sources/Services/TaskEngine/TaskSessionTextToolkit.swift`
- `Sources/Services/TaskEngine/TaskSessionStrategy.swift`
- `Sources/Services/TaskEngine/ConfigurableTaskSessionStrategy.swift`
- `Sources/Services/TaskEngine/TaskSessionEngine.swift`
- `Sources/Views/IslandView.swift`
- `Tests/BulingIslandTests/TaskSessionTextToolkitTests.swift`
- `Tests/BulingIslandTests/TaskSessionStrategyTests.swift`
- `Tests/BulingIslandTests/TerminalCaptureServiceTests.swift`

## 验证方案

1. `swift test` 全量通过。
2. 静音任务存在 `warn/error/waitingInput` 时，不再触发 pill 文案和异常路由。
3. 设置页文案与代码中不再出现 Tabby 支持描述。
4. 任务面板对 Codex / Claude 的等待输入场景展示：
   - 问题标题
   - 单选按钮
   - 多选按钮 + 确认按钮

## 风险与回滚

风险：

- 多选交互的实际 TUI 快捷键语义并不统一。

缓解：

- 多选先采用最保守协议：选项按钮发选项快捷键但不提交，确认按钮单独提交。

回滚：

- 如多选策略与某个 TUI 冲突，可保留结构化问题展示，同时回退为单击直接发送原始 `input`。
