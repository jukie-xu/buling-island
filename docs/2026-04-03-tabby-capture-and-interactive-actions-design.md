# BulingIsland 设计文档：Tabby 捕获增强 + 任务交互按钮执行

日期：2026-04-03

## 1. 背景与目标

当前外部终端捕获已支持 iTerm2 / iTerm / Terminal，但 Tabby 识别与内容提取能力不足；任务面板在 `waitingInput`（交互等待）状态下仅展示文本，无法直接执行选项输入。

本次目标：

1. **复用现有 iTerm 架构模式**，完善 Tabby 检测、会话识别、内容抓取。
2. 在任务面板对 `waitingInput` 状态展示交互选项按钮。
3. 点击按钮后直接向目标终端会话注入输入并执行（可选回车）。

## 2. 总体方案

### 2.1 架构原则

- 不重写主流程，沿用现有 `TerminalSessionCaptureBackend` 插件机制。
- 业务入口保持在 `TerminalCaptureService` + `TaskSessionEngine`。
- UI 只消费快照，不直连脚本实现。

### 2.2 分层改造

1. **Terminal 层（捕获 + 激活 + 输入）**
   - Tabby backend 强化检测与文本提取。
   - 后端协议新增可选能力：发送输入。

2. **TaskEngine 层（状态 + 交互选项）**
   - 快照增加 `interactionOptions`。
   - 分析阶段在 `waitingInput` 时提取交互菜单项。

3. **View 层（任务面板）**
   - `waitingInput` 行渲染选项按钮。
   - 点击按钮执行输入，保留当前面板。

## 3. Tabby 捕获设计

### 3.1 进程识别

- 支持 `Tabby` 与 `tabby` 进程名。
- `TerminalKind.tabby` 增加 bundle 候选：`org.tabby`、`io.tabby`、`app.tabby`。

### 3.2 会话模型

- 采用“窗口级 session”：
  - `nativeSessionId` = window id（兜底 window name）
  - `title` = window name
  - `tty` 暂为空（Tabby UI 脚本层难稳定获取）

### 3.3 内容提取

- 通过 `System Events` 在窗口 UI 子树中搜索 `AXTextArea`。
- 选择首个可读非空 `value` 作为会话文本。
- 尾窗截断（例如 12000 字符）避免过重轮询。
- 失败时降级为空字符串，不作为脚本错误上抛。

## 4. 交互按钮设计

### 4.1 数据结构

新增 `TaskInteractionOption`：

- `id`: 稳定键
- `label`: 展示文案
- `input`: 注入终端的输入内容（如 `y` / `n` / `p`）
- `submit`: 是否回车执行

`TaskSessionRawAnalysis` / `TaskSessionSnapshot` 增加 `interactionOptions`。

### 4.2 规则提取

在 `TaskSessionTextToolkit` 新增解析器：

1. 解析编号菜单：`^\s*\d+\.\s+...`。
2. 优先读取尾部快捷键（如 `(y)`、`(p)`）生成输入。
3. 若未出现编号菜单但命中 `[y/n]` 或 `(y/n)`，回退生成 Yes/No 两按钮。
4. 仅在 `waitingInput` 生命周期下对外输出选项。

### 4.3 UI 行为

- 任务行在 `snapshot.lifecycle == .waitingInput` 且 `interactionOptions` 非空时展示按钮区。
- 点击按钮：
  - 调 `terminalCapture.sendInput(...)`
  - 成功后不折叠面板，等待下一轮轮询刷新状态。
- 原有点击任务行跳转外部终端保留（兜底操作）。

## 5. 后端输入执行设计

在 `TerminalSessionCaptureBackend` 增加默认能力：

- `sendInput(nativeSessionId, terminalKind, text, submit) -> Bool`（默认 false）

各后端实现：

- `ITerm2SessionCaptureBackend`：定位 session 后 `write text`（支持 no newline / newline）。
- `LegacyITermSessionCaptureBackend`：同上。
- `AppleTerminalSessionCaptureBackend`：选中目标 tab，`System Events keystroke` + 可选 Enter。
- `TabbySessionCaptureBackend`：聚焦窗口，`System Events keystroke` + 可选 Enter。

`TerminalCaptureService` 增加统一入口：`sendInput(to:session, text:, submit:)`。

## 6. 兼容性与风险

1. Tabby UI 树变更风险：
   - 提取逻辑采用多层 try + 降级，不影响主流程。
2. 权限风险（辅助功能 / 自动化）：
   - 与现有外部终端捕获一致，继续依赖系统授权。
3. 输入误触风险：
   - 仅在 `waitingInput` 显示按钮。
   - 按钮触发不自动切换到其他会话，先定位目标会话再输入。

## 7. 验证计划

1. 单元测试
   - 交互选项解析器：编号选项 / y-n 回退 / 无选项。
   - `TaskSessionSnapshot` 携带 `interactionOptions`。
   - Tabby terminal kind 解析与 backend 注册可用。

2. 集成验证
   - Tabby 运行时可出现会话条。
   - `waitingInput` 任务行显示按钮并可注入输入。
   - 输入后状态从 `waitingInput` 转到 `running/success/error`（依样本）。

## 8. 实施顺序

1. 扩展 `TerminalKind` 与 Tabby backend（检测+内容）。
2. 扩展 backend 协议与各后端 `sendInput`。
3. 扩展 TaskEngine 快照与交互选项提取。
4. 任务面板 UI 增加按钮与执行逻辑。
5. 补测试并跑全量 `swift test`。
