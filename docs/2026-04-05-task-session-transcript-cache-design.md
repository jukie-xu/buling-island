# BulingIsland 设计文档：终端 Session Transcript Cache

## 背景

当前外部终端任务链路主要依赖每轮抓到的 `tailOutput` 直接做状态分析与 prompt 提取，存在两个问题：

1. 终端后端通常只能稳定拿到“尾部窗口”，旧内容会滚出可见范围，导致最后一次真实用户提问丢失
2. 缺少按 session 的增量归并层，每次只能对整段尾部重新分析，无法区分“新增输出”和“底部输入框占位内容”

## 目标

新增一层按 session 维护的 transcript cache，满足：

- 持续归并各轮抓到的终端尾部文本
- 计算本轮相对上一轮的增量内容
- 缓存每个 session 最后一次真实提交的用户 prompt
- 热路径以内存为主，磁盘仅做冷恢复持久化

## 方案

### 1. 双层缓存

- 内存：`TaskSessionTranscriptCache.entries`
  - 每轮刷新直接读取/更新，避免频繁磁盘 IO
- 磁盘：`~/Library/Application Support/BulingIsland/task-session-transcripts.json`
  - 仅保存轻量元数据与裁剪后的归并尾部
  - 作为 app 重启后的冷启动恢复

### 2. 每个 session 记录

- `lastSeenTail`
- `mergedTail`
- `latestSubmittedPrompt`
- `updatedAt`

### 3. 增量归并

- 基于“上一轮尾部 suffix”与“当前尾部 prefix”的最长行重叠做合并
- 有重叠时只追加增量行
- 明显 reset / clear 时重置为当前尾部
- 对 `mergedTail` 做最大行数裁剪，控制内存与文件体积

### 4. prompt 提取策略

- 优先从本轮增量中提取真实用户 prompt
- 提取失败时，再从当前尾部提取
- 若仍失败，回退到已缓存的 `latestSubmittedPrompt`
- 这样可以跳过 Codex / Claude 底部输入框里的占位建议，同时保留真正已提交任务

## 性能考虑

- 每轮轮询只在内存里做字符串/行级处理
- 仅在 entry 变化时标记 dirty，并在 refresh 结束后统一落盘
- 磁盘文件按 session 裁剪 `mergedTail`，避免无限增长

## 验证

- transcript cache 增量归并测试
- prompt 缓存跨轮询保持测试
- 文件持久化 round-trip 测试
- 既有任务面板与跨终端 contract 测试继续通过
