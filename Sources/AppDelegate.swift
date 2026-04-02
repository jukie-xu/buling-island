import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var islandViewModel = IslandViewModel()
    private var fullscreenAutoHider: FullscreenCollapsedPillAutoHider?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .panelInteractionPrefsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                PanelManager.shared.syncInteractionState(viewModel: self.islandViewModel)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TaskStrategyBootstrap.installProjectStrategies()

        let contentView = IslandView(viewModel: islandViewModel)
        PanelManager.shared.createPanel(with: contentView) { [weak self] in
            self?.islandViewModel.toggle()
        }
        PanelManager.shared.syncInteractionState(viewModel: islandViewModel)
        fullscreenAutoHider = FullscreenCollapsedPillAutoHider(viewModel: islandViewModel)
    }
}

@MainActor
final class IslandViewModel: ObservableObject {

    @Published var state: IslandState = .collapsed
    @Published var searchText: String = ""
    @Published var allApps: [AppInfo] = []
    @Published var isHovering: Bool = false
    @Published private(set) var isLoadingApps: Bool = false
    /// 当前展开面板顶栏选中的模式（应用 / Claude / 任务）。
    @Published var expandedPanelMode: ExpandedPanelMode
    /// 收缩态药丸底部提示为 error/warn 时，点击药丸应优先打开的面板（外部终端异常 → 任务；内嵌 Claude 异常 → Claude）。
    var pillAbnormalExpandTarget: ExpandedPanelMode?
    /// 与药丸 `claudePillStatusTone` 同步，供 `toggle()` 判断是否走异常路由。
    private(set) var collapsedPillTone: String = "info"

    let settings = SettingsManager.shared
    private var appReloadWorkItem: DispatchWorkItem?
    private var folderWatchSources: [DispatchSourceFileSystemObject] = []
    private var folderWatchFDs: [Int32] = []

    var filteredApps: [AppInfo] {
        AppSearchService.search(query: searchText, in: allApps)
    }

    init() {
        expandedPanelMode = SettingsManager.shared.defaultExpandedPanel
        startWatchingApplicationsFolders()
        loadApps()
    }

    func syncCollapsedPillTone(_ tone: String) {
        collapsedPillTone = tone
    }

    func notePillAbnormalFromExternalTerminalCapture() {
        pillAbnormalExpandTarget = .tasks
    }

    func notePillAbnormalFromClaudePanel() {
        pillAbnormalExpandTarget = .claude
    }

    /// 外部终端捕获不再显示 error/warn 时，去掉「点药丸进任务面板」的路由。
    func clearTerminalPillAbnormalRoutingIfNeeded(currentTone: String) {
        if pillAbnormalExpandTarget == .tasks, currentTone != "error", currentTone != "warn" {
            pillAbnormalExpandTarget = nil
        }
    }

    func clearPillExpandRouting() {
        pillAbnormalExpandTarget = nil
    }

    /// 任务面板中点击异常外部会话：展开（若已收缩）并切到任务面板。
    func expandToTaskPanel() {
        expandedPanelMode = .tasks
        if state == .collapsed {
            PanelManager.shared.setExpanded()
            if allApps.isEmpty && !isLoadingApps {
                scheduleAppsReload()
            }
            withAnimation(settings.expandAnimation.animation) {
                state = .expanded
                searchText = ""
            }
        } else {
            PanelManager.shared.setExpanded()
        }
    }

    func loadApps() {
        scheduleAppsReload()
    }

    private func scheduleAppsReload() {
        appReloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadAppsNow()
        }
        appReloadWorkItem = work
        // Debounce: app 安装/更新时目录会抖动多次，合并为一次扫描。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func reloadAppsNow() {
        isLoadingApps = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let apps = AppDiscoveryService.shared.discoverApps()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingApps = false
                // 启动早期会偶发目录索引未就绪：优先保留更完整的列表，避免“首次打开缺失/空白”。
                if self.allApps.isEmpty || apps.count >= self.allApps.count {
                    self.allApps = apps
                }
            }
        }
    }

    func toggle() {
        if state == .collapsed {
            // 仅药丸「异常」路由覆盖目标面板；其余情况保留上次停留的面板（如 Claude），
            // 避免展开时被默认面板替换导致 SwiftUI 卸载 Claude 终端、进程与缓冲丢失。
            if collapsedPillTone == "error" || collapsedPillTone == "warn",
               let route = pillAbnormalExpandTarget {
                expandedPanelMode = route
            }
            PanelManager.shared.setExpanded()
            // 展开时兜底刷新一次，避免冷启动/重启后首次展开看到空内容。
            if allApps.isEmpty && !isLoadingApps {
                scheduleAppsReload()
            }
            // 展开/收起曲线由设置项决定；窗口与 Grid 布局已由 `IslandPanelHostingView` + 非 Lazy 网格稳住，避免再走 `updateAnimatedWindowSize` 死循环。
            withAnimation(settings.expandAnimation.animation) {
                state = .expanded
                searchText = ""
            }
        } else {
            collapse()
        }
    }

    func collapse() {
        withAnimation(settings.collapseAnimation.animation) {
            state = .collapsed
            searchText = ""
        }
        PanelManager.shared.setCollapsed()
    }

    /// 设置关闭灵动岛等需要立即同步面板状态时使用（无展开动画）。
    func forceCollapseForPanelSync() {
        state = .collapsed
        searchText = ""
        PanelManager.shared.setCollapsed()
    }

    func launchApp(_ app: AppInfo) {
        AppDiscoveryService.shared.launchApp(app)
        collapse()
    }

    func openSettings() {
        collapse()
        SettingsWindowManager.shared.open()
    }

    // MARK: - Watch app folders

    private func startWatchingApplicationsFolders() {
        // 监听目录变动（安装/卸载/更新 app 时会触发），让面板无需重启即可刷新。
        let paths: [String] = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]

        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .attrib, .extend],
                queue: .main
            )

            src.setEventHandler { [weak self] in
                self?.scheduleAppsReload()
            }

            src.setCancelHandler { [fd] in
                close(fd)
            }

            src.resume()
            folderWatchSources.append(src)
            folderWatchFDs.append(fd)
        }
    }
}
