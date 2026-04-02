# BulingIsland 设计文档：Pill 左右信息位贴边 + 设置页控制台美化

日期：2026-04-02

## 1. 背景与目标

用户反馈两点体验问题：

1) **收缩态灵动岛左右信息位“离刘海两竖边太远”**  
当左/右槽位配置为电量或实时网速时，内容与刘海的垂直边缘（notch vertical edge）之间留白偏大，视觉上不够“贴边”，显得松散。

2) **设置页（控制台）视觉不够精致**  
虽然功能完整，但行/卡片的对齐、分组一致性与信息层级仍显粗糙，需要进一步打磨成更接近 macOS Settings 的质感。

目标：

- 将左右信息位向刘海竖边**更靠近**（减少内侧留白），同时保证不“贴死”硬件边缘、保持可读性。
- 优化控制台设置卡片的视觉层级与对齐，减少“空/散/丑”的观感。

## 2. 范围

### In Scope

- 调整 `PillLayout.contentInsetFromNotchEdge`（影响收缩态左右信息位的“离刘海竖边距离”）。
- 重做 `SettingsDashboardTab` 中“常规”卡片的布局，把“两个开关 + 默认展开面板分段控件”收敛成一致的分组行风格。

### Out of Scope

- 不修改 `pillSideSlotWidth` 的默认值与设置项含义（仅调整内容在槽位内的靠边程度）。
- 不改动收缩态灵动岛的总宽计算与点击热区逻辑（`PanelManager` 依旧使用 `PillLayout.totalWidth`）。
- 不在本次改动主题配色系统与全局 UI 风格（仅针对控制台页做精修）。

## 3. 详细设计

### 3.1 左右信息位更靠近刘海竖边

现状：

- `IslandView.pillOneSide` 使用：
  - `innerPad = PillLayout.notchAdjacentGap + PillLayout.contentInsetFromNotchEdge`
  - 并对左右分别做 `.padding(.trailing/.leading, innerPad)`
- `PillLayout.contentInsetFromNotchEdge` 当前为固定值（偏大），导致内容离 notch edge 远。

方案：

- 将 `PillLayout.contentInsetFromNotchEdge` 从 `6` 调整为 `3`（保留 `notchAdjacentGap` 作为硬件边缘“留缝”）。
- 保持 `notchAdjacentGap = 2` 不变，避免内容贴死硬件裁切边缘。

预期效果：

- 电量/网速在左右翼内更靠近刘海竖边，整体更“紧凑贴边”。
- 仍保留 2px 的硬件边缘留缝，避免视觉压迫。

### 3.2 设置页控制台美化（常规卡片）

现状问题（从截图观感）：

- “常规”卡片内部存在“组内组外”的不一致：开关在一个 rounded group 内，但“默认展开面板”分段控件在外部，导致布局松散、视觉不统一。

方案：

- 将“默认展开面板”也纳入同一个 rounded group，形成三行一致的设置行：
  - 行 1：全屏时隐藏灵动岛（Toggle）
  - 行 2：开机启动（Toggle）
  - 行 3：默认展开面板（Segmented Picker）
- 统一行左右对齐、行间分隔线风格；减少卡片内部的“漂浮感”。

## 4. 验收标准（Checklist）

- [ ] 收缩态灵动岛左右信息位（电量/网速）明显更靠近刘海竖边，视觉更紧凑。
- [ ] 不出现内容贴死硬件边缘的压迫感（仍有细小留缝）。
- [ ] 设置页控制台的“常规”卡片中：两行开关与分段控件在同一分组容器内，视觉一致、对齐更好。

## 5. 风险与回滚策略

- 风险：内侧留白缩小后，极端字体缩放/不同语言下可能略显拥挤。
  - 回滚：将 `contentInsetFromNotchEdge` 调回 `6` 或折中到 `4`。

## 6. 实施步骤

- 更新 `Sources/Views/PillLayout.swift`：调整 `contentInsetFromNotchEdge` 常量。
- 更新 `Sources/Views/SettingsView.swift`：重排 `SettingsDashboardTab.generalQuickTogglesCard` 内部结构。
- 本地验证：`swift build` + `./install-local.sh` 安装启动后人工观察收缩态与设置页。

