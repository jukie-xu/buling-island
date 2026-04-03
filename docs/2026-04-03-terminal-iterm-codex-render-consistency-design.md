# BulingIsland 设计文档：Terminal / iTerm 的 Codex 渲染一致性修复

## 背景与目标

当前同样是 Codex 会话，`iTerm` 能被识别为 `Codex`，但 `Terminal.app` 会掉到 `Generic TUI`。这会导致：

- 策略不一致
- 副文案不一致
- 同类会话在不同终端中呈现不同渲染效果

从现象看，`Terminal` 与 `iTerm` 的原始尾部内容几乎一致，差异不应出现在策略层。需要修复文本清洗规则，使两者在进入策略层后得到一致的有效文本。

## 范围

包含：

- 修复 `>_ OpenAI Codex (...)` 被误判为用户输入的问题
- 为 Terminal / iTerm 的 Codex 等价样例新增测试
- 确保策略识别、状态、面板副文案在两类样例上保持一致

不包含：

- 修改终端捕获 backend 的宿主脚本
- 修改非 Codex 相关的 Claude 规则

## 方案设计

### 1. 修正用户输入行判定

当前 `TaskSessionTextToolkit.isUserInputCommandLine(_:)` 将所有以 `>` 开头的行都视为用户输入。

这会误伤：

- `>_ OpenAI Codex (v0.118.0)` 顶部 banner

修正策略：

- 仅把真实输入前缀识别为用户输入
- `>` 只在后面是空白时视为输入提示
- `>_` 这类 TUI banner 前缀不再视为用户输入

### 2. 新增 Terminal / iTerm 等价样例测试

新增测试覆盖两种样例：

- `Terminal` 风格 Codex 初始界面 + 输入
- `iTerm` 风格 Codex 初始界面 + 输入

断言内容：

- 都命中 `codex` 策略
- 生命周期一致
- `TaskSessionSnapshot.secondaryText` 第一行都取用户输入
- 不会再把 Terminal 样例误判成 `Generic TUI`

### 3. 将该问题纳入一致性测试体系

这类“终端差异只在宿主 UI，不应影响策略结果”的场景，纳入后续固定测试资产，与 `rela/` 真实样例共同约束解析质量。

## 变更清单

- `docs/2026-04-03-terminal-iterm-codex-render-consistency-design.md`
- `Sources/Services/TaskEngine/TaskSessionTextToolkit.swift`
- `Tests/BulingIslandTests/TaskSessionTextToolkitTests.swift`
- `Tests/BulingIslandTests/RelaFixtureConsistencyTests.swift`（如需要补充等价断言）

## 验证方案

执行：

```bash
swift test
./install-local.sh
```

重点验证：

- Terminal 风格 Codex 文本不再落到 `Generic TUI`
- Terminal / iTerm 样例在策略与渲染结果上保持一致

## 风险与回滚方案

风险：

- `>` 输入前缀收紧后，可能影响某些极少见的纯 `>` 风格 prompt 识别

回滚：

- 若出现回归，只回退 `isUserInputCommandLine` 判定与新增测试
- 不影响统一标准化文本层与 `rela/` 回归体系
