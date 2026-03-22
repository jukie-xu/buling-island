import AppKit
import CoreServices

final class AppDiscoveryService {

    static let shared = AppDiscoveryService()

    private init() {}

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

        var seen = Set<String>()
        var apps: [AppInfo] = []

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
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                let bundleID: String
                if let bundle = Bundle(url: itemURL) {
                    bundleID = bundle.bundleIdentifier ?? path
                } else {
                    bundleID = path
                }

                // MDItemCopyAttribute(kMDItemDisplayName) is the authoritative locale-aware API.
                // It always returns the name matching the system language, unlike Bundle APIs
                // which fail for CLI processes without localization declarations.
                let name = localizedDisplayName(for: itemURL)
                    ?? itemURL.deletingPathExtension().lastPathComponent

                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 64, height: 64)

                apps.append(AppInfo(
                    id: bundleID,
                    name: name,
                    path: itemURL,
                    icon: icon
                ))
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func launchApp(_ app: AppInfo) {
        NSWorkspace.shared.open(app.path)
    }
}
