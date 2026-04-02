# Buling Island

> macOS 刘海区应用启动器 / A macOS notch-area app launcher

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

Buling Island 将 MacBook 的刘海区域变成一个控制中心：默认是快捷应用启动器，也可切换到 **Claude 面板**，在刘海下方内嵌终端会话、管理 Claude Code CLI 与（实验性）iTerm2 会话状态。点击刘海即可展开主面板，支持搜索、文件夹管理、自定义排列与多种展示模式。

Buling Island turns your MacBook's notch area into a control surface: a quick app launcher by default, plus optional **Claude panel** with an embedded terminal, Claude Code CLI workflows, and experimental iTerm2 session integration. Click the notch to expand the panel with search, folders, custom layout, and display modes.

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
- **全屏时隐藏 pill / Fullscreen Hide** — 可在全屏且为浏览器、播放器等场景时自动隐藏收缩态 pill（可开关）
- **Claude Code / 内嵌终端** — 选择工作区后启动本机 `claude` CLI（SwiftTerm 渲染），状态可反映在 pill 底部提醒区
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

# 本地开发：结束旧进程 → 构建 → 安装到 /Applications 并启动（见仓库根目录脚本）
./install-local.sh
```

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
    │   ├── SettingsManager         # 设置管理
    │   ├── ClaudeCLIService        # Claude CLI 检测与状态
    │   ├── TerminalIntegration/    # 外部终端捕获：通用协议 + 各终端后端 + 聚合服务
    │   ├── PillHudViewModel        # 收缩态 HUD / 热区
    │   ├── BatteryPowerReader      # 电量读取
    │   ├── NetworkThroughputReader # 网速读取
    │   └── FullscreenCollapsedPillAutoHider
    └── Views/
        ├── IslandView              # 主视图（pill 形态与展开内容）
        ├── LaunchpadGridView       # Launchpad 网格
        ├── AlphabetGridView        # 字母分组
        ├── AppGridView / AppItemView
        ├── FolderView              # 文件夹浮层
        ├── SearchBarView
        ├── SettingsView            # 设置（含 Claude 独立页签）
        ├── ClaudeTerminalView      # 内嵌终端（SwiftTerm）
        └── PanelModeIcons.swift    # 模式切换图标
```

## Changelog / 更新日志

详见 [CHANGELOG.md](CHANGELOG.md)。

## License / 许可

MIT
