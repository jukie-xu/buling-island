# BulingIsland 设计文档：Terminal.app 可见内容优先抓取修复

## 背景与目标

当前 `Terminal.app` 中的 Codex 会话仍然可能被识别成 `Generic TUI`，而同类 `iTerm` 会话可正确识别为 `Codex`。

结合现象，问题不只在文本清洗层，还在更前面的 Terminal 抓取层：

- `AppleTerminalSessionCaptureBackend` 目前优先读取 `history of tab`
- 对全屏 / 半全屏 TUI（如 Codex）来说，`history` 往往只保留 shell 与部分滚动缓冲，不等于当前可见内容
- 结果是 `Terminal` 后端上送到上层的文本，可能缺少 `OpenAI Codex`、`/model to change`、底部模型脚注等关键标识

这会导致即使后续清洗和策略完全统一，也无法得到和 `iTerm` 一致的分类结果。

目标：

- Terminal 会话优先抓取“当前可见内容”
- 当可见内容不可用时再回退 `history`
- 尽量缩小 `Terminal` 与 `iTerm` 在原始文本上的差异

## 范围

包含：

- 调整 `AppleTerminalSessionCaptureBackend` 文本源优先级
- 保留回退策略，避免背景标签页完全无内容
- 配合现有统一标准化文本层与一致性测试继续验证

不包含：

- 修改 iTerm / iTerm2 backend
- 修改 TaskEngine 或 UI 结构

## 方案设计

### 1. Terminal 文本源优先级调整

当前：

- `history` 优先
- `contents` 回退

改为：

- `contents` 优先
- `history` 回退

理由：

- `contents` 更接近当前屏幕可见状态
- `history` 更适合作为缺省兜底，而不是 TUI 主抓取源

### 2. 兼容性策略

若 `contents` 为空或不可用：

- 仍然回退到 `history`

这样可以兼容：

- 非前台标签页
- 某些 Terminal 状态下 `contents` 缺失的情况

## 变更清单

- `docs/2026-04-03-terminal-visible-content-priority-design.md`
- `Sources/Services/TerminalIntegration/AppleTerminalSessionCaptureBackend.swift`

## 验证方案

执行：

```bash
swift test
./install-local.sh
```

并重点复测：

- 同一 Codex 会话在 `Terminal.app` 与 `iTerm` 中是否都能落到 `Codex`
- Terminal 不再只展示用户输入，而是能识别到 Codex 上下文

## 风险与回滚方案

风险：

- 背景标签页在 `contents` 下可能拿到较少内容

缓解：

- 保留 `history` 回退

回滚：

- 仅回滚 `AppleTerminalSessionCaptureBackend` 中文本源优先级调整
