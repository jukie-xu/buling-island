import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Tab Enum

enum SettingsTab: String, CaseIterable {
    case animation = "动画"
    case layout = "布局"
    case appearance = "外观"
    case general = "通用"

    var icon: String {
        switch self {
        case .animation: return "sparkles.rectangle.stack"
        case .layout: return "square.grid.2x2"
        case .appearance: return "paintbrush"
        case .general: return "gearshape"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {

    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedTab: SettingsTab = .animation
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    SettingsWindowManager.shared.close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            Divider()

            switch selectedTab {
            case .animation:
                AnimationSettingsTab(settings: settings, colorScheme: colorScheme)
            case .layout:
                LayoutSettingsTab(settings: settings)
            case .appearance:
                AppearanceSettingsTab(settings: settings, colorScheme: colorScheme)
            case .general:
                GeneralSettingsTab()
            }
        }
        .frame(width: 380, height: 560)
        .background(.ultraThinMaterial)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
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
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 120, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.04))
                            .frame(width: 120, height: 10)
                        HStack(spacing: 8) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor.opacity(0.2))
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(width: 160, height: 110)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 0)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                            .overlay(
                                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 0)
                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 0))
                    .transition(settings.expandAnimation.transition)
                } else {
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 0)
                        .fill(pillColor.opacity(0.05))
                        .overlay(
                            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 0)
                                .strokeBorder(pillColor.opacity(0.15), lineWidth: 1)
                        )
                        .frame(width: 76, height: 14)
                        .transition(settings.collapseAnimation.transition)
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

                if settings.displayMode == .launchpad {
                    resetSection
                }
            }
            .padding(20)
        }
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

                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 0)
                    .fill(previewColor.opacity(0.05))
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 0)
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
                    Text("登录 macOS 时自动启动 Buling Island")
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
                    Text("退出 Buling Island")
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
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        newWindow.contentView = hostingView
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = true
        newWindow.center()
        newWindow.level = .floating
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
