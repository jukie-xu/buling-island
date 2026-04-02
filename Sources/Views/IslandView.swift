import SwiftUI
import AppKit

struct IslandView: View {

    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var pillHud = PillHudViewModel()
    @StateObject private var claudeCLI = ClaudeCLIService()
    @StateObject private var terminalCapture = TerminalCaptureService()
    @StateObject private var taskSessionEngine = TaskSessionEngine()
    @State private var isLaunchpadEditing = false
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
            viewModel.syncCollapsedPillTone(claudePillStatusTone)
            if viewModel.state == .collapsed {
                pillHud.start()
                syncCollapsedPillHitRect()
            }
            refreshClaudeBottomHintAutoCollapse()
            syncTerminalCaptureConfig()
            refreshTaskSnapshots()
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
            syncTerminalCaptureConfig()
        }
        .onChange(of: settings.pillLeftSlot) { _ in syncCollapsedPillHitRect() }
        .onChange(of: settings.pillRightSlot) { _ in syncCollapsedPillHitRect() }
        .onChange(of: claudeHintExpansionHeight) { _ in syncCollapsedPillHitRect() }
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
            viewModel.syncCollapsedPillTone(tone)
            if tone == "error" || tone == "warn", viewModel.pillAbnormalExpandTarget == nil {
                viewModel.notePillAbnormalFromClaudePanel()
            }
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
            viewModel.notePillAbnormalFromClaudePanel()
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
            syncTerminalCaptureConfig()
        }
        .onChange(of: settings.claudeITerm2PollInterval) { _ in
            syncTerminalCaptureConfig()
        }
        .onChange(of: settings.defaultExpandedPanel) { newDefault in
            if viewModel.state == .collapsed {
                viewModel.expandedPanelMode = newDefault
            }
        }
        .onChange(of: viewModel.expandedPanelMode) { mode in
            if mode == .tasks {
                syncTerminalCaptureConfig()
                refreshTaskSnapshots()
                TerminalAutomationAccessProber.requestPromptsForSupportedTerminalHosts()
            }
        }
        .onChange(of: terminalCapture.sessions) { _ in
            refreshTaskSnapshots()
        }
        .onChange(of: terminalCapture.activeSessionIDs) { _ in
            refreshTaskSnapshots()
        }
        .onChange(of: terminalCapture.statusRevision) { _ in
            refreshTaskSnapshots()
            if let text = terminalCapture.latestStatusText, !text.isEmpty {
                let tone = terminalCapture.latestStatusTone
                if tone == "warn" || tone == "error" || tone == "success" {
                    if let tail = terminalCapture.latestStatusSourceTail, !tail.isEmpty {
                        if tone == "error" {
                            let extracted = TaskSessionTextToolkit.lastErrorText(from: tail)
                            if isPillIssueSuppressed(text: extracted, tone: tone) {
                                return
                            }
                            claudePillStatusText = extracted
                        } else {
                            let compact = TaskSessionTextToolkit.compactTailText(tail)
                            let extracted = compact.isEmpty
                                ? text
                                : TaskSessionTextToolkit.truncate(compact, max: 88)
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
            claudeInteractionHint = terminalCapture.interactionHint.flatMap { $0.isEmpty ? nil : $0 }
            if let err = terminalCapture.lastError, !err.isEmpty {
                claudePillStatusText = err
                claudePillStatusTone = "error"
                claudeStatusRevision &+= 1
                triggerClaudeRightSlotFlashIfNeeded()
            }
            if let err = terminalCapture.lastError, !err.isEmpty {
                viewModel.notePillAbnormalFromExternalTerminalCapture()
            } else if terminalCapture.latestStatusTone == "error" || terminalCapture.latestStatusTone == "warn" {
                viewModel.notePillAbnormalFromExternalTerminalCapture()
            } else {
                viewModel.clearTerminalPillAbnormalRoutingIfNeeded(currentTone: terminalCapture.latestStatusTone)
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
            PanelManager.shared.syncIslandPanelLayout(
                notch: n,
                pillTotalWidth: w,
                extraHeight: 1 + claudeHintExpansionHeight
            )
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

    /// 已选项目且 CLI 可用时，让 Claude 面板子树始终留在层级里（切到其他标签或收起 pill 仅隐藏），避免卸载 `ClaudeTerminalView` 导致会话重启。
    private var claudeSessionHostShouldPersist: Bool {
        if case .installed = claudeCLI.installStatus, claudeCLI.projectDirectory != nil {
            return true
        }
        return false
    }

    private var claudePanelLayerInteractive: Bool {
        viewModel.expandedPanelMode == .claude && viewModel.state == .expanded
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

            ZStack(alignment: .topLeading) {
                if claudeSessionHostShouldPersist || viewModel.expandedPanelMode == .claude {
                    ClaudePanelFeatureView(
                        shouldPersistSessionHost: claudeSessionHostShouldPersist,
                        isLayerInteractive: claudePanelLayerInteractive,
                        panelContent: AnyView(claudePanelView)
                    )
                }

                Group {
                    switch viewModel.expandedPanelMode {
                    case .appStore:
                        AppPanelFeatureView(
                            searchText: $viewModel.searchText,
                            filteredApps: viewModel.filteredApps,
                            allApps: viewModel.allApps,
                            displayMode: settings.displayMode,
                            onAppTap: { app in viewModel.launchApp(app) },
                            onExitEditMode: { exitLaunchpadEditMode() },
                            folderManager: FolderManager.shared,
                            isLaunchpadEditing: $isLaunchpadEditing
                        )
                    case .claude:
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    case .tasks:
                        TaskPanelFeatureView(content: AnyView(claudeTaskBoardSection))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .onAppear {
            if viewModel.expandedPanelMode == .tasks {
                TerminalAutomationAccessProber.requestPromptsForSupportedTerminalHosts()
            }
        }
    }

    private func appStoreModeButton(mode: ExpandedPanelMode) -> some View {
        let selected = viewModel.expandedPanelMode == mode
        return Button {
            viewModel.expandedPanelMode = mode
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

    private func claudeModeButton(mode: ExpandedPanelMode) -> some View {
        let selected = viewModel.expandedPanelMode == mode
        return Button {
            viewModel.expandedPanelMode = mode
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

    private func taskModeButton(mode: ExpandedPanelMode) -> some View {
        let selected = viewModel.expandedPanelMode == mode
        return Button {
            viewModel.expandedPanelMode = mode
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
                            ForEach(group.tasks, id: \.session.id) { item in
                                let task = item.session
                                let snap = item.snapshot
                                let isMuted = terminalCapture.isSessionMuted(task.id)
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(alignment: .center, spacing: 8) {
                                        Circle()
                                            .fill(taskIndicatorColor(tone: snap.renderTone))
                                            .frame(width: 9, height: 9)
                                            .shadow(color: taskIndicatorColor(tone: snap.renderTone).opacity(0.55), radius: snap.isRunning ? 4 : 1, x: 0, y: 0)
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
                                                    set: { terminalCapture.setSessionMuted($0, sessionID: task.id) }
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

                                    Text(snap.secondaryText)
                                        .font(.system(size: taskFontBase, weight: .medium))
                                        .foregroundStyle(.white.opacity(isMuted ? 0.68 : (snap.isRunning ? (taskBreathPhase ? 0.9 : 0.72) : 0.82)))
                                        .lineLimit(2)
                                        .truncationMode(.tail)

                                    HStack(spacing: 6) {
                                        Text(snap.strategyDisplayName)
                                        Text("·")
                                        Text(task.terminalKind.rawValue)
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
                                        .fill(taskRowBackgroundColor(tone: snap.renderTone, isMuted: isMuted))
                                        .overlay {
                                            if snap.isRunning {
                                                taskRunningWaveOverlay(isMuted: isMuted)
                                            }
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(taskRowBorderColor(tone: snap.renderTone, isMuted: isMuted), lineWidth: 1)
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

            }
            .padding(.top, 2)
        }
    }

    private struct TaskBoardRow: Hashable {
        let session: CapturedTerminalSession
        let snapshot: TaskSessionSnapshot
    }

    private var taskGroups: [(name: String, tasks: [TaskBoardRow])] {
        let rows: [TaskBoardRow] = terminalCapture.sessions.compactMap { session in
            guard let snap = taskSessionEngine.snapshotsBySessionID[session.id] else { return nil }
            return TaskBoardRow(session: session, snapshot: snap)
        }
        let captured = Dictionary(grouping: terminalCapture.sessions) { session in
            let app = session.captureGroupKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if app.isEmpty {
                return "iTerm"
            }
            return app
        }
        let rowsByGroup = Dictionary(grouping: rows) { $0.session.captureGroupKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "iTerm" : $0.session.captureGroupKey.trimmingCharacters(in: .whitespacesAndNewlines) }
        let orderedNames = ["iTerm", "Terminal"]
        var result: [(name: String, tasks: [TaskBoardRow])] = []
        for name in orderedNames {
            let tasks = (rowsByGroup[name] ?? []).sorted { lhs, rhs in
                if lhs.snapshot.lifecycle == rhs.snapshot.lifecycle {
                    return lhs.session.title.localizedStandardCompare(rhs.session.title) == .orderedAscending
                }
                return taskLifecycleRank(lhs.snapshot.lifecycle) > taskLifecycleRank(rhs.snapshot.lifecycle)
            }
            result.append((name: name, tasks: tasks))
        }
        for (name, _) in captured where !orderedNames.contains(name) {
            let tasks = (rowsByGroup[name] ?? []).sorted { lhs, rhs in
                if lhs.snapshot.lifecycle == rhs.snapshot.lifecycle {
                    return lhs.session.title.localizedStandardCompare(rhs.session.title) == .orderedAscending
                }
                return taskLifecycleRank(lhs.snapshot.lifecycle) > taskLifecycleRank(rhs.snapshot.lifecycle)
            }
            result.append((name: name, tasks: tasks))
        }
        return result
    }

    @ViewBuilder
    private var iTerm2SessionStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("外部终端会话")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Circle()
                    .fill(terminalCapture.isTerminalHostReachable ? Color.green.opacity(0.9) : Color.white.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(terminalCapture.isTerminalHostReachable ? "运行中" : "未运行")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Text("\(terminalCapture.sessions.count) 个 Claude 会话")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            if !terminalCapture.sessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(terminalCapture.sessions.prefix(5)) { session in
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

    private func syncTerminalCaptureConfig() {
        let shouldEnableCapture = settings.claudeEnableITerm2Capture || viewModel.expandedPanelMode == .tasks
        let effectivePollInterval: Double = {
            if viewModel.state == .expanded {
                // 展开态提升刷新频率，让任务输出更接近实时滚动更新。
                return min(settings.claudeITerm2PollInterval, 0.6)
            }
            return settings.claudeITerm2PollInterval
        }()
        terminalCapture.updateConfig(
            enabled: shouldEnableCapture,
            pollInterval: effectivePollInterval
        )
        refreshTaskSnapshots()
    }

    private func clearPillAlertsAfterOpen() {
        if let text = claudePillStatusText, !text.isEmpty {
            suppressPillIssue(text: text, tone: claudePillStatusTone, seconds: 180)
        }
        viewModel.clearPillExpandRouting()
        viewModel.syncCollapsedPillTone("info")
        terminalCapture.acknowledgeAllCurrentIssues()
        claudePillStatusText = nil
        claudePillStatusTone = "info"
        claudeInteractionHint = nil
        claudeStatusRevision &+= 1
        claudeBottomHintCollapsed = false
        claudeBottomHintAutoCollapseWorkItem?.cancel()
        claudeBottomHintAutoCollapseWorkItem = nil
        stopClaudeRightSlotFlash()
    }

    private func refreshTaskSnapshots() {
        taskSessionEngine.refresh(
            sessions: terminalCapture.sessions,
            activeSessionIDs: terminalCapture.activeSessionIDs
        )
    }

    private func jumpToExternalTask(session: CapturedTerminalSession) {
        terminalCapture.acknowledgeCurrentIssue(for: session)
        terminalCapture.activate(session: session)
        viewModel.collapse()
    }

    private func taskLifecycleRank(_ state: TaskLifecycleState) -> Int {
        switch state {
        case .error: return 6
        case .waitingInput: return 5
        case .running: return 4
        case .success: return 3
        case .idle: return 2
        case .inactiveTool: return 1
        }
    }

    private func taskIndicatorColor(tone: TaskRenderTone) -> Color {
        switch tone {
        case .error:
            return Color.red.opacity(0.92)
        case .warning:
            return Color.orange.opacity(0.95)
        case .running:
            return Color.green.opacity(0.95)
        case .success:
            return Color.green.opacity(0.95)
        case .inactive:
            return Color.gray.opacity(0.85)
        case .neutral:
            return Color.green.opacity(0.95)
        }
    }

    private func taskRowBackgroundColor(
        tone: TaskRenderTone,
        isMuted: Bool
    ) -> Color {
        let base: Color = {
            switch tone {
            case .neutral:
                return Color.green.opacity(0.14)
            case .inactive:
                return Color.gray.opacity(0.14)
            case .running:
                return Color.green.opacity(0.16)
            case .success:
                return Color.green.opacity(0.14)
            case .warning:
                return Color.orange.opacity(0.14)
            case .error:
                return Color.red.opacity(0.16)
            }
        }()
        if isMuted { return base.opacity(0.35) }
        return base
    }

    private func taskRowBorderColor(
        tone: TaskRenderTone,
        isMuted: Bool
    ) -> Color {
        let base: Color = {
            switch tone {
            case .neutral:
                return Color.green.opacity(0.30)
            case .inactive:
                return Color.gray.opacity(0.28)
            case .running:
                return Color.green.opacity(0.34)
            case .success:
                return Color.green.opacity(0.30)
            case .warning:
                return Color.orange.opacity(0.34)
            case .error:
                return Color.red.opacity(0.34)
            }
        }()
        if isMuted { return base.opacity(0.45) }
        return base
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
