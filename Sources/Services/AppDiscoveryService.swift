import AppKit
import CoreServices

final class AppDiscoveryService {

    static let shared = AppDiscoveryService()

    private init() {}

    private struct AppCandidate {
        let bundleID: String?
        let path: String
        let url: URL
        let name: String
        let icon: NSImage
    }

    /// Use Spotlight metadata to get the locale-correct display name (same source as Finder).
    private func localizedDisplayName(for url: URL) -> String? {
        guard let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(mdItem, kMDItemDisplayName) as? String
    }

    func discoverApps() -> [AppInfo] {
        let searchPaths: [String] = [
            "/Applications",
            "/System/Applications",
            "/Applications/Utilities",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]

        var seenPaths = Set<String>()
        var candidates: [AppCandidate] = []

        for searchPath in searchPaths {
            let url = URL(fileURLWithPath: searchPath)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for itemURL in contents {
                guard itemURL.pathExtension == "app" else { continue }

                let path = itemURL.path
                guard !seenPaths.contains(path) else { continue }
                seenPaths.insert(path)

                let bundleID = Bundle(url: itemURL)?.bundleIdentifier

                // MDItemCopyAttribute(kMDItemDisplayName) is the authoritative locale-aware API.
                // It always returns the name matching the system language, unlike Bundle APIs
                // which fail for CLI processes without localization declarations.
                let name = localizedDisplayName(for: itemURL)
                    ?? itemURL.deletingPathExtension().lastPathComponent

                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 64, height: 64)

                candidates.append(
                    AppCandidate(
                        bundleID: bundleID,
                        path: path,
                        url: itemURL,
                        name: name,
                        icon: icon
                    )
                )
            }
        }

        // Generate stable IDs with backward compatibility:
        // - unique bundleID => keep raw bundleID (old behavior)
        // - duplicated bundleID => keep first as bundleID, others as bundleID|path
        // - no bundleID => use path
        let bundleCount = Dictionary(
            candidates.compactMap { c -> (String, Int)? in
                guard let bid = c.bundleID else { return nil }
                return (bid, 1)
            },
            uniquingKeysWith: +
        )
        var duplicatedBundleAssignedPrimary = Set<String>()
        let sortedCandidates = candidates.sorted { a, b in
            a.path.localizedStandardCompare(b.path) == .orderedAscending
        }

        var apps: [AppInfo] = []
        apps.reserveCapacity(sortedCandidates.count)
        for c in sortedCandidates {
            let id: String
            if let bid = c.bundleID {
                if (bundleCount[bid] ?? 0) <= 1 {
                    id = bid
                } else if !duplicatedBundleAssignedPrimary.contains(bid) {
                    id = bid
                    duplicatedBundleAssignedPrimary.insert(bid)
                } else {
                    id = "\(bid)|\(c.path)"
                }
            } else {
                id = c.path
            }

            apps.append(
                AppInfo(
                    id: id,
                    name: c.name,
                    path: c.url,
                    icon: c.icon
                )
            )
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func launchApp(_ app: AppInfo) {
        // `NSWorkspace.open` 在某些系统状态下（首次启动/校验/冷盘）可能带来主线程卡顿；
        // 将其移到后台队列，避免影响本 App 的交互与动画。
        DispatchQueue.global(qos: .userInitiated).async {
            NSWorkspace.shared.open(app.path)
        }
    }
}
