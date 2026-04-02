# 设计文档：设置页新增「关于」选项卡

- 日期：2026-04-02
- 目标版本：未定（本次为 UI 功能新增）
- 作者：Codex（按仓库协作约定生成）

## 1. 背景与目标

当前设置页缺少一个集中展示作者信息、免责声明与开源授权信息的入口。为了提升产品可信度与合规性，在设置中新增「关于」选项卡，展示：

- 作者/项目基本信息
- 作者声明 / 免责声明
- 开源许可（MIT）与仓库信息

## 2. 范围

### 2.1 In Scope

- 在设置侧边栏新增「关于」入口（图标 + 文案）。
- 新增 `AboutSettingsTab` 页面并接入现有 `SettingsView` 的分区切换逻辑。
- 页面展示 App 名称、版本号、构建号、作者信息、声明、开源授权说明。

### 2.2 Out of Scope

- 不引入网络请求（不在线拉取 README/License）。
- 不新增本地化资源文件（后续如需多语言再做结构化提取）。
- 不做自动更新检查或外部链接跳转的复杂交互（可保留简单的“复制/打开链接”能力，若实现成本过高则先不做）。

## 3. 详细设计

### 3.1 侧边栏入口

- 在 `SettingsSidebarSection` 增加：
  - case：`about = "关于"`
  - icon：使用 SF Symbol：`"info.circle"`
- 在侧边栏列表中把「关于」放在底部靠近「退出」按钮上方，符合用户预期的“辅助信息”位置。
- 「关于」与「退出」采用同一套底部大按钮样式：图标+文字整体居中，视觉上更像“动作入口”而非普通侧边栏条目。

### 3.2 内容布局（AboutSettingsTab）

整体采用与现有设置页一致的卡片风格/间距（跟随 `chromeBackground`），但改为更接近 macOS 原生「关于」的布局：

- 顶部品牌区：App 图标 + 名称 + 版本构建
- 快捷动作区：打开 GitHub、复制链接、复制邮箱（并显示轻量“已复制”反馈）
- 信息卡片区：3 块卡片（应用信息 / 作者与声明 / 开源与授权），内部用 `Grid` 做对齐，减少“表格感”和空洞留白

1) **应用信息**
- App 展示名：`CFBundleDisplayName`（兜底 `CFBundleName`）
- 版本：`CFBundleShortVersionString`
- 构建：`CFBundleVersion`
- 系统要求：macOS 13+
- GitHub：URL 显示为单行，中间省略（`truncationMode(.middle)`），但可一键打开/复制

2) **作者与声明**
- 作者（示例）：`jukie-xu`
- 作者邮箱：展示并可复制
- 反馈共创：提示“欢迎提出意见和共创”
- 声明（可后续调整文案）：
  - 本软件按“现状”提供，不对适用性、稳定性作任何明示/暗示担保。
  - 使用涉及系统辅助功能/自动化授权时，请用户确认权限含义并自行承担风险。
  - 如用于生产环境或企业分发，请自行完成代码签名、公证与合规审查。

3) **开源与授权**
- License：MIT
- 说明：Buling Island 为开源项目，遵循 MIT License；第三方依赖（如 SwiftTerm）以其各自许可证为准。
- 仓库地址：展示文本（可复制），例如 `https://github.com/jukie-xu/buling-island`。

### 3.3 数据来源

- 版本/构建号：读取 `Bundle.main`：
  - `CFBundleShortVersionString`
  - `CFBundleVersion`
  - `CFBundleDisplayName` / `CFBundleName`
- 作者/声明/许可文本：先硬编码在 `AboutSettingsTab` 内（后续如要国际化，可迁移到 strings 文件）。

## 4. 验收标准

- 设置页侧边栏出现「关于」入口，点击后能进入 About 页面。
- About 页面能正确显示当前 App 的版本号与构建号（来自 `Info.plist`）。
- 页面包含作者信息（含邮箱与共创提示）、声明文本、MIT 授权说明、GitHub 仓库地址。
- `swift build` 通过。

## 5. 风险与回滚策略

- 风险：文案可能需要多次迭代；目前先以硬编码落地，后续再结构化提取。
- 回滚：若 UI 回归，可仅移除 `AboutSettingsTab` 与侧边栏入口，不影响核心功能。

## 6. 实施步骤

1. 修改 `SettingsSidebarSection`：新增 `.about` 与 icon 映射。
2. 在 `SettingsView` 的侧边栏中插入 `sidebarRow(.about)`（靠近底部）。
3. 在 `switch selectedSection` 中新增 case，渲染 `AboutSettingsTab`。
4. 新增 `AboutSettingsTab` 视图实现。
5. `swift build` 验证。

