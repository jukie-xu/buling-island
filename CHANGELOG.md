# Changelog

All notable changes to **Buling Island**（不灵灵动岛）are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

版本字段与 macOS 包体对应关系：

| 概念 | Info.plist 键 | 约定 |
|------|----------------|------|
| 面向用户的版本号 | `CFBundleShortVersionString` | `MAJOR.MINOR.PATCH`（SemVer） |
| 构建号 | `CFBundleVersion` | 单调递增的整数字符串，每次上架/分发构建递增 |

发布流程中应同时更新本文件、`Sources/Info.plist` 中的上述两项，并保持叙述与真实用户可见变更一致。

## [Unreleased]

开发中的变更请先记在此处；发布新版本时移动到带日期的版本节，并同步更新 `Sources/Info.plist` 中的 `CFBundleShortVersionString` 与 `CFBundleVersion`。

## [1.0.0] - 2026-04-02

### Added

- 刘海区域展开面板：应用启动器（搜索、多种网格模式、文件夹与 Launchpad 式整理）。
- Claude 面板：内嵌终端（SwiftTerm）、Claude Code CLI 工作区与会话状态；可选 iTerm2 等外部终端捕获（实验性）。
- 任务面板、动画与外观设置、收缩态信息位、全屏时隐藏灵动岛、登录项（Launch at Login）等系统集成功能。

<!-- 后续版本在此上方追加 ## [x.y.z] - YYYY-MM-DD -->

[Unreleased]: https://github.com/jukie-xu/buling-island/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/jukie-xu/buling-island/releases/tag/v1.0.0
