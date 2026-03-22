import Foundation

struct AppFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var appIDs: [String]

    init(name: String, appIDs: [String]) {
        self.id = UUID()
        self.name = name
        self.appIDs = appIDs
    }
}

enum LaunchpadItem: Codable, Identifiable, Hashable {
    case app(String)
    case folder(UUID)

    var id: String {
        switch self {
        case .app(let bundleID): return "app:\(bundleID)"
        case .folder(let uuid): return "folder:\(uuid.uuidString)"
        }
    }

    var isApp: Bool {
        if case .app = self { return true }
        return false
    }

    // Codable
    enum CodingKeys: String, CodingKey {
        case type, value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let id):
            try container.encode("app", forKey: .type)
            try container.encode(id, forKey: .value)
        case .folder(let uuid):
            try container.encode("folder", forKey: .type)
            try container.encode(uuid.uuidString, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let value = try container.decode(String.self, forKey: .value)
        switch type {
        case "folder":
            guard let uuid = UUID(uuidString: value) else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "Invalid UUID")
            }
            self = .folder(uuid)
        default:
            self = .app(value)
        }
    }
}
