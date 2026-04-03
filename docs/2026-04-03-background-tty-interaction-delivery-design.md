## 背景

当前任务面板交互按钮主要依赖终端切前台后再发送按键。这条路径有两个结构性风险：

1. 前台焦点容易被用户当前操作打断，导致按键落到错误窗口。
2. 即便终端会话已被选中，`System Events` 的按键注入仍受时序与可访问性状态影响。

## 目标

将任务交互执行改为：

1. 优先后台直写目标会话的 TTY；
2. 仅在 TTY 不可用或写入失败时，回退到各终端 backend 的前台注入；
3. `sendInput` 和 `sendActions` 共用同一套底层动作序列编码，保证行为一致。

## 方案

1. 新增 `TerminalTTYWriter`：
   - 输入：`tty path` 与 `TaskInteractionOption.Action[]`
   - 输出：是否写入成功
   - 编码规则：
     - `text("abc") -> "abc"`
     - `enter -> "\\r"`
     - `escape -> "\\u001B"`
     - `tab -> "\\t"`
     - `space -> " "`
     - `arrowUp/Down/Left/Right -> ESC [ A/B/D/C`
2. 在 `TerminalCaptureService` 中优先调用 `TerminalTTYWriter`：
   - `sendInput` 将文本与可选回车转换为动作列表；
   - `sendActions` 直接写动作列表；
   - 写入成功则不再调用 backend。
3. 保留 backend 回退链：
   - 兼容没有 TTY、TTY 权限异常、目标会话已失效等场景。

## 验证

1. 单元测试验证动作到字节序列的映射。
2. 单元测试验证 `sendInput` 文本加回车的编码。
3. 真实场景依旧通过任务面板按钮复测 Codex 授权弹窗。
