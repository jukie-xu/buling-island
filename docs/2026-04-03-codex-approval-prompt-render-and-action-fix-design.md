## 背景

Codex 授权/确认弹窗在任务面板里出现三类问题：

1. 卡片主文案仍显示旧的压缩摘要，导致编号选项被误当成正文。
2. 结构化交互解析把 `Reason:` 误识别成问题标题，并把 `$ git ...` 命令行误过滤掉。
3. 交互按钮点击后没有稳定触发终端内选择，iTerm / Terminal 的发送动作缺少对目标终端进程的显式绑定，任务行整体点击也会和按钮点击竞争。

## 目标

1. `waitingInput` 且已解析出 `interactionPrompt` 时，任务卡片正文只展示结构化交互内容。
2. Codex 授权提示统一解析为：
   - `title`: 顶层问题，如 `Would you like to run the following command?`
   - `body`: 原因与命令，如 `Reason: ...` 和 `$ git add -A ...`
   - `instruction`: 底部操作提示，如 `Press enter to confirm or esc to cancel`
3. 交互按钮点击时，动作必须实际发送到目标终端会话。
4. 该场景必须有测试覆盖，避免不同终端或后续改动再次回归。

## 实施

1. 在 `TaskSessionTextToolkit` 中收紧交互问题提取：
   - 优先识别顶层问题行；
   - `Reason:` 允许作为 body，不再抢占 title；
   - `$ ...` 命令行允许进入 body。
2. 在 `IslandView` 中：
   - `waitingInput + interactionPrompt` 时隐藏旧 `secondaryText`；
   - 禁用整行点击跳转，改由交互按钮和显式“前往终端”入口承担跳转。
3. 在各终端 backend 的 `sendActions`/必要的 `sendInput` 中：
   - 先激活并选中目标会话；
   - 增加短延迟；
   - 使用 `System Events -> process "<terminal>"` 发送键盘动作。
4. 新增测试：
   - 授权弹窗的标题/body/instruction/options 解析测试；
   - 结构化交互体不会把 `Reason:` 误识别为 title；
   - 命令行 `$ git ...` 不会被过滤掉。
