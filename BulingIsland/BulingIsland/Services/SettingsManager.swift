import Foundation
import SwiftUI

@MainActor
final class SettingsManager: ObservableObject {

    static let shared = SettingsManager()

    private let expandKey = "expandAnimation"
    private let collapseKey = "collapseAnimation"
    private let pillColorKey = "pillBorderColor"
    private let useCustomColorKey = "useCustomPillColor"
    private let displayModeKey = "displayMode"

    @Published var expandAnimation: ExpandAnimation {
        didSet { UserDefaults.standard.set(expandAnimation.rawValue, forKey: expandKey) }
    }

    @Published var collapseAnimation: CollapseAnimation {
        didSet { UserDefaults.standard.set(collapseAnimation.rawValue, forKey: collapseKey) }
    }

    /// Whether user has set a custom pill color (vs. auto follow system)
    @Published var useCustomPillColor: Bool {
        didSet { UserDefaults.standard.set(useCustomPillColor, forKey: useCustomColorKey) }
    }

    @Published var pillBorderColor: Color {
        didSet { savePillColor() }
    }

    @Published var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: displayModeKey) }
    }

    private init() {
        let expandRaw = UserDefaults.standard.string(forKey: expandKey) ?? ""
        self.expandAnimation = ExpandAnimation(rawValue: expandRaw) ?? .spring

        let collapseRaw = UserDefaults.standard.string(forKey: collapseKey) ?? ""
        self.collapseAnimation = CollapseAnimation(rawValue: collapseRaw) ?? .spring

        self.useCustomPillColor = UserDefaults.standard.bool(forKey: useCustomColorKey)
        self.pillBorderColor = Self.loadPillColor()

        let modeRaw = UserDefaults.standard.string(forKey: displayModeKey) ?? ""
        self.displayMode = DisplayMode(rawValue: modeRaw) ?? .grid
    }

    private func savePillColor() {
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: NSColor(pillBorderColor),
            requiringSecureCoding: false
        ) {
            UserDefaults.standard.set(data, forKey: pillColorKey)
        }
    }

    private static func loadPillColor() -> Color {
        guard let data = UserDefaults.standard.data(forKey: "pillBorderColor"),
              let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else {
            return .white
        }
        return Color(nsColor)
    }
}
