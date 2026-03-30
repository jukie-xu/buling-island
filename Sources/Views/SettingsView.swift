import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Sidebar

private enum SettingsSidebarSection: String, CaseIterable, Identifiable {
    case dashboard = "控制台"
    case layout = "布局"
    case animation = "动画"
    case general = "通用"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "rectangle.inset.filled.and.person.filled"
        case .layout: return "square.grid.2x2"
        case .animation: return "sparkles.rectangle.stack"
        case .general: return "gearshape"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {

    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedSection: SettingsSidebarSection = .dashboard
    @Environment(\.colorScheme) private var colorScheme

    private var chromeBackground: Color {
        colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.94)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.35)
            Group {
                switch selectedSection {
                case .dashboard:
                    SettingsDashboardTab(settings: settings, colorScheme: colorScheme)
                case .animation:
                    AnimationSettingsTab(settings: settings, colorScheme: colorScheme)
                case .layout:
                    LayoutSettingsTab(settings: settings)
                case .general:
                    GeneralSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(chromeBackground)
        }
        .frame(width: 920, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "inset.filled.topthird.rectangle")
                    .font(.system(size: 20))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("不灵灵动岛")
                        .font(.system(size: 14, weight: .semibold))
                    Text("设置")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    SettingsWindowManager.shared.close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 20)

            VStack(spacing: 4) {
                ForEach(SettingsSidebarSection.allCases) { section in
                    sidebarRow(section)
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
        .frame(width: 200)
        .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.99))
    }

    private func sidebarRow(_ section: SettingsSidebarSection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14))
                    .frame(width: 22)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(selectedSection == section ? Color.accentColor : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedSection == section ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Dashboard (参考 Nook X：预览 + 全局开关 + 能力规划 + 模块卡片)

private struct SettingsDashboardTab: View {

    private static let previewCollapsedPillWidth: CGFloat = CGFloat(88 * 3) / 4
    private static let previewExpandedMockWidth: CGFloat = 196

    /// 预览区外轮廓：平顶 + 底圆角，与笔记本屏幕上沿 + 刘海语义一致。
    private static var previewScreenChromeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 28,
            bottomTrailingRadius: 28,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    @ObservedObject var settings: SettingsManager
    let colorScheme: ColorScheme

    @State private var launchAtLogin: Bool = false
    @State private var previewExpanded = false

    /// 将主屏刘海中心映射到预览区域宽度内（与硬件刘海水平对齐，而非窗口内随意居中）。
    private static func notchAlignedCenterX(in contentWidth: CGFloat, elementHalfWidth: CGFloat) -> CGFloat {
        let n = NotchDetector.layoutNotch()
        guard n.screenFrame.width > 1 else { return contentWidth / 2 }
        let fraction = (n.rect.midX - n.screenFrame.minX) / n.screenFrame.width
        let x = fraction * contentWidth
        let inset = elementHalfWidth + 2
        return max(inset, min(contentWidth - inset, x))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                globalTogglesCard
                widgetModulesCard
                roadmapCard
            }
            .padding(24)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var islandPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("刘海预览")
                .webNookSectionTitle()

            GeometryReader { geo in
                let w = geo.size.width
                let pillCX = Self.notchAlignedCenterX(in: w, elementHalfWidth: Self.previewCollapsedPillWidth / 2)
                let expandedCX = Self.notchAlignedCenterX(in: w, elementHalfWidth: Self.previewExpandedMockWidth / 2)

                ZStack(alignment: .topLeading) {
                    // 顶边平直 = 显示器上沿；底角圆角仅为装饰。避免四风圆角把内容顶成「离顶一条缝」。
                    Self.previewScreenChromeShape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.55, blue: 0.95),
                                    Color(red: 0.95, green: 0.78, blue: 0.35),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: w, height: 200)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(12)
                        }

                    if previewExpanded {
                        previewExpandedMock
                            .offset(x: expandedCX - Self.previewExpandedMockWidth / 2, y: 0)
                            .transition(IslandPanelViewTransition.settingsPreviewExpanded)
                    } else {
                        previewCollapsedPill
                            .offset(x: pillCX - Self.previewCollapsedPillWidth / 2, y: 0)
                            .transition(IslandPanelViewTransition.settingsPreviewCollapsed)
                    }
                }
                .frame(width: w, height: 200)
            }
            .frame(height: 200)
            .clipShape(Self.previewScreenChromeShape)
            .overlay(
                Self.previewScreenChromeShape
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )

            Button {
                if previewExpanded {
                    withAnimation(settings.collapseAnimation.animation) {
                        previewExpanded = false
                    }
                } else {
                    withAnimation(settings.expandAnimation.animation) {
                        previewExpanded = true
                    }
                }
            } label: {
                Text(previewExpanded ? "收起预览" : "展开预览")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .webNookCard(colorScheme: colorScheme)
    }

    private var previewCorner: CGFloat { 12 }

    private var previewCollapsedPill: some View {
        TangentFilletBottomRectangle(bottomFilletRadius: 6)
        .fill(Color.black.opacity(0.88))
        .frame(width: Self.previewCollapsedPillWidth, height: 15)
        .overlay {
            HStack(spacing: 5) {
                Image(systemName: "sun.max.fill").font(.system(size: 8)).foregroundStyle(.white.opacity(0.85))
                Text("0%").font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 4)
                Image(systemName: "arrow.up").font(.system(size: 7))
                Text("1 KB/s").font(.system(size: 7))
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 8)
        }
    }

    private var previewExpandedMock: some View {
        VStack(spacing: 8) {
            HStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 56, height: 12)
                Spacer()
            }

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: 120, height: 10)

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 22, height: 22)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(width: 196)
        .background(
            TangentFilletBottomRectangle(bottomFilletRadius: previewCorner)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            TangentFilletBottomRectangle(bottomFilletRadius: previewCorner)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var globalTogglesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("全局开关")
                .webNookSectionTitle()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                nookToggle(
                    title: "点击展开",
                    caption: "点击刘海区域展开面板",
                    isOn: $settings.clickToExpand
                )
                nookToggle(
                    title: "开启灵动岛",
                    caption: "显示顶部刘海启动面板",
                    isOn: $settings.islandEnabled
                )
                nookToggle(
                    title: "开机启动",
                    caption: "登录 macOS 时自动启动",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            toggleLaunchAtLogin(newValue)
                        }
                    )
                )
            }
        }
        .padding(18)
        .webNookCard(colorScheme: colorScheme)
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func nookToggle(title: String, caption: String, planned: Bool) -> some View {
        nookToggleShell(title: title, caption: caption) {
            Text("规划中")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(Color.orange.opacity(0.15)))
        }
    }

    private func nookToggle(title: String, caption: String, isOn: Binding<Bool>) -> some View {
        nookToggleShell(title: title, caption: caption) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private func nookToggleShell<Control: View>(
        title: String,
        caption: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("OFF")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                control()
                Text("ON")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var widgetModulesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("展开态能力模块")
                .webNookSectionTitle()
            Text("与 Nook X 类似，将能力拆为可开关模块；以下为当前产品与规划对照。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    moduleChip(
                        title: "应用启动器",
                        subtitle: "搜索与网格 / Launchpad 启动",
                        tier: .free,
                        status: "已就绪"
                    )
                    moduleChip(
                        title: "流光声域",
                        subtitle: "歌词与播放状态",
                        tier: .pro,
                        status: "规划中"
                    )
                    moduleChip(
                        title: "日历天气",
                        subtitle: "日程与天气摘要",
                        tier: .free,
                        status: "规划中"
                    )
                    moduleChip(
                        title: "快捷指令",
                        subtitle: "自定义快捷操作",
                        tier: .pro,
                        status: "规划中"
                    )
                    moduleChip(
                        title: "待办 / 提醒",
                        subtitle: "轻量待办展示",
                        tier: .pro,
                        status: "规划中"
                    )
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .webNookCard(colorScheme: colorScheme)
    }

    private enum ModuleTier {
        case free, pro
        var label: String {
            switch self {
            case .free: return "Free"
            case .pro: return "Pro"
            }
        }
        var color: Color {
            switch self {
            case .free: return .green
            case .pro: return .orange
            }
        }
    }

    private func moduleChip(title: String, subtitle: String, tier: ModuleTier, status: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tier.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tier.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(tier.color.opacity(0.18)))
                Spacer()
                Text(status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("详情与设置入口随模块上线提供")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 196, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var roadmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("图 2 功能点 — 产品映射")
                .webNookSectionTitle()

            VStack(alignment: .leading, spacing: 10) {
                roadmapRow(
                    "预览与手势",
                    "大屏卡片预览收缩/展开；设置入口与真实动画一致。"
                )
                roadmapRow(
                    "左 / 右自选信息位",
                    "对应多类系统信息胶囊（网速、农历、日期、时钟、电量等），依赖系统接口与布局框架。"
                )
                roadmapRow(
                    "展开态小组件",
                    "音乐、天气、快捷启动、快捷指令、待办等可插拔模块；需权限、沙箱与 Pro 策略。"
                )
                roadmapRow(
                    "多屏与通知",
                    "外接显示器镜像刘海能力；试验性通知推送至灵动区域。"
                )
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .webNookCard(colorScheme: colorScheme)
    }

    private func roadmapRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension Text {
    func webNookSectionTitle() -> some View {
        font(.system(size: 15, weight: .semibold))
    }
}

private extension View {
    func webNookCard(colorScheme: ColorScheme) -> some View {
        background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Animation Settings Tab

struct AnimationSettingsTab: View {

    @ObservedObject var settings: SettingsManager
    let colorScheme: ColorScheme
    @State private var previewExpanded = false

    private var pillColor: Color {
        if settings.useCustomPillColor {
            return settings.pillBorderColor
        }
        return .primary
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                previewSection

                animationPicker(
                    title: "展开动画",
                    icon: "arrow.down.forward.and.arrow.up.backward",
                    selection: Binding(
                        get: { settings.expandAnimation },
                        set: { settings.expandAnimation = $0 }
                    ),
                    allCases: ExpandAnimation.allCases
                )

                animationPicker(
                    title: "收起动画",
                    icon: "arrow.up.backward.and.arrow.down.forward",
                    selection: Binding(
                        get: { settings.collapseAnimation },
                        set: { settings.collapseAnimation = $0 }
                    ),
                    allCases: CollapseAnimation.allCases
                )
            }
            .padding(20)
        }
    }

    private var previewSection: some View {
        VStack(spacing: 12) {
            Text("预览")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.03))
                    .frame(height: 140)

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 70, height: 12)

                if previewExpanded {
                    VStack(spacing: 6) {
                        Spacer().frame(height: 14)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 120, height: 14)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                            .frame(width: 120, height: 10)
                        HStack(spacing: 8) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.2))
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(width: 160, height: 110)
                    .background(
                        TangentFilletBottomRectangle(bottomFilletRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                            .overlay(
                                TangentFilletBottomRectangle(bottomFilletRadius: 10)
                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                    .clipShape(TangentFilletBottomRectangle(bottomFilletRadius: 10))
                    .transition(IslandPanelViewTransition.settingsPreviewExpanded)
                } else {
                    TangentFilletBottomRectangle(bottomFilletRadius: 6)
                        .fill(pillColor.opacity(0.05))
                        .overlay(
                            TangentFilletBottomRectangle(bottomFilletRadius: 6)
                                .strokeBorder(pillColor.opacity(0.15), lineWidth: 1)
                        )
                        .frame(width: 76, height: 14)
                        .transition(IslandPanelViewTransition.settingsPreviewCollapsed)
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                if previewExpanded {
                    withAnimation(settings.collapseAnimation.animation) {
                        previewExpanded = false
                    }
                } else {
                    withAnimation(settings.expandAnimation.animation) {
                        previewExpanded = true
                    }
                }
            } label: {
                Text(previewExpanded ? "点击收起" : "点击展开")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
        }
    }

    private func animationPicker(
        title: String,
        icon: String,
        selection: Binding<ExpandAnimation>,
        allCases: [ExpandAnimation]
    ) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(.secondary)
                Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                Spacer()
            }
            VStack(spacing: 4) {
                ForEach(allCases) { item in
                    radioRow(label: item.displayName, isSelected: item == selection.wrappedValue) {
                        selection.wrappedValue = item
                    }
                }
            }
        }
    }

    private func animationPicker(
        title: String,
        icon: String,
        selection: Binding<CollapseAnimation>,
        allCases: [CollapseAnimation]
    ) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(.secondary)
                Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                Spacer()
            }
            VStack(spacing: 4) {
                ForEach(allCases) { item in
                    radioRow(label: item.displayName, isSelected: item == selection.wrappedValue) {
                        selection.wrappedValue = item
                    }
                }
            }
        }
    }

    private func radioRow(label: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
            Text(label).font(.system(size: 13)).foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Layout Settings Tab

struct LayoutSettingsTab: View {

    @ObservedObject var settings: SettingsManager
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                displayModeSection
                pillInfoSlotsSection

                if settings.displayMode == .launchpad {
                    resetSection
                }
            }
            .padding(20)
        }
    }

    private var pillInfoSlotsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("收缩态刘海信息位")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            Text("在 pill 左右两侧扩展区域展示系统电量与网速（约每秒刷新）。网速通过 netstat 统计网卡累计字节差分，无电池机型将不显示电量。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            pillSlotPickerRow(title: "左侧", selection: $settings.pillLeftSlot)
            pillSlotPickerRow(title: "右侧", selection: $settings.pillRightSlot)
        }
    }

    private func pillSlotPickerRow(title: String, selection: Binding<PillSideWidget>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .frame(width: 44, alignment: .leading)
            Picker(title, selection: selection) {
                ForEach(PillSideWidget.allCases) { slot in
                    Text(slot.displayName).tag(slot)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private var displayModeSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("展示模式")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            VStack(spacing: 4) {
                ForEach(DisplayMode.allCases) { mode in
                    let isSelected = mode == settings.displayMode
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
                        Image(systemName: mode.icon)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                            Text(mode.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.displayMode = mode
                        }
                    }
                }
            }
        }
    }

    private var resetSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Launchpad 管理")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            Button {
                showResetConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                    Text("重置布局")
                        .font(.system(size: 13))
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .alert("确认重置布局？", isPresented: $showResetConfirm) {
                Button("取消", role: .cancel) { }
                Button("重置", role: .destructive) {
                    FolderManager.shared.resetLayout()
                }
            } message: {
                Text("将清除所有文件夹和自定义排列，恢复默认布局，此操作不可撤销。")
            }

            Text("清除所有文件夹和自定义排列，恢复默认布局")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Appearance Settings Tab

struct AppearanceSettingsTab: View {

    @ObservedObject var settings: SettingsManager
    let colorScheme: ColorScheme

    private let presetColors: [(String, Color)] = [
        ("蓝色", Color.blue.opacity(0.4)),
        ("紫色", Color.purple.opacity(0.4)),
        ("青色", Color.cyan.opacity(0.4)),
        ("绿色", Color.green.opacity(0.4)),
        ("橙色", Color.orange.opacity(0.4)),
        ("粉色", Color.pink.opacity(0.4)),
        ("灰色", Color.gray.opacity(0.3)),
        ("白色", Color.white.opacity(0.3)),
    ]

    private var previewColor: Color {
        if settings.useCustomPillColor {
            return settings.pillBorderColor
        }
        return .primary
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                pillPreview
                modeSection
                if settings.useCustomPillColor {
                    presetSection
                    customColorSection
                }
            }
            .padding(20)
        }
    }

    private var pillPreview: some View {
        VStack(spacing: 12) {
            Text("预览")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.03))
                    .frame(height: 60)

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 70, height: 12)

                TangentFilletBottomRectangle(bottomFilletRadius: 6)
                    .fill(previewColor.opacity(0.05))
                    .overlay(
                        TangentFilletBottomRectangle(bottomFilletRadius: 6)
                            .strokeBorder(previewColor.opacity(0.15), lineWidth: 1)
                    )
                    .frame(width: 76, height: 14)
            }
            .frame(height: 60)
        }
    }

    private var modeSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("颜色模式")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            VStack(spacing: 4) {
                modeRow(label: "跟随系统", description: "深色模式白色边框，浅色模式黑色边框", isSelected: !settings.useCustomPillColor) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.useCustomPillColor = false
                    }
                }
                modeRow(label: "自定义颜色", description: "选择喜欢的边框颜色", isSelected: settings.useCustomPillColor) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.useCustomPillColor = true
                    }
                }
            }
        }
    }

    private func modeRow(label: String, description: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13)).foregroundColor(.primary)
                Text(description).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var presetSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "swatchpalette")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("预设颜色")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(presetColors, id: \.0) { name, color in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(color)
                            .overlay(
                                Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                            .frame(width: 36, height: 36)

                        Text(name)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.useCustomPillColor = true
                            settings.pillBorderColor = color
                        }
                    }
                }
            }
        }
    }

    private var customColorSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "eyedropper")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("自定义颜色")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            ColorPicker("边框颜色", selection: $settings.pillBorderColor, supportsOpacity: true)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {

    @State private var launchAtLogin: Bool = false
    @State private var accessibilityGranted: Bool = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var showQuitConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                startupSection
                permissionsSection
                quitSection
            }
            .padding(20)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            accessibilityGranted = AXIsProcessTrusted()
        }
        .onReceive(timer) { _ in
            let current = AXIsProcessTrusted()
            if current != accessibilityGranted {
                accessibilityGranted = current
            }
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("启动")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("开机自启动")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    Text("登录 macOS 时自动启动不灵灵动岛")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: launchAtLogin) { newValue in
                        toggleLaunchAtLogin(newValue)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("权限设置")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack {
                Image(systemName: "hand.raised")
                    .font(.system(size: 14))
                    .foregroundColor(accessibilityGranted ? .green : .orange)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("辅助功能")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Text(accessibilityGranted ? "已授权" : "未授权")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(accessibilityGranted ? .green : .orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(accessibilityGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            )
                    }
                    Text("用于监听全局鼠标事件（点击刘海、点击外部收起）")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    if !accessibilityGranted {
                        requestAccessibility()
                    }
                } label: {
                    Text(accessibilityGranted ? "已授权" : "去授权")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(accessibilityGranted ? .secondary : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(accessibilityGranted ? Color.primary.opacity(0.06) : Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .disabled(accessibilityGranted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
    }

    // MARK: - Quit

    private var quitSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("退出")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            Button {
                showQuitConfirm = true
            } label: {
                HStack {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                    Text("退出不灵灵动岛")
                        .font(.system(size: 13))
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .alert("确认退出？", isPresented: $showQuitConfirm) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            } message: {
                Text("退出后将无法通过刘海快速启动应用。")
            }
        }
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Settings Window Manager

final class SettingsWindowManager: NSObject, NSWindowDelegate {

    static let shared = SettingsWindowManager()

    private var window: NSWindow?

    private override init() {}

    func open() {
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        window = nil

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 700),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        newWindow.contentView = hostingView
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = true
        newWindow.center()
        newWindow.level = .normal
        newWindow.delegate = self
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
