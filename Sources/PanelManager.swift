import AppKit
import SwiftUI

/// `NSHostingView` 默认会把 fitting / 内容尺寸参与窗口布局；展开态内含 `ScrollView`+`LazyVGrid` 时，
/// 与 `NSHostingView.updateAnimatedWindowSize(_:)`、`windowDidLayout` 叠在一起会在部分系统上形成展示周期死循环
///（崩溃栈里 `__reusableDependencyContextForKey` / `NSScrollView setNeedsLayout` 递归）。
private final class IslandPanelHostingView<Content: View>: NSHostingView<Content> {

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    /// 切断「理想 fitting 尺寸 → `updateAnimatedWindowSize` → 改窗口/scroll 帧」回路：始终声明与当前 bounds 一致。
    override var fittingSize: NSSize {
        let s = bounds.size
        if s.width > 4, s.height > 4 { return s }
        return super.fittingSize
    }
}

/// NSPanel that can become key window (needed for text field input).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PanelManager {

    static let shared = PanelManager()

    private(set) var panel: NSPanel?
    private var clickMonitor: Any?
    private var pillClickMonitor: Any?
    private var pillRect: NSRect = .zero
    private var onPillClick: (() -> Void)?
    private var visibilityObserverTokens: [NSObjectProtocol] = []
    private var pendingBringFrontTasks: [DispatchWorkItem] = []
    private var clickOutsideMonitorGeneration: UInt64 = 0
    private var isCollapsedPillHiddenForFullscreen: Bool = false

    private init() {
        installIslandVisibilityObservers()
    }

    /// 三指左右切桌面时，合成器往往在动画全程里多次重排窗口层级；单次 `orderFront` 很容易落在「中间一帧」下面。
    /// 用短序列多次补拉 + `activeSpace` / 遮挡通知，尽量盖住整段过渡。
    private func scheduleBringIslandToFrontBurst() {
        pendingBringFrontTasks.forEach { $0.cancel() }
        pendingBringFrontTasks.removeAll()

        let delays: [TimeInterval] = [0, 0.04, 0.09, 0.16, 0.28, 0.45, 0.68, 0.95, 1.25, 1.55]
        for d in delays {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.bringIslandPanelsToFrontNow()
                }
            }
            pendingBringFrontTasks.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: work)
        }
    }

    private func applyIslandPanelSpaceChrome(_ panel: NSWindow) {
        // 略高于 `.screenSaver`，减轻被桌面切换过渡期里的临时遮罩压住。
        panel.level = NSWindow.Level(NSWindow.Level.screenSaver.rawValue + 24)
        var behaviors: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if #available(macOS 15.0, *) {
            behaviors.insert(.stationary)
        } else {
            // Ventura / Sonoma 等版本在运行时支持该位，旧 SDK 未导出 `.stationary` 时仍可编译。
            behaviors.insert(NSWindow.CollectionBehavior(rawValue: 16))
        }
        panel.collectionBehavior = behaviors
    }

    private func bringIslandPanelsToFrontNow() {
        guard SettingsManager.shared.islandEnabled, let panel else { return }
        guard !(panel.ignoresMouseEvents && isCollapsedPillHiddenForFullscreen) else { return }
        applyIslandPanelSpaceChrome(panel)
        panel.orderFrontRegardless()
    }

    /// 仅用于「收缩态 pill」在全屏等场景下临时隐藏：不影响展开态。
    /// 隐藏时会把 panel `orderOut` 并停掉全局 pill 点击监听；恢复时重新 `orderFrontRegardless` 并按当前 notch 同步热区。
    @MainActor
    func setCollapsedPillHiddenForFullscreen(_ hidden: Bool) {
        guard isCollapsedPillHiddenForFullscreen != hidden else { return }
        isCollapsedPillHiddenForFullscreen = hidden

        guard let panel else { return }
        if hidden {
            stopPillClickMonitor()
            if panel.ignoresMouseEvents { // only collapse state
                panel.orderOut(nil)
            }
        } else {
            if SettingsManager.shared.islandEnabled {
                panel.orderFrontRegardless()
                let notch = NotchDetector.layoutNotch()
                updatePanelFrame(notch: notch)
            }
            restartPillMonitoringIfCollapsedState()
        }
    }

    private func installIslandVisibilityObservers() {
        func observe(_ center: NotificationCenter, _ name: Notification.Name) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleBringIslandToFrontBurst()
                }
            }
            visibilityObserverTokens.append(token)
        }

        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification)
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        observe(NotificationCenter.default, NSApplication.didUnhideNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)

        let spaceToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.spaces.displayLayoutChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleBringIslandToFrontBurst()
            }
        }
        visibilityObserverTokens.append(spaceToken)
    }

    func createPanel<Content: View>(with contentView: Content, onPillClick: @escaping () -> Void) {
        let notch = NotchDetector.layoutNotch()

        let panelWidth: CGFloat = max(notch.notchWidth + Self.panelExtraWidth, Self.panelMinWidth) + 2 * Self.topCornerOverhang
        let panelHeight: CGFloat = Self.panelHeight
        let x = notch.rect.midX - panelWidth / 2
        let y = notch.screenFrame.maxY - panelHeight

        let panel = KeyablePanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        applyIslandPanelSpaceChrome(panel)
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        // Start collapsed: ignore mouse events on the panel itself
        panel.ignoresMouseEvents = true

        let hostingView = IslandPanelHostingView(rootView: contentView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
        self.onPillClick = onPillClick

        let occlusionToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleBringIslandToFrontBurst()
            }
        }
        visibilityObserverTokens.append(occlusionToken)

        let pillW = PillLayout.totalWidth(
            notch: notch,
            left: SettingsManager.shared.pillLeftSlot,
            right: SettingsManager.shared.pillRightSlot
        ) + 2 * PillLayout.visualWidthOverhang
        let pillH = notch.notchHeight + PillLayout.visualHeightOverhang
        let pillX = notch.rect.midX - pillW / 2
        let pillY = notch.screenFrame.maxY - pillH + PillLayout.visualHeightOverhang / 2
        self.pillRect = NSRect(x: pillX, y: pillY, width: pillW, height: pillH)

        restartPillMonitoringIfCollapsedState()
    }

    // MARK: - Panel frame + pill hit rect（与主屏刘海对齐，避免切换界面后窗口不跟走）

    private static let panelHeight: CGFloat = 535
    private static let panelExtraWidth: CGFloat = 40
    private static let panelMinWidth: CGFloat = 800
    /// Extra horizontal room for expanded panel's top flare corners.
    private static let topCornerOverhang: CGFloat = 16

    private func updatePanelFrame(notch: NotchInfo) {
        guard let panel else { return }
        let panelWidth = max(notch.notchWidth + Self.panelExtraWidth, Self.panelMinWidth) + 2 * Self.topCornerOverhang
        let x = notch.rect.midX - panelWidth / 2
        let y = notch.screenFrame.maxY - Self.panelHeight
        let newFrame = NSRect(x: x, y: y, width: panelWidth, height: Self.panelHeight)
        if !Self.nsRectApproximatelyEqual(panel.frame, newFrame) {
            panel.setFrame(newFrame, display: true)
        }
    }

    private static func nsRectApproximatelyEqual(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.origin.x - b.origin.x) < 0.5
            && abs(a.origin.y - b.origin.y) < 0.5
            && abs(a.size.width - b.size.width) < 0.5
            && abs(a.size.height - b.size.height) < 0.5
    }

    /// 仅按当前刘海把 NSPanel 挪回主屏顶边中（展开 / 收缩都需调用，否则台前调度后主窗口坐标会漂移）。
    @MainActor
    func repositionPanelWithNotchLayout(_ notch: NotchInfo) {
        updatePanelFrame(notch: notch)
    }

    /// 收缩态：窗口位置 + pill 全局点击热区与 `IslandView` 一致。
    @MainActor
    func syncIslandPanelLayout(notch: NotchInfo, pillTotalWidth: CGFloat) {
        updatePanelFrame(notch: notch)
        setCollapsedPillRect(notch: notch, width: pillTotalWidth)
    }

    /// 从台前调度等场景恢复后重挂全局点击监听（系统偶发使 monitor 失效）。
    func refreshCollapsedPillClickMonitoring() {
        guard panel != nil else { return }
        let s = SettingsManager.shared
        guard s.islandEnabled, s.clickToExpand else { return }
        guard panel?.ignoresMouseEvents == true else { return }
        restartPillMonitoringIfCollapsedState()
    }

    // MARK: - State transitions

    /// 与设置中的「开启灵动岛」「点击展开」等选项对齐。
    func syncInteractionState(viewModel: IslandViewModel) {
        let s = SettingsManager.shared
        guard panel != nil else { return }

        if !s.islandEnabled {
            stopPillClickMonitor()
            stopClickOutsideMonitor()
            if viewModel.state == .expanded {
                viewModel.forceCollapseForPanelSync()
            }
            panel?.orderOut(nil)
            return
        }

        // Fullscreen auto-hide takes precedence only for collapsed state.
        if viewModel.state == .collapsed, isCollapsedPillHiddenForFullscreen {
            stopPillClickMonitor()
            stopClickOutsideMonitor()
            panel?.orderOut(nil)
            return
        }

        panel?.orderFrontRegardless()

        let notch = NotchDetector.layoutNotch()
        updatePanelFrame(notch: notch)

        if viewModel.state == .expanded {
            setExpanded()
        } else {
            setCollapsed()
            let w = PillLayout.totalWidth(
                notch: notch,
                left: s.pillLeftSlot,
                right: s.pillRightSlot
            )
            setCollapsedPillRect(notch: notch, width: w)
        }
    }

    func setExpanded() {
        // Expand should always show panel.
        isCollapsedPillHiddenForFullscreen = false
        panel?.ignoresMouseEvents = false
        panel?.hasShadow = true
        panel?.makeKeyAndOrderFront(nil)
        stopPillClickMonitor()

        clickOutsideMonitorGeneration &+= 1
        let generation = clickOutsideMonitorGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.clickOutsideMonitorGeneration == generation else { return }
            guard let panel = self.panel, panel.isVisible, !panel.ignoresMouseEvents else { return }
            self.startClickOutsideMonitor { [weak self] in
                self?.onPillClick?()
            }
        }
    }

    func setCollapsed() {
        clickOutsideMonitorGeneration &+= 1
        stopClickOutsideMonitor()
        panel?.resignKey()
        panel?.ignoresMouseEvents = true
        panel?.hasShadow = false
        if isCollapsedPillHiddenForFullscreen {
            stopPillClickMonitor()
            panel?.orderOut(nil)
        } else {
            panel?.orderFrontRegardless()
            restartPillMonitoringIfCollapsedState()
        }
    }

    private func restartPillMonitoringIfCollapsedState() {
        stopPillClickMonitor()
        let s = SettingsManager.shared
        guard s.islandEnabled, s.clickToExpand else { return }
        startPillClickMonitor()
    }

    // MARK: - Pill click monitoring (collapsed state)

    private func startPillClickMonitor() {
        stopPillClickMonitor()
        // 未在系统设置中授权「辅助功能」时返回 nil，点击展开将不可用；回到前台时会通过 refreshCollapsedPillClickMonitoring 重试。
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard SettingsManager.shared.islandEnabled, SettingsManager.shared.clickToExpand else { return }
                let screenPoint = NSEvent.mouseLocation
                if self.pillRect.contains(screenPoint) {
                    self.onPillClick?()
                }
            }
        }
        pillClickMonitor = monitor
    }

    private func stopPillClickMonitor() {
        if let monitor = pillClickMonitor {
            NSEvent.removeMonitor(monitor)
            pillClickMonitor = nil
        }
    }

    /// 收缩态热区宽度随左右信息槽变化时更新。
    @MainActor
    func setCollapsedPillRect(notch: NotchInfo, width: CGFloat) {
        let pillH = notch.notchHeight + PillLayout.visualHeightOverhang
        let w = width + 2 * PillLayout.visualWidthOverhang
        let pillX = notch.rect.midX - w / 2
        let pillY = notch.screenFrame.maxY - pillH + PillLayout.visualHeightOverhang / 2
        pillRect = NSRect(x: pillX, y: pillY, width: w, height: pillH)
    }

    // MARK: - Click outside monitoring (expanded state)

    private var outsideMonitor: Any?
    private var outsideLocalMonitor: Any?

    func startClickOutsideMonitor(onClickOutside: @escaping () -> Void) {
        stopClickOutsideMonitor()
        // Global monitor: clicks in other apps
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let panel = self?.panel else { return }
            let screenPoint = NSEvent.mouseLocation
            if !panel.frame.contains(screenPoint) {
                DispatchQueue.main.async(execute: onClickOutside)
            }
        }
        // Local monitor: clicks in other windows of this app (e.g. settings)
        outsideLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let panel = self?.panel else { return event }
            if event.window != panel {
                onClickOutside()
            }
            return event
        }
    }

    func stopClickOutsideMonitor() {
        if let monitor = outsideMonitor {
            NSEvent.removeMonitor(monitor)
            outsideMonitor = nil
        }
        if let monitor = outsideLocalMonitor {
            NSEvent.removeMonitor(monitor)
            outsideLocalMonitor = nil
        }
    }
}
