# Task Strategy Config

任务状态判定支持按 TUI 程序拆分为独立规则文件。

## 规则文件位置

- 内置默认规则（随应用打包）：`Sources/Configs/TaskStrategies/*.json`
- 用户自定义覆盖目录：`~/Library/Application Support/BulingIsland/TaskStrategies/*.json`

加载顺序：先加载内置规则，再加载用户目录；同 `strategyID` 时后加载会覆盖先加载。

## 最小示例

```json
{
  "strategyID": "my-tui",
  "displayName": "My TUI",
  "priority": 220,
  "supports": {
    "titleContains": ["my tui"],
    "titleRegex": [],
    "tailContains": ["my-tui"],
    "tailRegex": []
  },
  "lifecycleRules": {
    "error": { "titleContains": [], "titleRegex": [], "tailContains": ["error"], "tailRegex": [] },
    "waitingInput": { "titleContains": [], "titleRegex": [], "tailContains": ["approve"], "tailRegex": [] },
    "running": { "titleContains": [], "titleRegex": [], "tailContains": ["running"], "tailRegex": [] },
    "success": { "titleContains": [], "titleRegex": [], "tailContains": ["done"], "tailRegex": [] }
  },
  "defaultLifecycle": "idle",
  "emptyOutput": {
    "lifecycle": "idle",
    "renderTone": "neutral",
    "secondaryText": "当前未运行任务"
  },
  "extraction": {
    "fallbackText": "暂无可展示输出",
    "fallbackMaxLength": 88,
    "byLifecycle": {
      "idle": { "mode": "truncateCompact", "maxLength": 88 },
      "running": { "mode": "promptAndReply" },
      "waitingInput": { "mode": "promptAndReply" },
      "success": { "mode": "promptAndReply" },
      "error": { "mode": "promptAndError" }
    }
  }
}
```

## 可用值

- `defaultLifecycle`: `inactiveTool | idle | running | waitingInput | success | error`
- `emptyOutput.renderTone`: `neutral | running | warning | success | error | inactive`
- `extraction.byLifecycle.<state>.mode`:
  - `promptAndReply`：提取“最近提问 + 最近回复”两行
  - `promptAndError`：提取“最近提问 + 最近错误”两行
  - `truncateCompact`：压缩尾输出并截断
  - `compact`：压缩尾输出，不截断
  - `fixedText`：固定文案（需提供 `text`）
