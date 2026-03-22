# Buling Island

> macOS 刘海区应用启动器 / A macOS notch-area app launcher

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

Buling Island 将 MacBook 的刘海区域变成一个快捷应用启动器。点击刘海即可展开应用面板，支持搜索、文件夹管理和自定义排列。

Buling Island turns your MacBook's notch area into a quick app launcher. Click the notch to reveal the app panel with search, folder management, and custom layout.

## Features / 功能

- **刘海触发 / Notch Activation** — 点击刘海区域展开应用面板
- **应用搜索 / App Search** — 支持拼音首字母和模糊搜索
- **文件夹管理 / Folder Management** — 拖拽合并应用到文件夹，支持重命名和编辑
- **自定义排列 / Custom Layout** — 编辑模式下拖拽排序，布局自动持久化
- **多种展示模式 / Display Modes** — Launchpad 网格 / 字母分组 / 列表
- **动画自定义 / Custom Animations** — 可选展开和收起动画效果
- **外观设置 / Appearance** — 自定义药丸边框颜色，支持跟随系统主题
- **开机自启 / Launch at Login** — 支持 macOS 原生自启动
- **本地化名称 / Localized Names** — 应用名称自动跟随系统语言

## Requirements / 系统要求

- macOS 13.0+
- MacBook with notch (刘海屏 MacBook)

## Build / 构建

```bash
# 编译并打包 .app / Build app bundle
./build.sh

# 编译并打包 .dmg / Build DMG installer
./build-dmg.sh
```

构建产物：
- `BulingIsland.app` — 可直接运行的应用
- `dist/BulingIsland_vX.X.X.dmg` — DMG 安装包

## Install / 安装

### 从 DMG 安装 / Install from DMG

1. 打开 DMG 文件
2. 拖拽 `BulingIsland.app` 到 `Applications` 文件夹
3. 首次启动需要授权辅助功能权限

### 从源码构建 / Build from source

```bash
git clone https://github.com/jukie-xu/buling-island.git
cd buling-island
./build.sh
cp -r BulingIsland.app /Applications/
open /Applications/BulingIsland.app
```

## Usage / 使用

1. 启动后应用在后台运行（无 Dock 图标）
2. 点击刘海区域展开应用面板
3. 长按应用图标进入编辑模式
4. 编辑模式下拖拽图标排序或合并为文件夹
5. 右键托盘图标或在设置中退出应用

## Project Structure / 项目结构

```
.
├── Package.swift          # SPM 配置
├── build.sh               # 构建脚本
├── build-dmg.sh           # DMG 打包脚本
├── AppIcon.icns           # 应用图标
└── Sources/
    ├── AppDelegate.swift          # 应用入口 & ViewModel
    ├── BulingIslandApp.swift      # SwiftUI App
    ├── NotchDetector.swift        # 刘海区域检测
    ├── PanelManager.swift         # 面板窗口管理
    ├── Models/                    # 数据模型
    ├── Services/                  # 业务服务
    │   ├── AppDiscoveryService    # 应用发现
    │   ├── AppSearchService       # 搜索服务
    │   ├── FolderManager          # 文件夹管理
    │   └── SettingsManager        # 设置管理
    └── Views/                     # UI 视图
        ├── IslandView             # 主视图
        ├── LaunchpadGridView      # Launchpad 网格
        ├── FolderView             # 文件夹浮层
        └── SettingsView           # 设置面板
```

## License / 许可

MIT
