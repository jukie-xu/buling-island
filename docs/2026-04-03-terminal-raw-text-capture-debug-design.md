# BulingIsland 设计文档：Terminal 原始文本抓取排查

## 背景与目标

当前 `Terminal.app` 中明明运行的是 Codex，会话却被识别为 `Generic TUI`。继续只看 UI 结果没有意义，必须直接抓取 Terminal backend 实际获得的原始文本。

目标：

- 直接拿到当前 `Terminal.app` 会话的 `contents`
- 同时拿到同一会话的 `history`
- 对照当前 UI 看到的内容，确认 backend 实际拿到了什么
- 基于真实原文决定后续修复方案

## 范围

包含：

- 使用 AppleScript 直接读取当前 Terminal 窗口/标签页的 `contents` 与 `history`
- 汇总差异
- 如确认问题在抓取层，再继续修复 backend

不包含：

- 先入为主地修改 TaskEngine / UI

## 方案设计

1. 直接对 Terminal 当前活动标签执行 AppleScript
2. 同时输出：
   - window name
   - custom title
   - tty
   - `contents`
   - `history`
3. 对比：
   - 哪个字段包含 `OpenAI Codex`
   - 哪个字段只包含 shell / prompt
   - 当前 backend 是否选错了源

## 变更清单

- `docs/2026-04-03-terminal-raw-text-capture-debug-design.md`

如确认问题，再继续改：

- `Sources/Services/TerminalIntegration/AppleTerminalSessionCaptureBackend.swift`

## 验证方案

- 成功抓到当前 Terminal 会话的 `contents/history`
- 能明确解释为什么当前会被识别成 `Generic TUI`

## 风险与回滚方案

风险：

- AppleScript 访问 Terminal 需要系统权限

回滚：

- 本次仅做排查，不涉及运行时功能回滚
