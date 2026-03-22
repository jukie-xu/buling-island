import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var islandViewModel = IslandViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = IslandView(viewModel: islandViewModel)
        PanelManager.shared.createPanel(with: contentView) { [weak self] in
            self?.islandViewModel.toggle()
        }
    }
}

@MainActor
final class IslandViewModel: ObservableObject {

    @Published var state: IslandState = .collapsed
    @Published var searchText: String = ""
    @Published var allApps: [AppInfo] = []
    @Published var isHovering: Bool = false

    let settings = SettingsManager.shared

    var filteredApps: [AppInfo] {
        AppSearchService.search(query: searchText, in: allApps)
    }

    init() {
        loadApps()
    }

    func loadApps() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let apps = AppDiscoveryService.shared.discoverApps()
            DispatchQueue.main.async {
                self?.allApps = apps
            }
        }
    }

    func toggle() {
        if state == .collapsed {
            PanelManager.shared.setExpanded()
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

    func launchApp(_ app: AppInfo) {
        AppDiscoveryService.shared.launchApp(app)
        collapse()
    }

    func openSettings() {
        collapse()
        SettingsWindowManager.shared.open()
    }
}
