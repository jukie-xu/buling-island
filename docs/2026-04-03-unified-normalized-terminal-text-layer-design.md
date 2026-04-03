# 统一标准化终端文本层设计

## 背景与目标

不同终端的捕获能力可以不同，但一旦获得原始终端输出，后续所有环节都必须基于同一份标准化文本工作，否则会出现：

- 相同可见内容在不同终端下提取出不同的 prompt / reply
- pill 摘要与任务面板副文案不一致
- 等待交互按钮在不同终端下解析结果不同

目标：

- 建立唯一的“标准化文本入口”。
- `TaskEngine`、pill、交互提取、文案展示全部只消费标准化文本。
- 原始 `tailOutput` 仅保留给底层调试与 backend 传输，不再参与上层业务逻辑。

## 方案

### 1. 引入统一标准化文本层

在 `TaskSessionTextToolkit` 增加：

- `standardizedTerminalText(from:)`

职责：

- 统一换行（CRLF / CR -> LF）
- 移除 ANSI 控制序列
- 移除控制字符（保留换行与制表）
- 统一不间断空格为普通空格
- 统一多平台终端中的特殊空白表现

### 2. 在 `CapturedTerminalSession` 上暴露标准化文本

新增只读属性：

- `standardizedTailOutput`

语义：

- 后续所有上层分析都只读这个字段。

### 3. 强制上层统一切换

以下模块禁止再直接读取 `tailOutput` 进行业务分析：

- `TaskSessionEngine`
- `ConfigurableTaskSessionStrategy`
- `TerminalSessionSignalParsing`
- `IslandView` 中 pill 摘要二次提取

统一改为：

- `session.standardizedTailOutput`
- 或 `terminalCapture.latestStatusSourceTail` 中存标准化后的 tail

### 4. 文本工具函数内部也以标准化文本为入口

`TaskSessionTextToolkit` 中以下函数统一先走标准化：

- `compactTailText`
- `extractLatestUserPrompt`
- `extractLatestReply`
- `lastErrorText`
- `interactionOptions`
- `extractInteractionPrompt`
- `composeTaskPanelSecondaryText`

这样即使有调用方误传原始文本，工具层也会收敛到同一标准。

## 结果

终端差异只留在“怎么抓到文本”这一层。
从“拿到文本之后”的所有逻辑，统一走一条标准化后的内容管线。

## 验证

1. `swift test` 全量通过。
2. 为同一可见文本构造不同终端风格的原始输入（ANSI、CRLF、NBSP、shell 残留），解析结果一致。
3. 执行 `./install-local.sh` 完成本机部署。
