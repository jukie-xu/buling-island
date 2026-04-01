import SwiftUI
import AppKit

struct IslandView: View {

    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var pillHud = PillHudViewModel()
    @StateObject private var claudeCLI = ClaudeCLIService()
    @StateObject private var iTerm2Integration = ITerm2IntegrationService()
    @State private var isLaunchpadEditing = false
    @State private var expandedContentMode: ExpandedContentMode = .appStore
    @State private var claudeInteractionHint: String?
    @State private var claudePillStatusText: String?
    @State private var claudePillStatusTone: String = "info"
    @State private var claudeRightSlotFlashVisible = false
    @State private var claudeRightSlotFlashPulse = false
    @State private var lastClaudeFlashAt: Date = .distantPast
    @State private var claudeSessionRenderNonce: Int = 0
    @State private var claudeStatusRevision: Int = 0
    @State private var claudeBottomHintCollapsed = false
    @State private var claudeBottomHintAutoCollapseWorkItem: DispatchWorkItem?
    @State private var claudeRelaunchWorkItem: DispatchWorkItem?
    @State private var claudePendingAutoStart = false
    @State private var taskBreathPhase = false
    @State private var taskWavePhase = false
    @State private var pillSuppressedIssueUntil: [String: Date] = [:]

    private enum ExpandedContentMode {
        case appStore
        case claude
        case tasks
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
            let pillH = notch.notchHeight + 1 + claudeHintExpansionHeight

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
            refreshClaudeBottomHintAutoCollapse()
            syncITerm2CaptureConfig()
            if !taskBreathPhase {
                withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                    taskBreathPhase = true
                }
            }
            if !taskWavePhase {
                withAnimation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true)) {
                    taskWavePhase = true
                }
            }
        }
        .onChange(of: viewModel.state) { newState in
            if newState == .collapsed {
                pillHud.start()
                syncCollapsedPillHitRect()
            } else {
                pillHud.stop()
                stopClaudeRightSlotFlash()
                clearPillAlertsAfterOpen()
            }
            syncITerm2CaptureConfig()
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
            refreshClaudeBottomHintAutoCollapse()
        }
        .onChange(of: claudePillStatusText) { _ in
            refreshClaudeBottomHintAutoCollapse()
        }
        .onChange(of: claudeStatusRevision) { _ in
            if claudeInteractionHint != nil || claudePillStatusTone == "warn" || claudePillStatusTone == "error" {
                triggerClaudeRightSlotFlashIfNeeded()
            }
            refreshClaudeBottomHintAutoCollapse()
        }
        .onChange(of: claudeCLI.lastError) { err in
            guard let err, !err.isEmpty else { return }
            if isPillIssueSuppressed(text: err, tone: "error") {
                return
            }
            claudePillStatusText = "错误: \(err)"
            claudePillStatusTone = "error"
            claudeStatusRevision &+= 1
            triggerClaudeRightSlotFlashIfNeeded()
            refreshClaudeBottomHintAutoCollapse()
        }
        .onChange(of: settings.claudeStretchHintEnabled) { enabled in
            if !enabled {
                claudeBottomHintCollapsed = true
                claudeBottomHintAutoCollapseWorkItem?.cancel()
                claudeBottomHintAutoCollapseWorkItem = nil
            } else {
                claudeBottomHintCollapsed = false
                refreshClaudeBottomHintAutoCollapse()
            }
        }
        .onChange(of: settings.claudeHintAutoCollapseEnabled) { _ in
            refreshClaudeBottomHintAutoCollapse()
        }
        .onChange(of: settings.claudeHintAutoCollapseDelay) { _ in
            refreshClaudeBottomHintAutoCollapse()
        }
        .onChange(of: settings.claudeEnableITerm2Capture) { _ in
            syncITerm2CaptureConfig()
        }
        .onChange(of: settings.claudeITerm2PollInterval) { _ in
            syncITerm2CaptureConfig()
        }
        .onChange(of: expandedContentMode) { mode in
            if mode == .tasks {
                syncITerm2CaptureConfig()
            }
        }
        .onChange(of: iTerm2Integration.statusRevision) { _ in
            if let text = iTerm2Integration.latestStatusText, !text.isEmpty {
                let tone = iTerm2Integration.latestStatusTone
                if tone == "warn" || tone == "error" || tone == "success" {
                    if let tail = iTerm2Integration.latestStatusSourceTail, !tail.isEmpty {
                        if tone == "error" {
                            let extracted = lastErrorText(from: tail)
                            if isPillIssueSuppressed(text: extracted, tone: tone) {
                                return
                            }
                            claudePillStatusText = extracted
                        } else {
                            let extracted = lastQuestionText(from: tail)
                            if isPillIssueSuppressed(text: extracted, tone: tone) {
                                return
                            }
                            claudePillStatusText = extracted
                        }
                    } else {
                        if isPillIssueSuppressed(text: text, tone: tone) {
                            return
                        }
                        claudePillStatusText = text
                    }
                    claudePillStatusTone = tone
                    claudeStatusRevision &+= 1
                    if tone == "warn" || tone == "error" {
                        triggerClaudeRightSlotFlashIfNeeded()
                    }
                }
            }
            if let hint = iTerm2Integration.interactionHint, !hint.isEmpty {
                claudeInteractionHint = hint
            }
            if let err = iTerm2Integration.lastError, !err.isEmpty {
                claudePillStatusText = err
                claudePillStatusTone = "error"
                claudeStatusRevision &+= 1
                triggerClaudeRightSlotFlashIfNeeded()
            }
            refreshClaudeBottomHintAutoCollapse()
        }
        .onChange(of: claudeCLI.installStatus) { status in
            guard claudePendingAutoStart else { return }
            guard claudeCLI.projectDirectory != nil else { return }
            if case .installed = status {
                claudePendingAutoStart = false
                startClaudeSession()
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
        guard settings.claudeStretchHintEnabled else { return false }
        if claudeBottomHintCollapsed { return false }
        return shouldShowClaudeBottomHintRaw
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
        .frame(width: totalW, height: notch.notchHeight + claudeHintExpansionHeight, alignment: .top)
        .frame(width: visualW, alignment: .center)
        .background(
            pillShape
                .fill(Color.black)
        )
        .clipShape(pillShape)
        .offset(y: 0)
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

    private var taskFontBase: CGFloat {
        CGFloat(settings.taskPanelFontSize)
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Top bar — flush with screen top, no rounded corners
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    appStoreModeButton(mode: .appStore)
                    claudeModeButton(mode: .claude)
                    taskModeButton(mode: .tasks)
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
            case .tasks:
                claudeTaskBoardSection
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
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
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
                AppPanelIconMark(size: 14, active: true)
            }
            .frame(width: 24, height: 24)
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
                ClaudePanelIconMark(size: 14, active: true)
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Claude 面板")
    }

    private func taskModeButton(mode: ExpandedContentMode) -> some View {
        let selected = expandedContentMode == mode
        return Button {
            expandedContentMode = mode
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
                TaskPanelIconMark(size: 14, active: true)
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Task 面板")
    }

    private var claudePanelView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                claudeCodeLogoMark(size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(claudeCLI.projectDirectory?.path ?? "未选择项目目录")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(claudeCLI.projectDirectory == nil ? 0.45 : 0.68))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
                claudeTopRightToolbar
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
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            claudeCLI.ensureDetected()
        }
        .onChange(of: claudeCLI.projectDirectory) { dir in
            guard dir != nil else { return }
            if !claudeCLI.isRunning {
                startClaudeSession()
            }
        }
    }

    @ViewBuilder
    private var claudeTopRightToolbar: some View {
        if case .installed = claudeCLI.installStatus, claudeCLI.projectDirectory != nil {
            HStack(spacing: 8) {
                Text("Claude 会话")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                Button {
                    pickProjectDirectory()
                } label: {
                    Text("切换目录")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)

                if claudeCLI.isRunning {
                    Button {
                        stopClaudeSession(clearSurface: true)
                    } label: {
                        Text("停止")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.42), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        resetClaudeSessionAndRelaunch(shouldRelaunch: true)
                    } label: {
                        Text("启动")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.92))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    resetClaudeSessionAndRelaunch(shouldRelaunch: true)
                } label: {
                    Text("重启")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var projectSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("项目目录")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))

            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))

                Text("选择一个目录作为 Claude 的工作区")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))

                Text("建议直接选择你的项目根目录，之后会自动启动终端会话。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)

                Button {
                    pickProjectDirectory()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .semibold))
                        Text("选择目录")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, minHeight: 210, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var claudeInstallStatusSection: some View {
        Group {
            switch claudeCLI.installStatus {
            case .unknown, .checking:
                Text("正在检测本机 Claude CLI…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .missing(let reason):
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red.opacity(0.12))
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .installed:
                EmptyView()
            }
        }
    }

    private var claudeSessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let dir = claudeCLI.projectDirectory,
               case let .installed(path) = claudeCLI.installStatus {
                if settings.claudeEnableITerm2Capture {
                    iTerm2SessionStrip
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

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay {
                        ClaudeTerminalView(
                            cliPath: path,
                            workingDirectory: dir,
                            isRunning: $claudeCLI.isRunning,
                            lastError: $claudeCLI.lastError,
                            interactionHint: $claudeInteractionHint,
                            latestStatusText: $claudePillStatusText,
                            latestStatusTone: $claudePillStatusTone,
                            latestStatusRevision: $claudeStatusRevision,
                            currentSessionNonce: $claudeSessionRenderNonce
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(claudeSessionRenderNonce)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let error = claudeCLI.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var claudeTaskBoardSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(taskGroups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(group.name)
                                .font(.system(size: taskFontBase, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                            Spacer()
                            Text("\(group.tasks.count) 个任务")
                                .font(.system(size: max(9, taskFontBase - 2)))
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        if group.tasks.isEmpty {
                            Text("暂无捕获任务")
                                .font(.system(size: max(10, taskFontBase - 1)))
                                .foregroundStyle(.white.opacity(0.42))
                                .padding(.vertical, 6)
                        } else {
                            ForEach(group.tasks, id: \.id) { task in
                                let visual = taskVisualMeta(for: task)
                                let isMuted = iTerm2Integration.isSessionMuted(task.id)
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(alignment: .center, spacing: 8) {
                                        Circle()
                                            .fill(visual.color)
                                            .frame(width: 9, height: 9)
                                            .shadow(color: visual.color.opacity(0.55), radius: visual.isRunning ? 4 : 1, x: 0, y: 0)
                                            .opacity(taskBreathPhase ? 1 : 0.7)
                                            .scaleEffect(taskBreathPhase ? 1 : 0.84)

                                        if isMuted {
                                            Image(systemName: "speaker.slash.fill")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.45))
                                        }

                                        Text(task.title.isEmpty ? "Claude 任务" : task.title)
                                            .font(.system(size: taskFontBase, weight: .semibold))
                                            .foregroundStyle(.white.opacity(isMuted ? 0.82 : 0.93))
                                            .lineLimit(1)

                                        Spacer(minLength: 6)

                                        HStack(spacing: 6) {
                                            Toggle(
                                                "Mute",
                                                isOn: Binding(
                                                    get: { isMuted },
                                                    set: { iTerm2Integration.setSessionMuted($0, sessionID: task.id) }
                                                )
                                            )
                                            .toggleStyle(.switch)
                                            .controlSize(.mini)
                                            .tint(isMuted ? Color(red: 0.33, green: 0.46, blue: 0.62) : Color(white: 0.22))
                                            .labelsHidden()
                                            .help("静音该会话：不再在 pill 提醒")

                                            Text("Mute")
                                                .font(.system(size: max(8, taskFontBase - 3), weight: .semibold))
                                            .foregroundStyle(.white.opacity(isMuted ? 0.94 : 0.55))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(isMuted ? Color(red: 0.20, green: 0.26, blue: 0.33).opacity(0.9) : Color.white.opacity(0.07))
                                        )
                                    }

                                    Text(taskSecondaryText(for: task, visual: visual))
                                        .font(.system(size: taskFontBase, weight: .medium))
                                        .foregroundStyle(.white.opacity(isMuted ? 0.68 : (visual.isRunning ? (taskBreathPhase ? 0.9 : 0.72) : 0.82)))
                                        .lineLimit(2)
                                        .truncationMode(.tail)

                                    HStack(spacing: 6) {
                                        Text(task.terminalApp)
                                        Text("·")
                                        Text(task.tty.isEmpty ? "tty 未知" : task.tty)
                                    }
                                    .font(.system(size: max(9, taskFontBase - 2), weight: .medium))
                                    .foregroundStyle(.white.opacity(isMuted ? 0.45 : 0.52))
                                    .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(taskRowBackgroundColor(visual: visual, isMuted: isMuted))
                                        .overlay {
                                            if visual.isRunning {
                                                taskRunningWaveOverlay(isMuted: isMuted)
                                            }
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(taskRowBorderColor(visual: visual, isMuted: isMuted), lineWidth: 1)
                                        )
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onTapGesture {
                                    jumpToExternalTask(session: task)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("监控动作")
                            .font(.system(size: taskFontBase, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                        Spacer()
                        Text(iTerm2Integration.monitorHeartbeatText ?? "未启动")
                            .font(.system(size: max(9, taskFontBase - 2)))
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(1)
                    }
                    if iTerm2Integration.monitorActions.isEmpty {
                        Text("暂无动作日志")
                            .font(.system(size: max(10, taskFontBase - 1)))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.vertical, 6)
                    } else {
                        ForEach(Array(iTerm2Integration.monitorActions.suffix(8).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: max(9, taskFontBase - 2)))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
            .padding(.top, 2)
        }
    }

    private var taskGroups: [(name: String, tasks: [ITerm2IntegrationService.Session])] {
        let captured = Dictionary(grouping: iTerm2Integration.sessions) { session in
            session.terminalApp.isEmpty ? "iTerm2" : session.terminalApp
        }
        let orderedNames = ["iTerm2", "iTerm", "Ghostty", "Terminal"]
        var result: [(name: String, tasks: [ITerm2IntegrationService.Session])] = []
        for name in orderedNames {
            result.append((name: name, tasks: captured[name] ?? []))
        }
        for (name, tasks) in captured where !orderedNames.contains(name) {
            result.append((name: name, tasks: tasks))
        }
        return result
    }

    @ViewBuilder
    private var iTerm2SessionStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("iTerm2 会话")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Circle()
                    .fill(iTerm2Integration.isITerm2Running ? Color.green.opacity(0.9) : Color.white.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(iTerm2Integration.isITerm2Running ? "运行中" : "未运行")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Text("\(iTerm2Integration.sessions.count) 个 Claude 会话")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            if !iTerm2Integration.sessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(iTerm2Integration.sessions.prefix(5)) { session in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.title.isEmpty ? "Claude" : session.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.86))
                                    .lineLimit(1)
                                Text(session.tty.isEmpty ? "tty 未知" : session.tty)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                    }
                }
            }
        }
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
        claudeRelaunchWorkItem?.cancel()
        claudeRelaunchWorkItem = nil
        clearClaudeSessionSurface()
        claudeSessionRenderNonce &+= 1
        claudeCLI.isRunning = false

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
                    startClaudeSession()
                }
                ensureClaudePanelExpanded()
            }
        } else if panel.runModal() == .OK, let url = panel.urls.first {
            claudeCLI.projectDirectory = url
            startClaudeSession()
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

    private func clearClaudeSessionSurface() {
        claudeInteractionHint = nil
        claudePillStatusText = nil
        claudePillStatusTone = "info"
        claudeStatusRevision &+= 1
        claudeCLI.lastError = nil
        claudeBottomHintCollapsed = false
        claudeBottomHintAutoCollapseWorkItem?.cancel()
        claudeBottomHintAutoCollapseWorkItem = nil
        stopClaudeRightSlotFlash()
    }

    private func resetClaudeSessionAndRelaunch(shouldRelaunch: Bool) {
        stopClaudeSession(clearSurface: true)
        guard shouldRelaunch else { return }
        startClaudeSession()
    }

    private func stopClaudeSession(clearSurface: Bool) {
        claudeRelaunchWorkItem?.cancel()
        claudeRelaunchWorkItem = nil
        claudePendingAutoStart = false
        claudeCLI.isRunning = false
        if clearSurface {
            clearClaudeSessionSurface()
        }
        claudeSessionRenderNonce &+= 1
    }

    private func startClaudeSession() {
        claudeRelaunchWorkItem?.cancel()
        claudeRelaunchWorkItem = nil

        // 每次启动都重建终端视图，避免旧会话残留状态污染。
        claudeSessionRenderNonce &+= 1
        clearClaudeSessionSurface()
        guard claudeCLI.projectDirectory != nil else { return }
        guard case .installed = claudeCLI.installStatus else {
            claudePendingAutoStart = true
            claudeCLI.ensureDetected()
            return
        }
        claudePendingAutoStart = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            claudeCLI.isRunning = true
        }
    }

    private var shouldShowClaudeBottomHintRaw: Bool {
        if let err = claudeCLI.lastError, !err.isEmpty { return true }
        guard let text = claudePillStatusText, !text.isEmpty else { return false }
        return claudePillStatusTone == "success" || claudePillStatusTone == "error" || claudePillStatusTone == "warn"
    }

    private func refreshClaudeBottomHintAutoCollapse() {
        claudeBottomHintAutoCollapseWorkItem?.cancel()
        claudeBottomHintAutoCollapseWorkItem = nil

        guard settings.claudeStretchHintEnabled else {
            claudeBottomHintCollapsed = true
            return
        }

        guard shouldShowClaudeBottomHintRaw else {
            claudeBottomHintCollapsed = false
            return
        }

        claudeBottomHintCollapsed = false

        guard settings.claudeHintAutoCollapseEnabled else { return }
        let delay = max(1, settings.claudeHintAutoCollapseDelay)
        let work = DispatchWorkItem {
            self.claudeBottomHintCollapsed = true
        }
        claudeBottomHintAutoCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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

    private func syncITerm2CaptureConfig() {
        let shouldEnableCapture = settings.claudeEnableITerm2Capture || expandedContentMode == .tasks
        let effectivePollInterval: Double = {
            if viewModel.state == .expanded {
                // 展开态提升刷新频率，让任务输出更接近实时滚动更新。
                return min(settings.claudeITerm2PollInterval, 0.6)
            }
            return settings.claudeITerm2PollInterval
        }()
        iTerm2Integration.updateConfig(
            enabled: shouldEnableCapture,
            pollInterval: effectivePollInterval
        )
    }

    private func clearPillAlertsAfterOpen() {
        if let text = claudePillStatusText, !text.isEmpty {
            suppressPillIssue(text: text, tone: claudePillStatusTone, seconds: 180)
        }
        iTerm2Integration.acknowledgeAllCurrentIssues()
        claudePillStatusText = nil
        claudePillStatusTone = "info"
        claudeInteractionHint = nil
        claudeStatusRevision &+= 1
        claudeBottomHintCollapsed = false
        claudeBottomHintAutoCollapseWorkItem?.cancel()
        claudeBottomHintAutoCollapseWorkItem = nil
        stopClaudeRightSlotFlash()
    }

    private func jumpToExternalTask(session: ITerm2IntegrationService.Session) {
        iTerm2Integration.acknowledgeCurrentIssue(for: session)
        iTerm2Integration.activate(session: session)
        if viewModel.state == .expanded {
            viewModel.toggle()
        }
        PanelManager.shared.setCollapsed()
    }

    private enum TaskStatusKind {
        case idle
        case inactiveNoClaude
        case running
        case success
        case error
    }

    private func taskVisualMeta(for session: ITerm2IntegrationService.Session) -> (color: Color, isRunning: Bool, kind: TaskStatusKind) {
        let lines = normalizedTaskOutputLines(from: session.tailOutput)
        let compact = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = compact.lowercased()
        let seemsClaudeSession = looksLikeClaudeSession(session)
        if !seemsClaudeSession {
            return (Color.gray.opacity(0.85), false, .inactiveNoClaude)
        }
        if compact.isEmpty {
            return (Color.green.opacity(0.95), false, .idle)
        }
        if lower.contains("error") || lower.contains("failed") || lower.contains("exception")
            || lower.contains("auth_error") || lower.contains("unauthorized") || lower.contains("401")
            || lower.contains("timeout") || lower.contains("timed out")
            || lower.contains("报错") || lower.contains("失败") || lower.contains("错误") || lower.contains("超时") {
            return (Color.red.opacity(0.92), false, .error)
        }
        if iTerm2Integration.activeSessionIDs.contains(session.id) {
            return (Color.green.opacity(0.95), true, .running)
        }
        if lower.contains("done") || lower.contains("completed") || lower.contains("finished")
            || lower.contains("success") || lower.contains("已完成") || lower.contains("成功") || lower.contains("完成") {
            return (Color.green.opacity(0.95), false, .success)
        }
        if lower.contains("allow") || lower.contains("approve") || lower.contains("confirm")
            || lower.contains("[y/n]") || lower.contains("(y/n)")
            || lower.contains("请确认") || lower.contains("请选择") || lower.contains("是否允许")
            || lower.contains("running") || lower.contains("executing") || lower.contains("processing")
            || lower.contains("thinking") || lower.contains("analyzing")
            || lower.contains("处理中") || lower.contains("执行中") || lower.contains("思考中") {
            return (Color.green.opacity(0.95), true, .running)
        }
        return (Color.green.opacity(0.95), false, .idle)
    }

    private func looksLikeClaudeSession(_ session: ITerm2IntegrationService.Session) -> Bool {
        let titleLower = session.title.lowercased()
        let tailLower = session.tailOutput.lowercased()
        let claudeMarkers = [
            "claude",
            "claude code",
            "what should claude do",
            "billowing",
            "sonnet",
            "ask claude",
            "esc to interrupt"
        ]
        if titleLower.contains("claude") {
            return true
        }
        return claudeMarkers.contains(where: { tailLower.contains($0) })
    }

    private func taskSecondaryText(
        for session: ITerm2IntegrationService.Session,
        visual: (color: Color, isRunning: Bool, kind: TaskStatusKind)
    ) -> String {
        if visual.kind == .idle {
            return "当前未运行任务"
        }
        if visual.kind == .inactiveNoClaude {
            return "当前会话未启动 claude"
        }
        if visual.kind == .error {
            return taskPromptAndErrorTextTwoLines(from: session.tailOutput)
        }
        return taskPromptAndReplyTextTwoLines(from: session.tailOutput)
    }

    private func taskRowBackgroundColor(
        visual: (color: Color, isRunning: Bool, kind: TaskStatusKind),
        isMuted: Bool
    ) -> Color {
        let base: Color = {
            switch visual.kind {
            case .idle:
                return Color.green.opacity(0.14)
            case .inactiveNoClaude:
                return Color.gray.opacity(0.14)
            case .running:
                return Color.green.opacity(0.16)
            case .success:
                return Color.green.opacity(0.14)
            case .error:
                return Color.red.opacity(0.16)
            }
        }()
        if isMuted { return base.opacity(0.35) }
        return base
    }

    private func taskRowBorderColor(
        visual: (color: Color, isRunning: Bool, kind: TaskStatusKind),
        isMuted: Bool
    ) -> Color {
        let base: Color = {
            switch visual.kind {
            case .idle:
                return Color.green.opacity(0.30)
            case .inactiveNoClaude:
                return Color.gray.opacity(0.28)
            case .running:
                return Color.green.opacity(0.34)
            case .success:
                return Color.green.opacity(0.30)
            case .error:
                return Color.red.opacity(0.34)
            }
        }()
        if isMuted { return base.opacity(0.45) }
        return base
    }

    private func lastQuestionText(from tail: String) -> String {
        let lines = normalizedTaskOutputLines(from: tail)
        for line in lines.reversed() {
            if line.hasSuffix("?") || line.contains("？") {
                return line
            }
            if line.hasPrefix(">") {
                return line
            }
        }
        if let last = lines.last {
            if last.count > 88 { return String(last.prefix(88)) + "…" }
            return last
        }
        return "暂无可展示输出"
    }

    private func taskPromptAndReplyTextTwoLines(from tail: String) -> String {
        let displayLines = normalizedTaskDisplayLines(from: tail)
        let latestPrompt = extractLatestUserPrompt(from: tail)
        let latestReply = displayLines.reversed().first(where: { !isUserInputCommandLine($0) })

        if let prompt = latestPrompt, let reply = latestReply {
            return "\(truncateLine(prompt, max: 30))\n\(truncateLine(reply, max: 88))"
        }
        if let reply = latestReply {
            return "（未识别到提问）\n\(truncateLine(reply, max: 88))"
        }
        return lastQuestionText(from: tail)
    }

    private func taskPromptAndErrorTextTwoLines(from tail: String) -> String {
        let latestPrompt = extractLatestUserPrompt(from: tail)
        let errorText = lastErrorText(from: tail)

        if let prompt = latestPrompt {
            return "\(truncateLine(prompt, max: 30))\n\(truncateLine(errorText, max: 88))"
        }
        return "（未识别到提问）\n\(truncateLine(errorText, max: 88))"
    }

    private func lastErrorText(from tail: String) -> String {
        let lines = normalizedTaskOutputLines(from: tail)

        let markers = ["error", "failed", "exception", "unauthorized", "auth_error", "401", "timeout", "报错", "失败", "错误", "超时"]
        for line in lines.reversed() {
            let lower = line.lowercased()
            if markers.contains(where: { lower.contains($0) }) {
                if line.count > 88 { return String(line.prefix(88)) + "…" }
                return line
            }
        }
        if let last = lines.last {
            if last.count > 88 { return String(last.prefix(88)) + "…" }
            return last
        }
        return "检测到异常"
    }

    private func isBannedClaudePromptLine(_ line: String) -> Bool {
        _ = line
        return false
    }

    private func isTaskNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let noiseMarkers = [
            "esc to interrupt",
            "image in clipboard",
            "ctrl+v to paste",
            "for shortcuts",
            "update available",
            "run: brew upgrade claude-code",
            "claude code (",
            "claude code v",
            "sonnet",
            "api usage",
            "recent activity",
            "tips for getting started",
            "welcome back"
        ]
        if noiseMarkers.contains(where: { lower.contains($0) }) {
            return true
        }
        // 纯装饰线/分隔线等无业务含义文本。
        let stripped = lower.replacingOccurrences(of: " ", with: "")
        if stripped.allSatisfy({ "-_=|·•:".contains($0) }) {
            return true
        }
        return false
    }

    private func isClaudeInputAreaLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let inputMarkers = [
            "send message",
            "shift+enter",
            "press enter",
            "type a message",
            "ask claude",
            "esc to interrupt"
        ]
        if inputMarkers.contains(where: { lower.contains($0) }) {
            return true
        }

        // Claude TUI 输入区/边框字符（常见于底部双输入框并排）。
        if line.contains("╭") || line.contains("╰")
            || line.contains("┌") || line.contains("└")
            || line.contains("│") || line.contains("┃")
            || line.contains("┆") || line.contains("─") {
            return true
        }

        // 纯占位输入前缀："> "、":" 等
        if line == ":" || line == ">" || line.hasPrefix("> ") {
            return true
        }
        return false
    }

    private func isUserInputCommandLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("❯") || trimmed.hasPrefix("›") || trimmed.hasPrefix("»") || trimmed.hasPrefix(">") {
            return true
        }
        return false
    }

    private func extractLatestUserPrompt(from tail: String) -> String? {
        let lines = tail
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            guard isUserInputCommandLine(line) else { continue }
            var prompt = line
                .replacingOccurrences(of: "^[❯›»>]\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.isEmpty { continue }
            if isTaskNoiseLine(prompt) || isClaudeInputAreaLine(prompt) { continue }
            // 避免把 Claude 的输出占位句误当“用户输入内容”
            if prompt.lowercased().contains("what should claude do") { continue }
            if prompt.count > 120 {
                prompt = String(prompt.prefix(120))
            }
            return prompt
        }
        return nil
    }

    private func normalizedTaskOutputLines(from tail: String) -> [String] {
        tail
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isUserInputCommandLine($0) }
            .filter { !isBannedClaudePromptLine($0) }
            .filter { !isTaskNoiseLine($0) }
            .filter { !isClaudeInputAreaLine($0) }
    }

    private func normalizedTaskDisplayLines(from tail: String) -> [String] {
        tail
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isTaskNoiseLine($0) }
            .filter { !isClaudeInputAreaLine($0) }
    }

    private func truncateLine(_ text: String, max: Int) -> String {
        if text.count <= max { return text }
        return String(text.prefix(max)) + "…"
    }

    @ViewBuilder
    private func taskRunningWaveOverlay(isMuted: Bool) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.00),
                            Color.white.opacity(isMuted ? 0.03 : 0.06),
                            Color.white.opacity(0.00)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * 0.68)
                .offset(x: taskWavePhase ? width * 0.24 : -width * 0.24)
                .blur(radius: 7)
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func stopClaudeRightSlotFlash() {
        claudeRightSlotFlashVisible = false
        claudeRightSlotFlashPulse = false
    }

    private func isPillIssueSuppressed(text: String, tone: String) -> Bool {
        purgeExpiredPillSuppressions()
        let key = pillIssueKey(text: text, tone: tone)
        if let until = pillSuppressedIssueUntil[key], until > Date() {
            return true
        }
        return false
    }

    private func suppressPillIssue(text: String, tone: String, seconds: TimeInterval) {
        let key = pillIssueKey(text: text, tone: tone)
        pillSuppressedIssueUntil[key] = Date().addingTimeInterval(seconds)
        purgeExpiredPillSuppressions()
    }

    private func purgeExpiredPillSuppressions() {
        let now = Date()
        pillSuppressedIssueUntil = pillSuppressedIssueUntil.filter { $0.value > now }
    }

    private func pillIssueKey(text: String, tone: String) -> String {
        var normalized = text.lowercased()
        normalized = normalized.replacingOccurrences(of: "[0-9a-f]{6,}", with: "#", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "\\b\\d+\\b", with: "#", options: .regularExpression)
        return "\(tone)|\(normalized)"
    }

}
