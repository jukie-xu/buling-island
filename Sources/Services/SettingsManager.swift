import Foundation
import SwiftUI

extension Notification.Name {
    /// 灵动岛显示/点击展开等偏好变更，需同步面板与全局监听。
    static let panelInteractionPrefsDidChange = Notification.Name("buling.panelInteractionPrefsDidChange")
}

@MainActor
final class SettingsManager: ObservableObject {

    static let shared = SettingsManager()

    private let expandKey = "expandAnimation"
    private let collapseKey = "collapseAnimation"
    private let pillColorKey = "pillBorderColor"
    private let useCustomColorKey = "useCustomPillColor"
    private let displayModeKey = "displayMode"
    private let islandEnabledKey = "islandEnabled"
    private let clickToExpandKey = "clickToExpand"
    private let pillLeftSlotKey = "pillLeftSlot"
    private let pillRightSlotKey = "pillRightSlot"

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

    /// 关闭后隐藏刘海面板（等同于「关闭灵动岛」）。
    @Published var islandEnabled: Bool {
        didSet {
            UserDefaults.standard.set(islandEnabled, forKey: islandEnabledKey)
            NotificationCenter.default.post(name: .panelInteractionPrefsDidChange, object: nil)
        }
    }

    /// 是否在收缩态下允许点击刘海区域展开。
    @Published var clickToExpand: Bool {
        didSet {
            UserDefaults.standard.set(clickToExpand, forKey: clickToExpandKey)
            NotificationCenter.default.post(name: .panelInteractionPrefsDidChange, object: nil)
        }
    }

    /// 收缩态 pill 左侧扩展区展示内容。
    @Published var pillLeftSlot: PillSideWidget {
        didSet { UserDefaults.standard.set(pillLeftSlot.rawValue, forKey: pillLeftSlotKey) }
    }

    /// 收缩态 pill 右侧扩展区展示内容。
    @Published var pillRightSlot: PillSideWidget {
        didSet { UserDefaults.standard.set(pillRightSlot.rawValue, forKey: pillRightSlotKey) }
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

        self.islandEnabled = UserDefaults.standard.object(forKey: islandEnabledKey) as? Bool ?? true
        self.clickToExpand = UserDefaults.standard.object(forKey: clickToExpandKey) as? Bool ?? true

        let leftRaw = UserDefaults.standard.string(forKey: pillLeftSlotKey) ?? ""
        self.pillLeftSlot = PillSideWidget(rawValue: leftRaw) ?? .none
        let rightRaw = UserDefaults.standard.string(forKey: pillRightSlotKey) ?? ""
        self.pillRightSlot = PillSideWidget(rawValue: rightRaw) ?? .none
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
