import Foundation
import SwiftUI

@MainActor
final class FolderManager: ObservableObject {

    static let shared = FolderManager()

    enum SmartMergePreset: String, CaseIterable, Identifiable {
        case byFunction
        case byVendor
        case byInitial

        var id: String { rawValue }

        var title: String {
            switch self {
            case .byFunction: return "按用途"
            case .byVendor: return "按开发者"
            case .byInitial: return "按首字母"
            }
        }

        var detail: String {
            switch self {
            case .byFunction: return "浏览器/开发/社交/影音等分组"
            case .byVendor: return "按厂商归类（Apple/Google 等）"
            case .byInitial: return "按应用名称首字母分段"
            }
        }
    }

    @Published var folders: [AppFolder] = []
    @Published var layout: [LaunchpadItem] = []

    private let storageDir: URL
    private let foldersFile: URL
    private let layoutFile: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("BulingIsland", isDirectory: true)
        foldersFile = storageDir.appendingPathComponent("folders.json")
        layoutFile = storageDir.appendingPathComponent("layout.json")

        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: foldersFile),
           let decoded = try? JSONDecoder().decode([AppFolder].self, from: data) {
            folders = decoded
        }
        if let data = try? Data(contentsOf: layoutFile),
           let decoded = try? JSONDecoder().decode([LaunchpadItem].self, from: data) {
            layout = decoded
        }
        if normalizeFolderAppLists() {
            saveFolders()
        }
        if dedupeTopLevelAppEntries() {
            saveLayout()
        }
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            try? data.write(to: foldersFile)
        }
    }

    private func saveLayout() {
        if let data = try? JSONEncoder().encode(layout) {
            try? data.write(to: layoutFile)
        }
    }

    // MARK: - Build layout from apps

    func buildLayoutIfNeeded(from apps: [AppInfo]) {
        // Root-cause fix:
        // Startup early-phase may transiently return an empty app list.
        // Treating that as "all apps uninstalled" would wipe Launchpad layout.
        guard !apps.isEmpty else { return }

        let currentAppIDs = Set(apps.map { $0.id })
        var changed = false

        // Self-heal: remove stale folder slots whose folder payload is missing/corrupted.
        let beforeInvalidFolderCleanup = layout.count
        layout.removeAll { item in
            if case .folder(let uuid) = item, folder(for: uuid) == nil {
                return true
            }
            return false
        }
        if layout.count != beforeInvalidFolderCleanup {
            changed = true
        }

        if layout.isEmpty {
            layout = apps.map { .app($0.id) }
            saveLayout()
            return
        }

        // Collect all app IDs already present in layout or folders
        var knownAppIDs = Set<String>()
        for item in layout {
            switch item {
            case .app(let id): knownAppIDs.insert(id)
            case .folder(let uuid):
                if let folder = folder(for: uuid) {
                    knownAppIDs.formUnion(folder.appIDs)
                }
            }
        }

        // Add newly installed apps to the end of layout
        for app in apps where !knownAppIDs.contains(app.id) {
            layout.append(.app(app.id))
            changed = true
        }

        // Remove uninstalled apps from layout
        let beforeCount = layout.count
        layout.removeAll { item in
            if case .app(let id) = item, !currentAppIDs.contains(id) { return true }
            return false
        }
        if layout.count != beforeCount { changed = true }

        // Remove uninstalled apps from folders, dissolve folders with < 2 apps
        for i in (0..<folders.count).reversed() {
            let before = folders[i].appIDs.count
            folders[i].appIDs.removeAll { !currentAppIDs.contains($0) }
            if folders[i].appIDs.count != before { changed = true }

            if folders[i].appIDs.count < 2 {
                let remaining = folders[i].appIDs
                let folderID = folders[i].id
                if let layoutIdx = layout.firstIndex(of: .folder(folderID)) {
                    layout.remove(at: layoutIdx)
                    for (offset, id) in remaining.enumerated() {
                        layout.insert(.app(id), at: layoutIdx + offset)
                    }
                }
                folders.remove(at: i)
                changed = true
            }
        }

        if changed {
            saveFolders()
            saveLayout()
        }

        if dedupeTopLevelAppEntries() {
            saveLayout()
        }
    }

    /// 同一 bundle 在顶层只能占一格；历史数据或旧版拖拽 bug 可能产生重复 `.app(id)`。
    @discardableResult
    private func dedupeTopLevelAppEntries() -> Bool {
        var seen = Set<String>()
        let before = layout.count
        layout.removeAll { item in
            if case .app(let id) = item {
                if seen.contains(id) { return true }
                seen.insert(id)
            }
            return false
        }
        return layout.count != before
    }

    @discardableResult
    private func normalizeFolderAppLists() -> Bool {
        var changed = false
        for i in folders.indices {
            var seen = Set<String>()
            let before = folders[i].appIDs.count
            folders[i].appIDs = folders[i].appIDs.filter { seen.insert($0).inserted }
            if folders[i].appIDs.count != before { changed = true }
        }
        return changed
    }

    // MARK: - Folder CRUD

    func createFolder(name: String, appIDs: [String]) -> AppFolder {
        let folder = AppFolder(name: name, appIDs: appIDs)
        folders.append(folder)
        saveFolders()
        return folder
    }

    func mergeApps(_ appID1: String, _ appID2: String) {
        guard appID1 != appID2 else { return }
        let folder = createFolder(name: "新建文件夹", appIDs: [appID1, appID2])

        // Replace both apps in layout with the folder, remove the second
        if let idx1 = layout.firstIndex(of: .app(appID1)) {
            layout[idx1] = .folder(folder.id)
        }
        layout.removeAll { $0 == .app(appID2) }
        saveLayout()
    }

    func addAppToFolder(_ appID: String, folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        if !folders[idx].appIDs.contains(appID) {
            folders[idx].appIDs.append(appID)
            saveFolders()
        }
        layout.removeAll { $0 == .app(appID) }
        saveLayout()
    }

    func removeAppFromFolder(_ appID: String, folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].appIDs.removeAll { $0 == appID }

        // Insert app back into layout after the folder
        if let folderLayoutIdx = layout.firstIndex(of: .folder(folderID)) {
            layout.insert(.app(appID), at: folderLayoutIdx + 1)
        } else {
            layout.append(.app(appID))
        }

        // If folder has < 2 apps, dissolve it
        if folders[idx].appIDs.count < 2 {
            let remaining = folders[idx].appIDs
            if let folderLayoutIdx = layout.firstIndex(of: .folder(folderID)) {
                layout.remove(at: folderLayoutIdx)
                for (offset, id) in remaining.enumerated() {
                    layout.insert(.app(id), at: folderLayoutIdx + offset)
                }
            }
            folders.remove(at: idx)
        }

        saveFolders()
        saveLayout()
    }

    func renameFolder(_ folderID: UUID, to name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].name = name
        saveFolders()
    }

    func deleteFolder(_ folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        let appIDs = folders[idx].appIDs

        if let layoutIdx = layout.firstIndex(of: .folder(folderID)) {
            layout.remove(at: layoutIdx)
            for (offset, id) in appIDs.enumerated() {
                layout.insert(.app(id), at: layoutIdx + offset)
            }
        }

        folders.remove(at: idx)
        saveFolders()
        saveLayout()
    }

    func moveItem(from source: IndexSet, to destination: Int) {
        layout.move(fromOffsets: source, toOffset: destination)
        saveLayout()
    }

    /// Move item without persisting — used during live drag reorder.
    /// - Returns: The layout index of the moved item after the operation.
    @discardableResult
    func moveItemLive(from source: Int, to destination: Int) -> Int {
        let offset = source > destination ? destination : destination - 1
        guard source != offset else { return source }
        let item = layout.remove(at: source)
        let insertAt = min(max(0, offset), layout.count)
        layout.insert(item, at: insertAt)
        return insertAt
    }

    func commitLayout() {
        saveLayout()
    }

    /// 从顶层布局移除指定下标（用于拖放取消重复格等）。
    func removeLayoutSlot(at index: Int) {
        guard layout.indices.contains(index) else { return }
        layout.remove(at: index)
        saveLayout()
    }

    func reorderAppsInFolder(_ folderID: UUID, from source: IndexSet, to destination: Int) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].appIDs.move(fromOffsets: source, toOffset: destination)
        saveFolders()
    }

    /// Live reorder inside folder without persisting
    func reorderAppsInFolderLive(_ folderID: UUID, from source: Int, to destination: Int) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        let offset = source > destination ? destination : destination - 1
        guard source != offset else { return }
        let id = folders[idx].appIDs.remove(at: source)
        folders[idx].appIDs.insert(id, at: offset > folders[idx].appIDs.count ? folders[idx].appIDs.count : offset)
    }

    func commitFolders() {
        saveFolders()
    }

    func resetLayout() {
        folders = []
        layout = []
        saveFolders()
        saveLayout()
    }

    func smartMergeApps(_ apps: [AppInfo], preset: SmartMergePreset) {
        let uniqueApps = dedupeAppsByID(apps)
        guard !uniqueApps.isEmpty else { return }

        // 系统自带应用先聚类（1～2 个文件夹），避免 Safari 等再被拆进「浏览器」或按首字母打散。
        let builtInClusters = builtInMacOSClusters(from: uniqueApps)
        let builtInIDs = Set(builtInClusters.flatMap(\.appIDs))
        let appsForPreset = uniqueApps.filter { !builtInIDs.contains($0.id) }

        let presetGrouped: [(name: String, appIDs: [String])]
        switch preset {
        case .byFunction:
            presetGrouped = groupByFunction(appsForPreset)
        case .byVendor:
            presetGrouped = groupByVendor(appsForPreset)
        case .byInitial:
            presetGrouped = groupByInitial(appsForPreset)
        }

        let grouped = builtInClusters + presetGrouped

        var newFolders: [AppFolder] = []
        var newLayout: [LaunchpadItem] = []
        var groupedIDs = Set<String>()

        for g in grouped {
            let ids = Array(Set(g.appIDs)).sorted()
            guard ids.count >= 2 else { continue }
            let folder = AppFolder(name: g.name, appIDs: ids)
            newFolders.append(folder)
            newLayout.append(.folder(folder.id))
            groupedIDs.formUnion(ids)
        }

        for app in uniqueApps where !groupedIDs.contains(app.id) {
            newLayout.append(.app(app.id))
        }

        folders = newFolders
        layout = newLayout
        saveFolders()
        saveLayout()
    }

    func folder(for id: UUID) -> AppFolder? {
        folders.first { $0.id == id }
    }

    // MARK: - Smart merge helpers

    private func dedupeAppsByID(_ apps: [AppInfo]) -> [AppInfo] {
        var seen = Set<String>()
        return apps.filter { seen.insert($0.id).inserted }
    }

    /// `com.apple.*` 与安装在 `/System/Applications` 下的应用视为 macOS 系统自带。
    private func isBuiltInMacOSApp(_ app: AppInfo) -> Bool {
        let id = app.id.lowercased()
        if id.hasPrefix("com.apple.") { return true }
        return app.path.path.lowercased().hasPrefix("/system/applications")
    }

    /// 至少 2 个自带应用才成文件夹。尽量拆成「系统实用工具」与「macOS 自带应用」；不足两类的余项并入较多的一类。
    private func builtInMacOSClusters(from apps: [AppInfo]) -> [(name: String, appIDs: [String])] {
        let builtIn = apps.filter { isBuiltInMacOSApp($0) }
        guard builtIn.count >= 2 else { return [] }

        var utilIDs: [String] = []
        var otherIDs: [String] = []
        for app in builtIn {
            if app.path.path.contains("/Applications/Utilities/") {
                utilIDs.append(app.id)
            } else {
                otherIDs.append(app.id)
            }
        }

        var folders: [(String, [String])] = []
        if utilIDs.count >= 2 {
            folders.append(("系统实用工具", utilIDs))
        }
        if otherIDs.count >= 2 {
            folders.append(("macOS 自带应用", otherIDs))
        }

        if folders.isEmpty {
            return [("macOS 自带应用", builtIn.map(\.id))]
        }

        let assigned = Set(folders.flatMap(\.1))
        let orphans = builtIn.map(\.id).filter { !assigned.contains($0) }
        guard !orphans.isEmpty else { return folders }

        guard let maxIdx = folders.indices.max(by: { folders[$0].1.count < folders[$1].1.count }) else {
            return folders
        }
        var merged = folders
        let name = merged[maxIdx].0
        merged[maxIdx] = (name, merged[maxIdx].1 + orphans)
        return merged
    }

    private func groupByFunction(_ apps: [AppInfo]) -> [(name: String, appIDs: [String])] {
        let buckets: [(name: String, keywords: [String])] = [
            ("浏览器", ["safari", "chrome", "edge", "firefox", "brave", "opera", "vivaldi", "browser"]),
            ("开发工具", ["xcode", "terminal", "iterm", "code", "android studio", "docker", "postman", "intellij", "pycharm", "goland", "webstorm"]),
            ("社交沟通", ["wechat", "weixin", "qq", "slack", "discord", "telegram", "teams", "zoom", "feishu", "lark"]),
            ("影音播放", ["music", "tv", "quicktime", "iina", "vlc", "spotify", "netflix", "bilibili", "video", "player"]),
            ("办公效率", ["word", "excel", "powerpoint", "notion", "obsidian", "calendar", "reminders", "mail", "pages", "numbers", "keynote"]),
            ("设计创作", ["photoshop", "illustrator", "figma", "sketch", "pixelmator", "premiere", "after effects", "davinci"]),
            ("系统工具", ["system settings", "activity monitor", "disk utility", "finder", "preview", "shortcuts", "automator"]),
        ]

        var grouped: [String: [String]] = [:]
        for app in apps {
            let text = "\(app.name.lowercased()) \(app.pinyinFull) \(app.id.lowercased())"
            if let hit = buckets.first(where: { b in
                b.keywords.contains { text.contains($0) }
            }) {
                grouped[hit.name, default: []].append(app.id)
            }
        }

        return buckets.compactMap { bucket in
            guard let ids = grouped[bucket.name], ids.count >= 2 else { return nil }
            return (bucket.name, ids)
        }
    }

    private func groupByVendor(_ apps: [AppInfo]) -> [(name: String, appIDs: [String])] {
        var grouped: [String: [String]] = [:]
        for app in apps {
            let key = vendorName(forBundleID: app.id)
            guard !key.isEmpty else { continue }
            grouped[key, default: []].append(app.id)
        }
        return grouped
            .filter { $0.value.count >= 2 }
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private func vendorName(forBundleID bundleID: String) -> String {
        let lower = bundleID.lowercased()
        let known: [(String, String)] = [
            ("com.apple.", "Apple"),
            ("com.microsoft.", "Microsoft"),
            ("com.google.", "Google"),
            ("org.mozilla.", "Mozilla"),
            ("com.tencent.", "腾讯"),
            ("com.bytedance.", "字节跳动"),
            ("com.adobe.", "Adobe"),
            ("com.jetbrains.", "JetBrains"),
        ]
        if let hit = known.first(where: { lower.hasPrefix($0.0) }) {
            return hit.1
        }
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 2 else { return "" }
        return String(parts[1]).capitalized
    }

    private func groupByInitial(_ apps: [AppInfo]) -> [(name: String, appIDs: [String])] {
        let ranges: [(name: String, letters: ClosedRange<Character>)] = [
            ("A-F", "A"..."F"),
            ("G-L", "G"..."L"),
            ("M-R", "M"..."R"),
            ("S-Z", "S"..."Z"),
        ]

        var grouped: [String: [String]] = ["#": []]
        for app in apps {
            let first = app.pinyinFull.uppercased().first ?? "#"
            if let range = ranges.first(where: { $0.letters.contains(first) }) {
                grouped[range.name, default: []].append(app.id)
            } else {
                grouped["#", default: []].append(app.id)
            }
        }

        var out: [(String, [String])] = []
        for r in ranges {
            if let ids = grouped[r.name], ids.count >= 2 { out.append((r.name, ids)) }
        }
        if let ids = grouped["#"], ids.count >= 2 { out.append(("#", ids)) }
        return out
    }
}
