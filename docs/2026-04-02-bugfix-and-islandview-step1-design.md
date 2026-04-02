# BulingIsland 设计文档：Bug 修复 + IslandView 三分拆（第一步）

- 日期：2026-04-02
- 作者：Codex
- 关联需求：
  - 修复已发现 bug
  - 将 `IslandView` 拆分成 3 个 feature 子视图（第一步）
  - 后续功能开发先在 `docs/` 落设计再实现

## 1. 背景与目标

当前 `IslandView` 承载应用面板、Claude 面板、任务面板三类 UI 逻辑，代码体量较大。已确认存在至少一处真实 bug（监听释放不对称），另有应用 ID 冲突风险（同 bundle 多副本时可能覆盖/错位）。

本次目标：

1. 修复所有已发现且可直接落地的 bug。
2. 对 `IslandView` 做“第一步拆分”：把三类面板 UI 提炼为三个 feature 子视图，降低主文件复杂度。
3. 不改变用户可见行为，不引入新设置项，不改动持久化格式（除 ID 冲突修复所需的兼容逻辑）。

## 2. 范围

### 2.1 In Scope

- BugFix-A：修复 `FullscreenCollapsedPillAutoHider` 的 observer 移除中心不匹配问题。
- BugFix-B：修复应用唯一 ID 在同 bundle 多副本场景下冲突的问题（保留向后兼容策略）。
- Refactor-Step1：新增三个 feature 子视图文件，并将 `IslandView` 展开态 `switch` 主体切换到子视图承载。
- 构建验证：`swift build`。

### 2.2 Out of Scope

- 不做完整架构重写（如 reducer 全面落地）。
- 不新增自动化门禁或单元测试目标（下一阶段）。
- 不调整视觉交互与业务规则。

## 3. 详细设计

## 3.1 BugFix-A：Fullscreen 自动隐藏监听释放修复

### 问题描述

`start()` 中同时向两个通知中心注册：
- `NotificationCenter.default`
- `NSWorkspace.shared.notificationCenter`

但 `stop()` 中统一从 `NotificationCenter.default` 移除 token，导致一部分 observer 释放不正确。

### 设计方案

- 将 `tokens: [NSObjectProtocol]` 改为 `observerTokens: [(center: NotificationCenter, token: NSObjectProtocol)]`。
- 注册时记录对应 `center`。
- 停止时按原 `center.removeObserver(token)` 成对释放。

### 风险与兼容

- 无行为变化，仅资源管理修复。

## 3.2 BugFix-B：App 唯一标识冲突修复

### 问题描述

`AppInfo.id` 主要使用 `bundleIdentifier`。同 bundle 多副本（如多个路径安装）时会出现 ID 冲突，影响布局/文件夹映射正确性。

### 设计方案

在 `AppDiscoveryService.discoverApps()` 中引入“稳定且兼容”的 ID 生成策略：

1. 先收集候选应用（bundleID/path/name/icon）。
2. 按 bundleID 计数。
3. 若 bundleID 唯一：保持旧行为 `id = bundleID`。
4. 若 bundleID 重复：
   - 按路径排序，首个仍用 `bundleID`（尽量兼容历史布局）
   - 其余副本用 `"\(bundleID)|\(path)"` 生成稳定唯一 ID。
5. 无 bundleID 时仍用 `path`。

### 风险与兼容

- 重复 bundle 场景下，旧版本本就无法稳定区分，现版本将可区分。
- 保留首副本的旧 ID，最大化兼容已有布局。

## 3.3 Refactor-Step1：IslandView 三 feature 子视图

### 目标

将展开态三种模式的 UI 容器拆成独立子视图，降低 `IslandView` 复杂度。

### 子视图拆分

- `AppPanelFeatureView`
  - 负责搜索栏 + Grid/Alphabet/Launchpad 显示逻辑。
- `ClaudePanelFeatureView`
  - 负责“保持会话 host 常驻”逻辑下的展示层与交互层。
- `TaskPanelFeatureView`
  - 负责任务面板容器布局（padding 与 content 承载）。

### 集成方式

- 在 `IslandView` 保留业务状态与回调，子视图通过参数接收数据与闭包。
- 先做 View 级拆分，不改状态机和服务调用链。

### 风险与兼容

- 纯重构，目标是行为等价。
- 用 `swift build` 做编译回归。

## 4. 实施步骤

1. 修改 `FullscreenCollapsedPillAutoHider` observer 管理。
2. 修改 `AppDiscoveryService` 应用 ID 生成逻辑。
3. 新增三个 feature 子视图文件。
4. 改造 `IslandView` 展开态 switch 使用新子视图。
5. 执行 `swift build` 验证。

## 5. 验收标准

- `swift build` 成功。
- 全屏自动隐藏相关逻辑无编译告警，observer 移除逻辑成对。
- `IslandView` 展开态三分支已使用独立 feature 子视图承载。
- 应用发现在同 bundle 多副本场景下能生成唯一 ID（并保留首副本兼容 ID）。

## 6. 回滚策略

- 若出现行为回归，优先回滚 `IslandView` 子视图拆分（保持 bugfix）。
- 若 ID 兼容问题超预期，可临时切回旧 ID 策略并在下一版引入迁移脚本。

## 7. 后续约定（流程）

后续所有新功能建设或 TODO plan，先在 `docs/` 编写详细设计文档（目标、范围、设计、验收）并评审，再进入实现阶段。
