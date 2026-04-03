# Buling Island

> macOS 刘海区应用启动器 / A macOS notch-area app launcher

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

Buling Island 将 MacBook 的刘海区域变成一个控制中心：默认是快捷应用启动器，也可切换到 **Claude 面板**，在刘海下方内嵌终端会话、管理 Claude Code CLI 与（实验性）iTerm2 会话状态。点击刘海即可展开主面板，支持搜索、文件夹管理、自定义排列与多种展示模式。

Buling Island turns your MacBook's notch area into a control surface: a quick app launcher by default, plus optional **Claude panel** with an embedded terminal, Claude Code CLI workflows, and experimental iTerm2 session integration. Click the notch to expand the panel with search, folders, custom layout, and display modes.

## Download / 下载

- **DMG（v1.0.0）**: [点击下载](https://github.com/jukie-xu/buling-island/raw/main/BulingIsland_v1.0.0.dmg)

## Features / 功能

- **双模式面板 / Dual Modes** — 展开后可在 **应用** 与 **Claude** 面板间切换（顶部模式按钮）
- **刘海触发 / Notch Activation** — 点击刘海区域展开面板
- **应用搜索 / App Search** — 支持拼音首字母和模糊搜索
- **智能合并 / Smart Merge** — Launchpad 一键按用途、开发者、首字母等规则整理进文件夹，系统自带应用归入「系统实用工具」「macOS 自带应用」等分组
- **文件夹管理 / Folder Management** — 拖拽合并应用到文件夹，支持重命名和编辑
- **自定义排列 / Custom Layout** — 编辑模式下拖拽排序，布局自动持久化
- **多种展示模式 / Display Modes** — Launchpad 网格 / 字母分组 / 列表
- **动画自定义 / Custom Animations** — 可选展开与收起动画（弹性 / 快速 / 柔和等预设）
- **外观设置 / Appearance** — 自定义药丸边框颜色，支持跟随系统主题
- **收缩态信息位 / Collapsed Pill Widgets** — 左右槽位可选电量、实时网速等（设置中配置）
- **全屏时隐藏灵动岛 / Fullscreen Hide** — 可在全屏且为浏览器、播放器等场景时自动隐藏收缩态灵动岛（可开关）
- **Claude Code / 内嵌终端** — 选择工作区后启动本机 `claude` CLI（SwiftTerm 渲染），状态可反映在灵动岛底部提醒区
- **外部终端捕获（实验） / External Terminal Capture (Experimental)** — 可选轮询 **iTerm2**、经典 **iTerm**、系统 **终端 (Terminal.app)** 等已接入后端的会话缓冲，用于提醒与会话条（需在设置中开启并为「系统事件」与各终端勾选自动化）
- **开机自启 / Launch at Login** — 支持 macOS 原生自启动
- **本地化名称 / Localized Names** — 应用名称自动跟随系统语言

## Requirements / 系统要求

- macOS 13.0+
- 刘海屏 MacBook（Notch MacBook）；几何与热区依赖本机刘海布局

可选能力：

- 使用 Claude 面板需本机已安装可用的 **Claude Code CLI**（可在终端执行 `claude`）
- iTerm2 集成功能需安装 **iTerm2**（或配合系统终端的脚本路径）

## Dependencies / 依赖

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)（SwiftPM，`Package.resolve` 会在首次构建时解析）

## Build / 构建

```bash
# 仅编译并生成 BulingIsland.app / Build app bundle only
./build.sh

# 编译并打包 DMG / Build DMG installer
./build-dmg.sh

# 执行单元测试 / Run unit tests
swift test

# 本地开发：结束旧进程 → 构建 → 安装到 /Applications 并启动（见仓库根目录脚本）
./install-local.sh
```

## Codex Development Rules / Codex 开发规范

- 每次完成功能代码修改后，必须重新执行 `/Users/jukie/git/buling-island/install-local.sh`，将最新构建安装部署到本机。
- 若脚本执行失败，需先修复失败原因，再继续后续验证与提交流程。

构建产物：

- `BulingIsland.app` — 可直接运行的应用
- `dist/BulingIsland_v*.dmg` — 运行 `build-dmg.sh` 后生成的 DMG（具体版本号以脚本产出为准）

## Install / 安装

### 发行包 / Release

若有提供的 DMG：双击打开，将 `BulingIsland.app` 拖入 **应用程序 (Applications)**。

### 从源码安装 / Build from source

```bash
git clone https://github.com/jukie-xu/buling-island.git
cd buling-island
./build.sh
cp -R BulingIsland.app /Applications/
open /Applications/BulingIsland.app
```

开发调试可直接使用 `./install-local.sh`（会先 `killall BulingIsland` 再覆盖安装并打开）。

## Usage / 使用

1. 启动后应用在后台运行（无 Dock 图标）
2. 点击刘海区域展开面板
3. 在应用模式下：长按应用图标进入编辑模式；编辑模式下拖拽排序或合并为文件夹
4. 使用 Launchpad 工具栏中的整理能力（含「一键智能合并」）可快速分组
5. 切换到 Claude 模式：选择工作区、按需启动会话；可在设置中配置提醒与 iTerm2 实验选项
6. 右键菜单栏托盘图标或在设置侧边栏底部退出应用

首次运行可能需要在 **系统设置 → 隐私与安全性 → 辅助功能**（及相关自动化/屏幕录制权限，视功能而定）中为 Buling Island 授权。

## Project Structure / 项目结构

```
.
├── Package.swift                    # SPM 配置（含 SwiftTerm）
├── build.sh                        # 构建脚本
├── build-dmg.sh                    # DMG 打包脚本
├── install-local.sh                # 本地杀进程、安装、启动
├── AppIcon.icns                    # 应用图标
└── Sources/
    ├── AppDelegate.swift           # 应用入口 & ViewModel
    ├── BulingIslandApp.swift      # SwiftUI App
    ├── NotchDetector.swift         # 刘海区域检测
    ├── NSScreen+Island.swift       # 屏幕 / 刘海几何扩展
    ├── PanelManager.swift          # 面板窗口管理
    ├── Models/                     # 数据模型（应用、文件夹、动画、展示模式、信息位等）
    ├── Services/
    │   ├── AppDiscoveryService     # 应用发现
    │   ├── AppSearchService        # 搜索服务
    │   ├── FolderManager           # 文件夹管理
    │   ├── FolderLayoutEngine      # Launchpad 纯布局规则引擎
    │   ├── SettingsManager         # 设置管理
    │   ├── SettingsSchema          # 设置键/默认值 schema
    │   ├── ClaudeCLIService        # Claude CLI 检测与状态
    │   ├── TaskEngine/             # 任务引擎：状态机 + 可插拔策略（Claude/Codex/Generic）
    │   ├── TerminalIntegration/    # 外部终端捕获：通用协议 + 各终端后端 + 聚合服务
    │   ├── PillHudViewModel        # 收缩态 HUD / 热区
    │   ├── BatteryPowerReader      # 电量读取
    │   ├── NetworkThroughputReader # 网速读取
    │   └── FullscreenCollapsedPillAutoHider
    └── Views/
        ├── IslandView              # 主视图（灵动岛形态与展开内容）
        ├── LaunchpadGridView       # Launchpad 网格
        ├── AlphabetGridView        # 字母分组
        ├── AppGridView / AppItemView
        ├── FolderView              # 文件夹浮层
        ├── SearchBarView
        ├── SettingsView            # 设置（含 Claude 独立页签）
        ├── ClaudeTerminalView      # 内嵌终端（SwiftTerm）
        └── PanelModeIcons.swift    # 模式切换图标
```

## Architecture Analysis / 架构分析（2026-04-02）

### Current Architecture / 当前架构

- **UI Layer (SwiftUI + AppKit Bridge)**  
  `IslandView` 负责收缩/展开态、三面板切换（应用/Claude/任务）、状态提示、交互动画；`PanelManager` 负责 `NSPanel` 生命周期、跨桌面层级、点击监控与热区同步。
- **State Layer (ViewModel + Settings)**  
  `IslandViewModel` 维护主状态（展开态、搜索、应用列表、目标面板路由）；`SettingsManager` 负责设置项与 `UserDefaults` 持久化、交互配置广播。
- **Domain Services / 功能服务层**  
  应用发现(`AppDiscoveryService`)、搜索(`AppSearchService`)、文件夹布局(`FolderManager`)、Claude CLI 检测(`ClaudeCLIService`)、终端会话捕获(`TerminalCaptureService`)。
- **Platform Integration / 系统集成层**  
  刘海几何检测(`NotchDetector`)、全屏自动隐藏(`FullscreenCollapsedPillAutoHider`)、AppleScript 终端桥接（iTerm2/iTerm/Terminal）。
- **Build & Distribution / 构建分发**  
  SwiftPM 主构建链，`build.sh` 组装 `.app`，`build-dmg.sh` 产出 DMG。

### Data Flow / 核心数据流

1. App 启动：`AppDelegate` 创建 `IslandViewModel` 与 `PanelManager`。  
2. 状态刷新：`IslandViewModel` 扫描应用 + 文件夹监听，更新 `allApps`。  
3. UI 响应：`IslandView` 订阅设置、CLI、终端捕获状态，驱动灵动岛与面板。  
4. 系统行为：`PanelManager` 同步窗口层级、点击监听、收缩热区。  
5. 持久化：`SettingsManager`（UserDefaults）与 `FolderManager`（Application Support JSON）。

### Architectural Strengths / 架构优点

- 模块边界基本清晰：`Models / Services / Views` 分层明确。
- 高风险系统集成（AppleScript/窗口层级）已封装到独立服务。
- 对冷启动和目录抖动有防护（应用扫描 debounce、布局自愈与去重）。

### Architectural Risks / 架构风险

- `IslandView` 逻辑体量较大（状态监听、业务规则、动画耦合），后续维护成本高。
- `SettingsManager` 作为全局单例承载大量职责，缺少“配置 schema + 迁移策略”。
- 当前无自动化测试目标（`swift test` 报 `no tests found`），回归风险主要靠人工验证。

## Bug Check / 功能 Bug 检查

本次检查方式：

- 静态代码审查（核心入口、状态流、终端捕获、全屏隐藏、布局管理）。
- 构建验证：`swift build`（通过）。
- 测试验证：`swift test`（失败原因为无 `Tests` 目标，并非编译错误）。

### Confirmed Issue / 已确认问题

1. **通知监听释放不对称，存在重复监听/泄漏风险**  
   `FullscreenCollapsedPillAutoHider.stop()` 中统一用 `NotificationCenter.default.removeObserver` 移除 token，但部分 token 实际由 `NSWorkspace.shared.notificationCenter` 注册。  
   影响：反复 `start/stop` 或生命周期重建时，可能导致重复回调、隐藏逻辑抖动、资源泄漏。

### Potential Issues / 潜在问题（建议回归验证）

1. **应用唯一标识冲突风险**  
   `AppInfo.id` 主要使用 `bundleIdentifier`；当用户存在多个同 bundle 应用副本时，布局与文件夹可能出现“同 ID 覆盖/错位”行为。  
2. **终端捕获轮询成本偏高**  
   轮询 + AppleScript 读取多会话全文尾窗，活动会话多时 CPU 抖动可能明显（尤其低电量场景）。
3. **单体 View 的回归面大**  
   `IslandView` 内大量 `onChange/onReceive` 串联，新增功能时容易引入状态联动回归。

## Optimization Plan / 优化精简升级建议

### 1) Architecture Optimization / 架构设计优化

- 将 `IslandView` 拆分为 3 个 Feature 模块：`AppPanelFeature`、`ClaudePanelFeature`、`TaskPanelFeature`。
- 引入统一事件层（轻量 reducer 或 action dispatcher），将跨面板联动从 View 事件回调迁出。
- 为 `SettingsManager` 增加版本化配置结构（如 `SettingsSnapshot v1/v2` + migration）。
- 终端捕获后端抽象继续下沉：统一 `PollingPolicy`（前台快轮询/后台慢轮询/静默停轮询）。

### 2) Feature Optimization / 功能优化

- 新增“性能模式”：低电量或高负载时自动降低终端轮询频率。
- 为任务面板增加过滤与折叠（仅异常、仅活跃、按来源终端）。
- 增加首次运行引导页：权限状态（辅助功能/自动化）逐项检测 + 一键跳转设置。
- 搜索增强：支持权重排序（最近使用优先、拼音命中权重、前缀命中优先）。

### 3) Quality & Testability / 质量与可测试性

- 建立 `Tests/`：先覆盖 `FolderManager`、`AppSearchService`、`TerminalOutputStatusAnalyzer`。
- 加入最小自动化门禁：`swift build` + `swift test` + 基本格式/静态检查。
- 对关键状态流增加日志分级（debug/info/warn/error）与 session trace ID，便于排查联动问题。

## Can It Be Simplified & Upgraded? / 是否可以优化精简升级

可以，且建议采用“**保功能、先收敛复杂度**”的渐进升级策略：

1. **Phase 1（1~2 天）**：修复确认 bug、补齐基础单元测试目标、建立最小自动化门禁。  
2. **Phase 2（3~5 天）**：拆分 `IslandView` 到三面板 Feature，抽离共享状态与事件。  
3. **Phase 3（3~5 天）**：优化终端捕获轮询策略 + 权限引导 + 任务面板可用性增强。  
4. **Phase 4（持续）**：性能基线（CPU/内存）与崩溃/异常日志闭环。

预期收益：

- 代码复杂度下降，新增功能改动面更小。
- 回归风险降低（可测试路径增加）。
- 多终端场景下性能与稳定性更可控。

## Changelog / 更新日志

详见 [CHANGELOG.md](CHANGELOG.md)。

## Author / 作者

- **jukie.xu**
- **Email**: `jukiexu@icloud.com`

## Copyright / 著作权

© 2026 jukie.xu.  
本项目源代码、界面与相关文档等内容受著作权法及相关法律保护。

## Disclaimer / 免责声明

本软件按“现状（AS IS）”提供，不提供任何明示或暗示担保。作者不对因使用或无法使用本软件所产生的任何直接或间接损失承担责任，包括但不限于数据丢失、业务中断、收益损失等。

与系统自动化、辅助功能、终端集成等能力相关的行为可能受系统权限、软件版本与环境差异影响，作者不保证在所有环境下均可用或结果一致。

## Privacy / 隐私说明（简版）

- 本软件不以收集个人身份信息为目的。
- 若你启用了与系统交互相关的权限（如辅助功能、自动化），这些权限仅用于实现对应功能；本软件不以此为目的读取键盘输入内容或收集输入内容。
- 本地保存的设置与布局数据仅用于功能运行。

## Third-Party / 第三方声明

本项目可能包含第三方开源组件，其著作权归原作者所有，并受各自许可证约束；详见依赖清单与其许可证文件。

## License / 许可

本项目采用 **MIT License** 开源发布。许可证全文见 [`LICENSE`](LICENSE)。
