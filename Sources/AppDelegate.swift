import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var islandViewModel = IslandViewModel()

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
        let contentView = IslandView(viewModel: islandViewModel)
        PanelManager.shared.createPanel(with: contentView) { [weak self] in
            self?.islandViewModel.toggle()
        }
        PanelManager.shared.syncInteractionState(viewModel: islandViewModel)
    }
}

@MainActor
final class IslandViewModel: ObservableObject {

    @Published var state: IslandState = .collapsed
    @Published var searchText: String = ""
    @Published var allApps: [AppInfo] = []
    @Published var isHovering: Bool = false
    @Published private(set) var isLoadingApps: Bool = false

    let settings = SettingsManager.shared
    private var appReloadWorkItem: DispatchWorkItem?
    private var folderWatchSources: [DispatchSourceFileSystemObject] = []
    private var folderWatchFDs: [Int32] = []

    var filteredApps: [AppInfo] {
        AppSearchService.search(query: searchText, in: allApps)
    }

    init() {
        startWatchingApplicationsFolders()
        loadApps()
        // 兜底：某些启动/重启后的早期时刻可能拿到空列表（Spotlight/目录尚未就绪），稍后再补拉一次。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            if self.allApps.isEmpty {
                self.loadApps()
            }
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
                // 防抖：避免偶发读取失败导致把已有列表清空（会造成面板“空白”）。
                if !apps.isEmpty || self.allApps.isEmpty {
                    self.allApps = apps
                }
            }
        }
    }

    func toggle() {
        if state == .collapsed {
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
