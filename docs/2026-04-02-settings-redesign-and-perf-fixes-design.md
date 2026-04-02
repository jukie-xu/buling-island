# BulingIsland 设计文档：设置页样式重做 + 跳转延迟优化 + 应用启动异步化

日期：2026-04-02

## 1. 背景与目标

当前设置页「控制台」区域存在两类体验问题：

- **视觉密度不均衡**：上方「全屏时隐藏灵动岛 / 开机启动」块显得过高、占用大；下方「辅助功能授权」卡显得过短、信息密度不足。
- **交互性能问题**：
  - 从任务面板点击跳转外部终端会话（iTerm/Terminal）**延迟 2~3 秒**，影响“快速定位任务”体验。
  - 应用面板点击应用时存在**阻塞主线程**的风险，导致本软件卡住。

目标：

- 重新设计设置页该区域版式，让开关使用系统 Toggle 风格、信息密度更均衡。
- 优化终端激活/跳转的感知延迟（尽可能减少 AppleScript 搜索成本）。
- 应用启动改为异步触发，避免主线程卡顿。

## 2. 范围

### In Scope

- `SettingsView` → `SettingsDashboardTab` 中：
  - “全屏时隐藏灵动岛 / 开机启动”两行开关的视觉与布局调整（更紧凑、右侧 Toggle）。
  - “辅助功能授权”卡片重做为“状态徽标 + 更完整说明 + 主按钮/次按钮”，并与上方区域保持同宽与一致边距。
- 终端跳转延迟：
  - 优化 `ITerm2SessionCaptureBackend.activate` 与 `LegacyITermSessionCaptureBackend.activate` 的 AppleScript 查询方式，减少嵌套遍历开销。
- 应用启动异步化：
  - `AppDiscoveryService.launchApp` 从主线程调用改为后台队列执行。

### Out of Scope

- 不改动终端会话捕获的轮询协议与数据结构（`TerminalSessionRow` 字段不扩展）。
- 不引入新的权限类型（仅复用已有 Automation / Accessibility 相关能力）。
- 不在本次引入新的测试覆盖与自动化门禁约束（后续独立任务处理）。

## 3. 详细设计

### 3.1 设置页布局（控制台）

设计原则：

- **两块同宽**：上方“常规开关卡”和下方“权限卡”宽度一致、边距一致。
- **上方更紧凑**：开关行的纵向 padding 收敛，副说明行高更紧，减少占用。
- **下方更饱满**：权限卡增加状态徽标与更完整说明，避免“太短”。

具体布局：

- 常规开关卡
  - 标题：`常规`
  - 两行 Toggle Row：
    - `全屏时隐藏灵动岛`（caption：前台全屏时自动隐藏收缩态灵动岛）
    - `开机启动`（caption：登录 macOS 时自动启动）
  - 行分隔线：弱化（暗色 0.18~0.25）
  - Toggle：`.toggleStyle(.switch)` + `.controlSize(.small)`

- 权限卡（辅助功能授权）
  - 标题：`权限`
  - 子标题：`辅助功能授权`
  - 状态徽标：`已授权`（green）/ `未授权`（orange）
  - 说明两行：
    - 用途说明：点击唤醒/收起、外部点击收起等全局交互
    - 隐私承诺：不读取键盘内容、不收集输入内容（仅用于交互）
  - 按钮：
    - 未授权：主按钮 `去授权…`（accent）
    - 已授权：禁用态 `已授权`
    - 次按钮：`打开系统设置`（始终可用，直接打开对应隐私页）

### 3.2 终端跳转延迟优化（任务面板 → 外部终端）

现状：

- `TerminalCaptureService.activate(session:)` 触发 backend 的 `activate(...)`。
- iTerm/iTerm2 的 `activate` 脚本通过三层 `repeat` 全量扫描 windows/tabs/sessions，命中后 `select`。
- 在会话数量较多时，AppleScript 执行时间显著上升，导致用户感知 2~3 秒。

方案：

- 用 AppleScript 的 **对象过滤查询（whose）** 替代嵌套遍历，减少脚本解释层循环开销：
  - iTerm2：`every session of every tab of every window whose unique id is targetID`
  - iTerm：同上
- 保持行为：
  - 命中后切到对应会话并激活应用。
  - 未命中返回 `__SESSION_NOT_FOUND__`（仍旧忽略结果）。

### 3.3 应用启动异步化（应用面板）

现状：

- `AppDiscoveryService.launchApp` 直接 `NSWorkspace.shared.open(app.path)`。
- 在某些系统状态下（首次启动/安全校验/冷盘），调用可能在主线程上造成卡顿。

方案：

- 将 `open` 调用移到 `DispatchQueue.global(qos: .userInitiated)`，主线程仅负责响应 UI。

## 4. 验收标准（Checklist）

- 设置页（控制台）：
  - [ ] 上方两项开关为系统 Toggle 风格，整体高度明显收敛（行高更紧凑）。
  - [ ] “辅助功能授权”卡与上方卡同宽，信息更完整（含状态徽标 + 两行说明 + 主/次按钮）。
  - [ ] 已授权状态按钮禁用，未授权状态按钮可点击并能跳转系统设置。

- 终端跳转：
  - [ ] 从任务面板点击跳转 iTerm/iTerm2 会话时，感知延迟降低（目标：常见场景 < 1s；重负载时也优于原实现）。
  - [ ] iTerm/iTerm2 未运行时不崩溃（原有容错保留）。

- 应用启动：
  - [ ] 点击应用后 UI 不出现明显卡顿，主线程保持可交互。

## 5. 风险与回滚策略

- 风险：AppleScript `whose` 查询在不同 iTerm 版本下可能不兼容。
  - 回滚：恢复旧的嵌套遍历脚本（单文件回退即可）。
- 风险：异步启动应用可能掩盖启动失败。
  - 缓解：保持现有行为不新增弹窗；如后续需要可追加轻量错误日志（不在本次范围）。

## 6. 实施步骤

- 更新 `SettingsView.swift`：重做 `SettingsDashboardTab` 中常规开关卡与权限卡布局。
- 更新 `ITerm2SessionCaptureBackend.swift` / `LegacyITermSessionCaptureBackend.swift`：改写 `activate` 脚本查询方式。
- 更新 `AppDiscoveryService.swift`：应用启动改为后台异步调用。
- 本地验证：`swift build` + `./install-local.sh`（安装并启动）。

