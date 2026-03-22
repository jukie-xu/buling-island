import Foundation
import SwiftUI

@MainActor
final class FolderManager: ObservableObject {

    static let shared = FolderManager()

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
        let currentAppIDs = Set(apps.map { $0.id })

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

        var changed = false

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
    }

    // MARK: - Folder CRUD

    func createFolder(name: String, appIDs: [String]) -> AppFolder {
        let folder = AppFolder(name: name, appIDs: appIDs)
        folders.append(folder)
        saveFolders()
        return folder
    }

    func mergeApps(_ appID1: String, _ appID2: String) {
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

    /// Move item without persisting — used during live drag reorder
    func moveItemLive(from source: Int, to destination: Int) {
        let offset = source > destination ? destination : destination - 1
        guard source != offset else { return }
        let item = layout.remove(at: source)
        layout.insert(item, at: offset > layout.count ? layout.count : offset)
    }

    func commitLayout() {
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

    func folder(for id: UUID) -> AppFolder? {
        folders.first { $0.id == id }
    }
}
