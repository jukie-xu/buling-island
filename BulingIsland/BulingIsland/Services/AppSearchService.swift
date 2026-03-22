import Foundation

final class AppSearchService {

    static func search(query: String, in apps: [AppInfo]) -> [AppInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return apps }

        let lowered = trimmed.lowercased()
        return apps.filter { app in
            // Match app name (Chinese/English)
            app.name.localizedCaseInsensitiveContains(lowered) ||
            // Match bundle identifier
            app.id.lowercased().contains(lowered) ||
            // Match pinyin full spelling (e.g. "xitong" matches "系统设置")
            app.pinyinFull.contains(lowered) ||
            // Match pinyin initials (e.g. "xtsz" matches "系统设置")
            app.pinyinInitials.contains(lowered)
        }
    }
}
