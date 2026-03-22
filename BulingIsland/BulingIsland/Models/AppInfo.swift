import AppKit

struct AppInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let path: URL
    let icon: NSImage

    // Cached for pinyin search
    let pinyinFull: String    // e.g. "xitongshezhi"
    let pinyinInitials: String // e.g. "xtsz"

    init(id: String, name: String, path: URL, icon: NSImage) {
        self.id = id
        self.name = name
        self.path = path
        self.icon = icon
        self.pinyinFull = Self.toPinyin(name).lowercased()
        self.pinyinInitials = Self.toPinyinInitials(name).lowercased()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Pinyin conversion

    private static func toPinyin(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        // Remove spaces for continuous matching
        return (mutable as String).replacingOccurrences(of: " ", with: "")
    }

    private static func toPinyinInitials(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        // Get first letter of each word
        let words = (mutable as String).components(separatedBy: " ")
        return words.compactMap { $0.first.map(String.init) }.joined()
    }
}
