import SwiftUI
import AppKit

struct IslandView: View {

    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var pillHud = PillHudViewModel()
    @StateObject private var claudeCLI = ClaudeCLIService()
    @State private var isLaunchpadEditing = false
    @State private var expandedContentMode: ExpandedContentMode = .appStore
    @State private var claudeInteractionHint: String?
    @State private var claudePillStatusText: String?
    @State private var claudePillStatusTone: String = "info"
    @State private var claudeRightSlotFlashVisible = false
    @State private var claudeRightSlotFlashPulse = false
    @State private var lastClaudeFlashAt: Date = .distantPast

    private enum ExpandedContentMode {
        case appStore
        case claude
    }

    private var fillColor: Color {
        .primary
    }

    private var borderColor: Color {
        .primary
    }

    private var notch: NotchInfo {
        NotchDetector.layoutNotch()
    }

    /// 主屏刘海几何签名；变化时刷新 pill 热区与面板 frame（切换 App / 台前调度后 `layoutNotch` 会变，但无 @Published 触发）。
    private var notchLayoutKey: String {
        let n = NotchDetector.layoutNotch()
        let f = n.screenFrame
        let r = n.rect
        return "\(n.notchWidth)_\(n.notchHeight)_\(f.minX)_\(f.minY)_\(f.width)_\(f.height)_\(r.midX)_\(r.minY)_\(r.width)_\(r.height)"
    }

    var body: some View {
        GeometryReader { geo in
            let progress: CGFloat = viewModel.state == .expanded ? 1 : 0
            let totalW = PillLayout.totalWidth(notch: notch, left: settings.pillLeftSlot, right: settings.pillRightSlot)
            let pillVisualW = totalW + 2 * PillLayout.visualWidthOverhang
            let effectiveVisualHeightOverhang = max(PillLayout.visualHeightOverhang, 2)
            let pillH = notch.notchHeight + effectiveVisualHeightOverhang + claudeHintExpansionHeight

            // Expanded content occupies the full hosting area.
            let expandedSize = geo.size

            let morphShape = IslandMorphShape(
                progress: progress,
                pillSize: CGSize(width: pillVisualW, height: pillH),
                expandedSize: expandedSize,
                pillTopRadius: settings.pillFlareRadius,
                expandedTopRadius: Self.expandedTopCornerRadius,
                pillTopFlare: 0.52,
                expandedTopFlare: 0.64,
                pillBottomFillet: 12,
                expandedBottomFillet: Self.expandedBottomFillet,
                pillBodyInsetX: PillLayout.visualWidthOverhang
            )

            ZStack(alignment: .top) {
                // One continuous black surface that morphs from pill -> panel.
                morphShape
                    .fill(Color.black, style: FillStyle(antialiased: false))

                collapsedView
                    .opacity(1 - progress)
                    .allowsHitTesting(false)

                expandedView
                    .opacity(progress)
                    .allowsHitTesting(viewModel.state == .expanded)
            }
            .clipShape(morphShape, style: FillStyle(antialiased: false))
            .animation(
                viewModel.state == .expanded ? settings.expandAnimation.animation : settings.collapseAnimation.animation,
                value: viewModel.state
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if viewModel.state == .collapsed {
                pillHud.start()
                syncCollapsedPillHitRect()
            }
        }
        .onChange(of: viewModel.state) { newState in
            if newState == .collapsed {
                pillHud.start()
                syncCollapsedPillHitRect()
            } else {
                pillHud.stop()
                stopClaudeRightSlotFlash()
            }
        }
        .onChange(of: settings.pillLeftSlot) { _ in syncCollapsedPillHitRect() }
        .onChange(of: settings.pillRightSlot) { _ in syncCollapsedPillHitRect() }
        .onChange(of: notchLayoutKey) { _ in syncCollapsedPillHitRect() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncCollapsedPillHitRect()
            PanelManager.shared.refreshCollapsedPillClickMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            syncCollapsedPillHitRect()
        }
        .onChange(of: claudeInteractionHint) { hint in
            guard hint != nil else { return }
            triggerClaudeRightSlotFlashIfNeeded()
        }
        .onChange(of: claudePillStatusTone) { tone in
            if tone == "warn" || tone == "error" {
                triggerClaudeRightSlotFlashIfNeeded()
            }
        }
    }

    private func syncCollapsedPillHitRect() {
        let n = NotchDetector.layoutNotch()
        if viewModel.state == .collapsed {
            let w = PillLayout.totalWidth(notch: n, left: settings.pillLeftSlot, right: settings.pillRightSlot)
            PanelManager.shared.syncIslandPanelLayout(notch: n, pillTotalWidth: w)
        } else {
            PanelManager.shared.repositionPanelWithNotchLayout(n)
        }
    }

    // MARK: - Collapsed

    private enum CollapsedWingSide {
        case left
        case right
    }

    /// 收缩态：底角为与边相切的圆弧（非 cornerRadius 近似曲线）。
    private var pillShape: FlaredTopTangentBottomRectangle {
        FlaredTopTangentBottomRectangle(
            topConvexRadius: settings.pillFlareRadius,
            topCornerFlare: 0.52,
            bottomFilletRadius: 12,
            bodyInsetX: PillLayout.visualWidthOverhang
        )
    }

    /// 收缩 pill 为纯黑底，前景固定浅色以保证对比度（与系统浅色/深色模式无关）。
    private var collapsedPillForeground: Color { .white }
    private var shouldShowClaudeBottomHint: Bool {
        guard let text = claudePillStatusText, !text.isEmpty else { return false }
        if claudePillStatusTone == "success" || claudePillStatusTone == "error" || claudePillStatusTone == "warn" {
            return true
        }
        return false
    }
    private var claudeHintExpansionHeight: CGFloat {
        if shouldShowClaudeBottomHint {
            return 14
        }
        return 0
    }

    /// 低功耗模式下电池轮廓用黄色，其余为默认淡化主色。
    private var pillBatteryIconColor: Color {
        if pillHud.batteryState.isLowPowerMode {
            return Color.yellow
        }
        return collapsedPillForeground.opacity(0.72)
    }

    private var collapsedView: some View {
        let totalW = PillLayout.totalWidth(notch: notch, left: settings.pillLeftSlot, right: settings.pillRightSlot)
        let visualW = totalW + 2 * PillLayout.visualWidthOverhang
        let coreW = PillLayout.coreNotchWidth(notch: notch)
        let hasLeft = settings.pillLeftSlot != .none
        let hasRight = settings.pillRightSlot != .none
        let isBatteryAccessoryVisible = pillHud.batteryState.isCharging || pillHud.batteryState.isExternalPowered
        let singleBatteryLeftOnly = (settings.pillLeftSlot == .battery && settings.pillRightSlot == .none)
        let singleBatteryRightOnly = (settings.pillLeftSlot == .none && settings.pillRightSlot == .battery)
        let singleBatteryOnly = (singleBatteryLeftOnly || singleBatteryRightOnly) && !isBatteryAccessoryVisible

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                if singleBatteryOnly {
                    let halfW = totalW / 2
                    if singleBatteryLeftOnly {
                        HStack(spacing: 0) {
                            batteryCompactContent()
                                .frame(width: halfW, height: notch.notchHeight, alignment: .center)
                            .offset(x: -15)
                            Color.clear.frame(width: halfW, height: notch.notchHeight)
                        }
                    } else {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: halfW, height: notch.notchHeight)
                            batteryCompactContent()
                                .frame(width: halfW, height: notch.notchHeight, alignment: .center)
                            .offset(x: -15)
                        }
                    }
                } else
                if hasLeft {
                    ZStack {
                        Color.clear
                        pillOneSide(
                            slot: settings.pillLeftSlot,
                            side: .left,
                            centerForSingleBattery: singleBatteryOnly && singleBatteryLeftOnly
                        )
                    }
                    .frame(width: PillLayout.leftWingTotalWidth(left: settings.pillLeftSlot), height: notch.notchHeight)
                }

                Color.clear.frame(width: coreW, height: notch.notchHeight)

                if hasRight {
                    ZStack {
                        Color.clear
                        if claudeRightSlotFlashVisible {
                            claudeCodeLogoMark(size: 13)
                                .opacity(claudeRightSlotFlashPulse ? 0.2 : 1)
                        } else {
                            pillOneSide(
                                slot: settings.pillRightSlot,
                                side: .right,
                                centerForSingleBattery: singleBatteryOnly && singleBatteryRightOnly
                            )
                        }
                    }
                    .frame(width: PillLayout.rightWingTotalWidth(right: settings.pillRightSlot), height: notch.notchHeight)
                }
            }
            .frame(height: notch.notchHeight)

            if claudeHintExpansionHeight > 0 {
                claudePillBottomHint
                    .frame(height: claudeHintExpansionHeight)
            }
        }
        .frame(width: totalW, height: notch.notchHeight + max(PillLayout.visualHeightOverhang, 2) + claudeHintExpansionHeight, alignment: .top)
        .frame(width: visualW, alignment: .center)
        .background(
            pillShape
                .fill(Color.black)
        )
        .clipShape(pillShape)
        .offset(y: -max(PillLayout.visualHeightOverhang, 2) / 2)
        .animation(.easeInOut(duration: 0.22), value: claudeHintExpansionHeight)
    }

    private func batteryCompactContent() -> some View {
        HStack(spacing: 4) {
            ZStack {
                Image(systemName: batteryPillBaseSymbol(pillHud.batteryState))
                    .font(.system(size: 19))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(pillBatteryIconColor)
                pillBatteryPercentLabel()
                    .offset(
                        x: Self.batteryPercentOpticalOffsetX(pillHud.batteryState.percent),
                        y: 0.5
                    )
            }
            .fixedSize()
        }
        .fixedSize()
    }

    @ViewBuilder
    private var claudePillBottomHint: some View {
        if shouldShowClaudeBottomHint, let text = claudePillStatusText, !text.isEmpty {
            let isWarning = claudePillStatusTone == "warn"
            let isError = claudePillStatusTone == "error"
            let isSuccess = claudePillStatusTone == "success"
            let iconName: String = {
                if isError { return "xmark.octagon.fill" }
                if isWarning || claudeInteractionHint != nil { return "exclamationmark.triangle.fill" }
                if isSuccess { return "checkmark.circle.fill" }
                if claudePillStatusTone == "busy" { return "hourglass" }
                return "terminal"
            }()
            let tint: Color = {
                if isError { return Color.red.opacity(0.95) }
                if isWarning || claudeInteractionHint != nil { return Color.orange.opacity(0.95) }
                if isSuccess { return Color.green.opacity(0.92) }
                if claudePillStatusTone == "busy" { return Color.blue.opacity(0.9) }
                return Color.white.opacity(0.72)
            }()
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint)
                Text(text)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func pillOneSide(slot: PillSideWidget, side: CollapsedWingSide, centerForSingleBattery: Bool = false) -> some View {
        // Pin content to the notch vertical edge (inner edge), not the pill outer edge.
        let innerPad = PillLayout.notchAdjacentGap + PillLayout.contentInsetFromNotchEdge
        let alignment: Alignment = centerForSingleBattery ? .center : ((side == .left) ? .trailing : .leading)
        let shouldBiasBatteryOutward = !centerForSingleBattery && !pillHud.batteryState.isCharging && !pillHud.batteryState.isExternalPowered
        let batteryOutwardOffset: CGFloat = shouldBiasBatteryOutward ? ((side == .left) ? -8 : 8) : 0

        switch slot {
        case .none:
            Color.clear
        case .battery:
            HStack(spacing: 4) {
                ZStack {
                    Image(systemName: batteryPillBaseSymbol(pillHud.batteryState))
                        .font(.system(size: 19))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(pillBatteryIconColor)
                    pillBatteryPercentLabel()
                        .offset(
                            x: Self.batteryPercentOpticalOffsetX(pillHud.batteryState.percent),
                            y: 0.5
                        )
                }
                .fixedSize()
                pillBatteryPowerAccessory(state: pillHud.batteryState)
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(side == .left ? .trailing : .leading, centerForSingleBattery ? 0 : innerPad)
            .offset(x: batteryOutwardOffset)
        case .networkSpeed:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 10, alignment: .center)
                    Text(pillHud.uploadRateText)
                        .font(.system(size: 8))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 10, alignment: .center)
                    Text(pillHud.downloadRateText)
                        .font(.system(size: 8))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(collapsedPillForeground.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(side == .left ? .trailing : .leading, innerPad)
        }
    }

    /// 叠字与电池内仓对齐：先前正向偏移在实机上会显得偏右，改为按位数略微左移（负 x）。
    private static func batteryPercentOpticalOffsetX(_ percent: Int?) -> CGFloat {
        guard let p = percent else { return 0 }
        switch p {
        case 100: return -1.25
        case 10..<100: return -0.85
        default: return -0.35
        }
    }

    /// 正在向电池充电时显示闪电；已接适配器但已满/涓流时 IOKit 常把 `IsCharging` 置为 false，改用电插头表示仍接电。
    @ViewBuilder
    private func pillBatteryPowerAccessory(state: BatteryPowerState) -> some View {
        if state.isCharging {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(collapsedPillForeground.opacity(0.98))
                .shadow(color: .black.opacity(0.35), radius: 0.75, x: 0, y: 0.5)
        } else if state.isExternalPowered {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(collapsedPillForeground.opacity(0.92))
                .shadow(color: .black.opacity(0.3), radius: 0.75, x: 0, y: 0.5)
        }
    }

    @ViewBuilder
    private func pillBatteryPercentLabel() -> some View {
        if let p = pillHud.batteryState.percent {
            Text("\(p)")
                .font(.system(size: 8))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(collapsedPillForeground.opacity(0.9))
        } else {
            Text("—")
                .font(.system(size: 8))
                .foregroundStyle(collapsedPillForeground.opacity(0.9))
        }
    }

    /// Pill 内叠字用：只返回电量格数符号，**不含** `.bolt`（闪电单独 overlay）。
    private func batteryPillBaseSymbol(_ state: BatteryPowerState) -> String {
        let p = state.percent
        if state.isExternalPowered || state.isCharging {
            return batteryLevelSymbol(percent: p, bolt: false)
        }
        if let p, p < 20 {
            return p < 10 ? "battery.0" : "battery.25"
        }
        return batteryLevelSymbol(percent: p, bolt: false)
    }

    private func batteryLevelSymbol(percent: Int?, bolt: Bool) -> String {
        let base: String
        guard let p = percent else {
            base = "battery.100"
            return bolt ? base + ".bolt" : base
        }
        switch p {
        case ..<10: base = "battery.0"
        case ..<35: base = "battery.25"
        case ..<60: base = "battery.50"
        case ..<85: base = "battery.75"
        default: base = "battery.100"
        }
        return bolt ? base + ".bolt" : base
    }

    // MARK: - Expanded 面板轮廓（非 pill）：顶左/顶右凸圆角 + 底左/底右相切凸圆弧

    private static let expandedTopCornerRadius: CGFloat = 16
    private static let expandedBottomFillet: CGFloat = 16

    private var expandedShape: ExpandedIslandPanelShape {
        ExpandedIslandPanelShape(
            topConvexRadius: Self.expandedTopCornerRadius,
            bottomFilletRadius: Self.expandedBottomFillet
        )
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Top bar — flush with screen top, no rounded corners
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    appStoreModeButton(mode: .appStore)
                    claudeModeButton(mode: .claude)
                }
                .padding(.leading, 10)

                Color.clear
                    .frame(height: notch.notchHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        exitLaunchpadEditMode()
                        viewModel.toggle()
                    }

                Button {
                    exitLaunchpadEditMode()
                    viewModel.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.65))
                        .frame(width: 32, height: notch.notchHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            switch expandedContentMode {
            case .appStore:
                SearchBarView(text: $viewModel.searchText)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .onTapGesture {
                        exitLaunchpadEditMode()
                    }

                // Switch view based on display mode (search always uses grid)
                if !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    AppGridView(
                        apps: viewModel.filteredApps,
                        onAppTap: { app in viewModel.launchApp(app) }
                    )
                } else {
                    switch settings.displayMode {
                    case .grid:
                        AppGridView(
                            apps: viewModel.filteredApps,
                            onAppTap: { app in viewModel.launchApp(app) }
                        )
                    case .alphabetical:
                        AlphabetGridView(
                            apps: viewModel.filteredApps,
                            onAppTap: { app in viewModel.launchApp(app) }
                        )
                    case .launchpad:
                        LaunchpadGridView(
                            allApps: viewModel.allApps,
                            onAppTap: { app in viewModel.launchApp(app) },
                            folderManager: FolderManager.shared,
                            isEditing: $isLaunchpadEditing
                        )
                    }
                }
            case .claude:
                claudePanelView
            }
        }
        // Leave horizontal margins for the top flare geometry; body width stays the same.
        .padding(.horizontal, Self.expandedTopCornerRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            expandedShape
                .fill(Color.black, style: FillStyle(antialiased: false))
        )
        // Avoid a light fringe around the panel edge when composited over the desktop.
        .clipShape(expandedShape, style: FillStyle(antialiased: false))
        .environment(\.useLightContentOnIslandPanel, true)
        .onChange(of: viewModel.state) { _ in
            exitLaunchpadEditMode()
        }
        .onChange(of: settings.displayMode) { _ in
            exitLaunchpadEditMode()
        }
        .onChange(of: viewModel.searchText) { text in
            if !text.isEmpty {
                exitLaunchpadEditMode()
            }
        }
    }

    private func appStoreModeButton(mode: ExpandedContentMode) -> some View {
        let selected = expandedContentMode == mode
        return Button {
            expandedContentMode = mode
        } label: {
            Text("A")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Color.white.opacity(0.95) : Color.white.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("应用面板")
    }

    private func claudeCodeLogoMark(size: CGFloat = 16) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.95, green: 0.54, blue: 0.22))
            ClaudeCodeLogoShape()
                .fill(Color.white)
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }

    private func claudeModeButton(mode: ExpandedContentMode) -> some View {
        let selected = expandedContentMode == mode
        return Button {
            expandedContentMode = mode
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
                ClaudeCodeLogoShape()
                    .fill(selected ? Color.white.opacity(0.95) : Color.white.opacity(0.65))
                    .padding(4.5)
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Claude 面板")
    }

    private var claudePanelView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                claudeCodeLogoMark(size: 16)
                Text("Claude")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            claudeInstallStatusSection

            if case .installed = claudeCLI.installStatus {
                if claudeCLI.projectDirectory == nil {
                    projectSelectionSection
                } else {
                    claudeSessionSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            claudeCLI.ensureDetected()
        }
        .onChange(of: claudeCLI.projectDirectory) { dir in
            guard dir != nil else { return }
            if !claudeCLI.isRunning {
                claudeCLI.isRunning = true
            }
        }
    }

    private var projectSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("项目路径")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 8) {
                if let dir = claudeCLI.projectDirectory {
                    Text(dir.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("未选择项目目录")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Button {
                    pickProjectDirectory()
                } label: {
                    Text("选择目录")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.9))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    private var claudeInstallStatusSection: some View {
        Group {
            switch claudeCLI.installStatus {
            case .unknown, .checking:
                Text("正在检测本机 Claude CLI…")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .missing(let reason):
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .installed:
                EmptyView()
            }
        }
    }

    private var claudeSessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Claude 会话")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button {
                    pickProjectDirectory()
                } label: {
                    Text("切换目录")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .buttonStyle(.plain)
            }

            if let dir = claudeCLI.projectDirectory,
               case let .installed(path) = claudeCLI.installStatus {

                HStack(spacing: 10) {
                    if claudeCLI.isRunning {
                        Button {
                            claudeCLI.isRunning = false
                        } label: {
                            Text("停止")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            claudeCLI.isRunning = true
                        } label: {
                            Text("启动")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.9))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        claudeCLI.isRunning = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            claudeCLI.isRunning = true
                        }
                    } label: {
                        Text("重新启动")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                if let hint = claudeInteractionHint, !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                }

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay {
                        ClaudeTerminalView(
                            cliPath: path,
                            workingDirectory: dir,
                            isRunning: $claudeCLI.isRunning,
                            lastError: $claudeCLI.lastError,
                            interactionHint: $claudeInteractionHint,
                            latestStatusText: $claudePillStatusText,
                            latestStatusTone: $claudePillStatusTone
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let error = claudeCLI.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func exitLaunchpadEditMode() {
        if isLaunchpadEditing {
            withAnimation(.easeInOut(duration: 0.2)) {
                isLaunchpadEditing = false
            }
        }
    }

    private func pickProjectDirectory() {
        // 目录选择期间关闭“点击外部收起”，避免面板被误判收起。
        PanelManager.shared.stopClickOutsideMonitor()

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.title = "选择 Claude 项目目录"

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.urls.first {
                    claudeCLI.projectDirectory = url
                }
                ensureClaudePanelExpanded()
            }
        } else if panel.runModal() == .OK, let url = panel.urls.first {
            claudeCLI.projectDirectory = url
            ensureClaudePanelExpanded()
        } else {
            ensureClaudePanelExpanded()
        }
    }

    private func ensureClaudePanelExpanded() {
        if viewModel.state != .expanded {
            viewModel.toggle()
        }
        PanelManager.shared.setExpanded()
    }

    private func triggerClaudeRightSlotFlashIfNeeded() {
        if claudeRightSlotFlashVisible { return }
        let now = Date()
        // 防抖：避免 Claude 高频输出时连续闪烁影响可读性。
        guard now.timeIntervalSince(lastClaudeFlashAt) > 1.2 else { return }
        lastClaudeFlashAt = now
        claudeRightSlotFlashVisible = true
        claudeRightSlotFlashPulse = false
        withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
            claudeRightSlotFlashPulse = true
        }
    }

    private func stopClaudeRightSlotFlash() {
        claudeRightSlotFlashVisible = false
        claudeRightSlotFlashPulse = false
    }

}
