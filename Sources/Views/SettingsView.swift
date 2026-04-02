import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Sidebar

private enum SettingsSidebarSection: String, CaseIterable, Identifiable {
    case dashboard = "控制台"
    case claude = "Claude 面板"
    case tasks = "任务面板"
    case layout = "布局"
    case appearance = "外观"
    case animation = "动画"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "rectangle.inset.filled.and.person.filled"
        case .claude: return "terminal"
        case .tasks: return "checklist"
        case .layout: return "square.grid.2x2"
        case .appearance: return "paintbrush"
        case .animation: return "sparkles.rectangle.stack"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {

    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedSection: SettingsSidebarSection = .dashboard
    @State private var appPanelExpanded = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQuitConfirm = false

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
                case .claude:
                    ClaudeSettingsTab(settings: settings, colorScheme: colorScheme)
                case .tasks:
                    TaskSettingsTab(settings: settings, colorScheme: colorScheme)
                case .animation:
                    AnimationSettingsTab(settings: settings, colorScheme: colorScheme)
                case .layout:
                    LayoutSettingsTab(settings: settings)
                case .appearance:
                    AppearanceSettingsTab(settings: settings, colorScheme: colorScheme)
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
                sidebarRow(.dashboard)
                appPanelGroup
                sidebarRow(.claude)
                sidebarRow(.tasks)
            }
            .padding(.horizontal, 10)

            Spacer()

            Button {
                showQuitConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .semibold))
                    Text("退出")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(colorScheme == .dark ? 0.16 : 0.12))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
            .alert("确认退出？", isPresented: $showQuitConfirm) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            } message: {
                Text("你想好了你就退吧。")
            }
        }
        .frame(width: 200)
        .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.99))
    }

    private func sidebarRow(_ section: SettingsSidebarSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                sidebarIcon(for: section, selected: isSelected)
                    .frame(width: 22, height: 22)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var appPanelChildren: [SettingsSidebarSection] {
        [.layout, .appearance, .animation]
    }

    private var appPanelGroup: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appPanelExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    AppPanelIconMark(size: 16, active: true)
                        .frame(width: 22, height: 22)
                    Text("应用面板")
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: appPanelExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.clear)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            if appPanelExpanded {
                VStack(spacing: 3) {
                    ForEach(appPanelChildren) { section in
                        appPanelChildRow(section)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appPanelExpanded)
    }

    private func appPanelChildRow(_ section: SettingsSidebarSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                sidebarIcon(for: section, selected: isSelected)
                    .frame(width: 20, height: 20)
                Text(section.rawValue)
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(isSelected ? Color.accentColor : .primary.opacity(0.92))
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sidebarIcon(for section: SettingsSidebarSection, selected: Bool) -> some View {
        switch section {
        case .claude:
            ClaudePanelIconMark(size: 15, active: selected)
        case .tasks:
            TaskPanelIconMark(size: 15, active: selected)
        default:
            Image(systemName: section.icon)
                .font(.system(size: 14))
        }
    }
}

struct ClaudeSettingsTab: View {
    @ObservedObject var settings: SettingsManager
    let colorScheme: ColorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                claudeHintCard
            }
            .padding(20)
        }
    }

    private var claudeHintCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Claude 提醒文案")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            toggleRow(
                title: "展示下拉伸提醒文案",
                caption: "在收缩态 pill 底部显示 Claude 的成功/警告/错误提醒。",
                isOn: $settings.claudeStretchHintEnabled
            )

            toggleRow(
                title: "自动动态缩回",
                caption: "提醒显示后按设定时长自动收起，减少常驻占位。",
                isOn: $settings.claudeHintAutoCollapseEnabled
            )

            toggleRow(
                title: "启用 iTerm2 会话捕获（实验）",
                caption: "读取 iTerm2 中运行中的 Claude 会话输出并生成提醒。",
                isOn: $settings.claudeEnableITerm2Capture
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("自动缩回延迟")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(Int(settings.claudeHintAutoCollapseDelay.rounded()))s")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { settings.claudeHintAutoCollapseDelay },
                        set: { settings.claudeHintAutoCollapseDelay = min(max($0, 1), 10) }
                    ),
                    in: 1...10,
                    step: 1
                )
                .disabled(!settings.claudeHintAutoCollapseEnabled)
                Text("默认 3 秒；关闭自动缩回后此项不会生效。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("iTerm2 轮询间隔")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1fs", settings.claudeITerm2PollInterval))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { settings.claudeITerm2PollInterval },
                        set: { settings.claudeITerm2PollInterval = min(max($0, 1), 5) }
                    ),
                    in: 1...5,
                    step: 0.5
                )
                .disabled(!settings.claudeEnableITerm2Capture)
                Text("建议 1.5 秒；较高频率会增加系统开销。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func toggleRow(title: String, caption: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

struct TaskSettingsTab: View {
    @ObservedObject var settings: SettingsManager
    let colorScheme: ColorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                taskTypographyCard
            }
            .padding(20)
        }
    }

    private var taskTypographyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Task 字体")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("任务面板字体大小")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(Int(settings.taskPanelFontSize.rounded()))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { settings.taskPanelFontSize },
                        set: { settings.taskPanelFontSize = min(max($0, 10), 16) }
                    ),
                    in: 10...16,
                    step: 1
                )
                Text("默认 12，调小后 Task 卡片文本会更紧凑。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SettingsDashboardTab: View {

    @ObservedObject var settings: SettingsManager
    let colorScheme: ColorScheme

    private static let showRoadmapAndModules: Bool = false

    @State private var launchAtLogin: Bool = false
    @State private var accessibilityGranted: Bool = false
    private let accessibilityPoller = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                globalTogglesCard
                if Self.showRoadmapAndModules {
                    widgetModulesCard
                    roadmapCard
                }
            }
            .padding(24)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            accessibilityGranted = AXIsProcessTrusted()
        }
        .onReceive(accessibilityPoller) { _ in
            let current = AXIsProcessTrusted()
            if current != accessibilityGranted {
                accessibilityGranted = current
            }
        }
    }


    private var globalTogglesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            generalQuickTogglesCard
            permissionsCard
        }
    }

    private var generalQuickTogglesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("常规")
                .sectionTitle()

            VStack(spacing: 0) {
                dashboardToggleRow(
                    title: "全屏时隐藏胶囊",
                    caption: "前台全屏时自动隐藏收缩态胶囊",
                    isOn: $settings.autoHideCollapsedPillInFullscreen
                )
                dashboardRowDivider
                dashboardToggleRow(
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
                dashboardRowDivider
                dashboardDefaultExpandedPanelRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.028))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06), lineWidth: 1)
            )
        }
        .padding(18)
        .cardStyle(colorScheme: colorScheme)
    }

    private var dashboardDefaultExpandedPanelRow: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("默认展开面板")
                    .font(.system(size: 13, weight: .medium))
                Text("从收缩态点击展开时，优先进入的面板。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Picker("默认展开面板", selection: $settings.defaultExpandedPanel) {
                ForEach(ExpandedPanelMode.allCases) { mode in
                    Text(expandedPanelSegmentLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .accessibilityHint("在应用、Claude 与任务三种展开面板间选择默认项")
        }
        .padding(.vertical, 10)
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("权限")
                .sectionTitle()

            dashboardAccessibilityAuthorizationSection
        }
        .padding(18)
        .cardStyle(colorScheme: colorScheme)
    }

    private func expandedPanelSegmentLabel(_ mode: ExpandedPanelMode) -> String {
        switch mode {
        case .appStore: return "应用"
        case .claude: return "Claude"
        case .tasks: return "任务"
        }
    }

    private var dashboardRowDivider: some View {
        Divider()
            .opacity(colorScheme == .dark ? 0.18 : 0.30)
    }

    private func dashboardToggleRow(title: String, caption: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .controlSize(.small)
                .toggleStyle(.switch)
        }
        .padding(.vertical, 8)
    }

    private var dashboardAccessibilityAuthorizationSection: some View {
        let statusText = accessibilityGranted ? "已授权" : "未授权"
        let statusColor: Color = accessibilityGranted ? .green : .orange
        let primaryTitle = accessibilityGranted ? "已授权" : "去授权…"
        let primaryEnabled = !accessibilityGranted
        let primaryBackground = accessibilityGranted
            ? Color.primary.opacity(0.10)
            : Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.16)
        let primaryForeground: Color = accessibilityGranted ? .secondary : .accentColor
        let cardStroke: Color = accessibilityGranted
            ? Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
            : Color.orange.opacity(0.34)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("辅助功能授权")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(statusColor.opacity(0.18))
                    )
                Spacer(minLength: 10)

                Button {
                    requestAccessibility()
                } label: {
                    Text(primaryTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(primaryBackground)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!primaryEnabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("用于点击唤醒/收起、外部点击收起等全局交互能力。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accessibilityGranted ? .secondary : statusColor.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                Text("我们不会读取键盘内容或收集输入，只用于交互判断。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.028))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: 1)
        )
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

    private var widgetModulesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("展开态能力模块")
                .sectionTitle()
            Text("将能力拆为可开关模块；以下为当前产品与规划对照。")
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
        .cardStyle(colorScheme: colorScheme)
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
                .sectionTitle()

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
        .cardStyle(colorScheme: colorScheme)
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

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySystemSettings()
    }

    private func openAccessibilitySystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private extension Text {
    func sectionTitle() -> some View {
        font(.system(size: 15, weight: .semibold))
    }
}

private extension View {
    func cardStyle(colorScheme: ColorScheme) -> some View {
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
                    VStack(spacing: 0) {
                        // Top bar (matches real panel: flush to top)
                        Color.clear
                            .frame(height: 14)

                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)
                            .padding(.horizontal, 16)

                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 24)
                            HStack(spacing: 10) {
                                ForEach(0..<4, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.white.opacity(0.12))
                                        .frame(width: 28, height: 28)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                    }
                    .frame(width: 196, height: 122)
                    .background(
                        ExpandedIslandPanelShape(topConvexRadius: 16, bottomFilletRadius: 16)
                            .fill(Color.black, style: FillStyle(antialiased: false))
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.18), radius: 8, y: 3)
                    )
                    .clipShape(ExpandedIslandPanelShape(topConvexRadius: 16, bottomFilletRadius: 16))
                    .transition(IslandPanelViewTransition.settingsPreviewExpanded)
                } else {
                    let baseCoreWidth: CGFloat = 132
                    let baseNotchHeight: CGFloat = 15
                    let pillH = baseNotchHeight + settings.pillVisualHeightOverhang
                    let pillW = baseCoreWidth + 2 * settings.pillVisualWidthOverhang
                    let pillShape = FlaredTopTangentBottomRectangle(
                        topConvexRadius: settings.pillFlareRadius,
                        topCornerFlare: 0.52,
                        bottomFilletRadius: 12,
                        bodyInsetX: settings.pillVisualWidthOverhang
                    )

                    pillShape
                        .fill(Color.black, style: FillStyle(antialiased: false))
                        .frame(width: pillW, height: pillH)
                        .offset(y: -settings.pillVisualHeightOverhang / 2)
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
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(allCases) { item in
                    animationOptionCard(
                        title: item.displayName,
                        detail: item.detail,
                        isSelected: item == selection.wrappedValue
                    ) {
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
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(allCases) { item in
                    animationOptionCard(
                        title: item.displayName,
                        detail: item.detail,
                        isSelected: item == selection.wrappedValue
                    ) {
                        selection.wrappedValue = item
                    }
                }
            }
        }
    }

    private func animationOptionCard(
        title: String,
        detail: String,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.55))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10) : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { onTap() }
    }
}

// MARK: - Layout Settings Tab

struct LayoutSettingsTab: View {

    @ObservedObject var settings: SettingsManager
    @State private var showResetConfirm = false
    @State private var selectedSmartMergePreset: FolderManager.SmartMergePreset = .byFunction
    @State private var showSmartMergeConfirm = false
    @State private var isSmartMerging = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                displayModeSection
                pillInfoSlotsSection

                if settings.displayMode == .launchpad {
                    smartMergeSection
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

    private var smartMergeSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Launchpad 智能合并")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("分组维度")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    Text(selectedSmartMergePreset.detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("分组维度", selection: $selectedSmartMergePreset) {
                    ForEach(FolderManager.SmartMergePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            Button {
                showSmartMergeConfirm = true
            } label: {
                HStack {
                    if isSmartMerging {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                    }
                    Text(isSmartMerging ? "处理中…" : "一键智能合并")
                        .font(.system(size: 13))
                }
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(isSmartMerging)
            .alert("确认智能合并？", isPresented: $showSmartMergeConfirm) {
                Button("取消", role: .cancel) { }
                Button("开始", role: .destructive) {
                    runSmartMerge()
                }
            } message: {
                Text("将按所选维度重建当前 Launchpad 布局（会覆盖现有文件夹排列）。")
            }

            Text("根据预设维度批量分组应用；不会删除应用，只会重建文件夹与网格顺序。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func runSmartMerge() {
        guard !isSmartMerging else { return }
        isSmartMerging = true
        let preset = selectedSmartMergePreset
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = AppDiscoveryService.shared.discoverApps()
            DispatchQueue.main.async {
                FolderManager.shared.smartMergeApps(apps, preset: preset)
                isSmartMerging = false
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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                pillTuningSection
            }
            .padding(20)
        }
    }

    private var pillTuningSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Pill 外观微调")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            sliderRow(
                title: "外撇角半径",
                value: $settings.pillFlareRadius,
                range: 4...18,
                step: 1,
                hint: "越小越紧，越大越圆"
            )

            sliderRow(
                title: "整体额外宽度（单侧）",
                value: $settings.pillVisualWidthOverhang,
                range: 0...18,
                step: 1,
                hint: "增大可让 P0 更外侧、更圆润"
            )

            sliderRow(
                title: "电量/网速槽宽",
                value: $settings.pillSideSlotWidth,
                range: 40...72,
                step: 1,
                hint: "左右翼信息区宽度"
            )

            sliderRow(
                title: "Pill 高度（额外）",
                value: $settings.pillVisualHeightOverhang,
                range: 0...10,
                step: 1,
                hint: "在 notch 高度基础上额外增加"
            )
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
                ),
                in: range,
                step: step
            )
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
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
