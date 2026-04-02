import Foundation

enum FolderLayoutEngine {
    struct Update {
        var folders: [AppFolder]
        var layout: [LaunchpadItem]
        var changed: Bool
    }

    static func sanitizeLoadedState(
        folders inputFolders: [AppFolder],
        layout inputLayout: [LaunchpadItem]
    ) -> Update {
        var folders = inputFolders
        var layout = inputLayout
        var changed = false

        for i in folders.indices {
            var seen = Set<String>()
            let before = folders[i].appIDs.count
            folders[i].appIDs = folders[i].appIDs.filter { seen.insert($0).inserted }
            if folders[i].appIDs.count != before {
                changed = true
            }
        }

        let validFolderIDs = Set(folders.map(\.id))
        let beforeInvalidFolderCleanup = layout.count
        layout.removeAll { item in
            if case .folder(let uuid) = item, !validFolderIDs.contains(uuid) {
                return true
            }
            return false
        }
        if layout.count != beforeInvalidFolderCleanup {
            changed = true
        }

        let dedupe = dedupeTopLevelAppEntries(layout: layout)
        if dedupe.changed {
            layout = dedupe.layout
            changed = true
        }

        return Update(folders: folders, layout: layout, changed: changed)
    }

    static func syncInstalledApps(
        orderedInstalledAppIDs: [String],
        folders inputFolders: [AppFolder],
        layout inputLayout: [LaunchpadItem]
    ) -> Update {
        let currentAppIDs = Set(orderedInstalledAppIDs)
        var folders = inputFolders
        var layout = inputLayout
        var changed = false

        // Add newly installed apps to the end of layout.
        var knownAppIDs = Set<String>()
        for item in layout {
            switch item {
            case .app(let id):
                knownAppIDs.insert(id)
            case .folder(let uuid):
                if let folder = folders.first(where: { $0.id == uuid }) {
                    knownAppIDs.formUnion(folder.appIDs)
                }
            }
        }
        for appID in orderedInstalledAppIDs where !knownAppIDs.contains(appID) {
            layout.append(.app(appID))
            changed = true
        }

        // Remove uninstalled apps from top-level layout.
        let beforeLayoutCount = layout.count
        layout.removeAll { item in
            if case .app(let id) = item, !currentAppIDs.contains(id) { return true }
            return false
        }
        if layout.count != beforeLayoutCount {
            changed = true
        }

        // Remove uninstalled apps from folders; dissolve folders with <2 apps.
        for i in (0..<folders.count).reversed() {
            let before = folders[i].appIDs.count
            folders[i].appIDs.removeAll { !currentAppIDs.contains($0) }
            if folders[i].appIDs.count != before {
                changed = true
            }

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

        let dedupe = dedupeTopLevelAppEntries(layout: layout)
        if dedupe.changed {
            layout = dedupe.layout
            changed = true
        }

        return Update(folders: folders, layout: layout, changed: changed)
    }

    private static func dedupeTopLevelAppEntries(layout: [LaunchpadItem]) -> (layout: [LaunchpadItem], changed: Bool) {
        var seen = Set<String>()
        let before = layout.count
        let deduped = layout.filter { item in
            if case .app(let id) = item {
                if seen.contains(id) { return false }
                seen.insert(id)
            }
            return true
        }
        return (layout: deduped, changed: deduped.count != before)
    }
}
