# BulingIsland 设计文档：终端接入规则纳入 Codex 开发规范

## 背景与目标

项目已经形成一套稳定的跨终端接入约束：

- 不同终端可以有不同抓取能力
- 但分析、状态判定、交互提取、任务面板展示必须走统一链路
- 相同语义在不同终端中的最终呈现结果必须一致

目前这些约束散落在实现、测试和历史设计文档里，缺少一份集中、可执行的开发规则。目标是把这套规则沉淀到 `CODEX_RULES.md`，让后续新增终端后端时能按统一标准快速接入，避免再次出现 Terminal / iTerm 分叉。

## 范围

包含：

- 在 `CODEX_RULES.md` 中新增“终端接入规则”强制章节
- 明确新增终端 backend 时必须遵守的数据流、捕获、展示与测试要求

不包含：

- 修改现有 TaskEngine 行为
- 新增具体终端 backend
- 调整 UI 文案或策略 JSON

## 方案设计

### 1. 在规则文件中补齐终端接入强制规范

新增规则需明确：

- 新终端只负责“抓取文本”和“会话激活/输入”，不得在 backend 内做任务状态判定或 UI 文案拼装
- 上层业务分析必须统一基于 `CapturedTerminalSession.standardizedTailOutput`
- 不允许新增仅对某一终端生效的 prompt/reply/secondaryText 特判，除非同时沉淀到共享标准化层

### 2. 统一捕获优先级与共享脚本约束

规则中明确：

- 若终端支持 scrollback / history，应优先抓取，与现有 `iTerm2` / `Terminal.app` 保持一致
- 若 scrollback 不可用，再回退到 `contents` / `text` 等可视内容 API
- 共有捕获逻辑优先下沉到共享 helper，避免各 backend 各写一套

### 3. 强化跨终端一致性验证要求

规则中明确：

- 新增终端接入时，必须补充至少一组“与现有终端等价”的样例断言
- 断言目标不是“看起来差不多”，而是生命周期、renderTone、interactionPrompt、secondaryText 等关键渲染契约一致
- 若接入引入新的原始文本差异，必须先扩充 `TaskSessionTextToolkit` 的共享标准化，再允许上层消费

## 变更清单

- `docs/2026-04-06-terminal-integration-codex-rules-design.md`
- `CODEX_RULES.md`

## 验证方案

执行：

```bash
swift test
./install-local.sh
```

检查点：

- `CODEX_RULES.md` 已包含终端接入强制规则
- 规则覆盖捕获优先级、统一标准化入口、禁止分叉分析、跨终端一致性测试
- 本机安装脚本执行成功

## 风险与回滚方案

风险：

- 规则更严格后，后续开发需要补更多测试与设计文档，短期接入成本略有上升

回滚：

- 如需回退，仅回退本次规则文档变更，不影响现有运行时行为
