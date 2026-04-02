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
    private let autoHideCollapsedPillInFullscreenKey = "autoHideCollapsedPillInFullscreen"
    private let pillLeftSlotKey = "pillLeftSlot"
    private let pillRightSlotKey = "pillRightSlot"
    private let pillFlareRadiusKey = "pillFlareRadius"
    private let pillVisualWidthOverhangKey = "pillVisualWidthOverhang"
    private let pillVisualHeightOverhangKey = "pillVisualHeightOverhang"
    private let pillSideSlotWidthKey = "pillSideSlotWidth"
    private let claudeStretchHintEnabledKey = "claudeStretchHintEnabled"
    private let claudeHintAutoCollapseEnabledKey = "claudeHintAutoCollapseEnabled"
    private let claudeHintAutoCollapseDelayKey = "claudeHintAutoCollapseDelay"
    private let claudeEnableITerm2CaptureKey = "claudeEnableITerm2Capture"
    private let claudeITerm2PollIntervalKey = "claudeITerm2PollInterval"
    private let taskPanelFontSizeKey = "taskPanelFontSize"
    private let defaultExpandedPanelKey = "defaultExpandedPanel"

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

    /// 全屏场景下自动隐藏收缩态 pill（仅收缩态；展开面板不受影响）。
    @Published var autoHideCollapsedPillInFullscreen: Bool {
        didSet {
            UserDefaults.standard.set(autoHideCollapsedPillInFullscreen, forKey: autoHideCollapsedPillInFullscreenKey)
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

    // MARK: - Pill appearance tuning

    /// 收缩态 pill 顶角外撇弯角尺度（越小越“尖/紧”，越大越“圆润”）。
    @Published var pillFlareRadius: CGFloat {
        didSet { UserDefaults.standard.set(Double(pillFlareRadius), forKey: pillFlareRadiusKey) }
    }

    /// 收缩态 pill 两侧额外可视宽度（用于把 P0 推得更外侧，让外撇更圆润），单侧值。
    @Published var pillVisualWidthOverhang: CGFloat {
        didSet { UserDefaults.standard.set(Double(pillVisualWidthOverhang), forKey: pillVisualWidthOverhangKey) }
    }

    /// 收缩态 pill 额外可视高度（用于让 pill 略高于 notch，从而更“饱满”），为额外叠加值。
    @Published var pillVisualHeightOverhang: CGFloat {
        didSet { UserDefaults.standard.set(Double(pillVisualHeightOverhang), forKey: pillVisualHeightOverhangKey) }
    }

    /// 收缩态 pill 左/右信息槽固定宽度（电量/网速）。
    @Published var pillSideSlotWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(pillSideSlotWidth), forKey: pillSideSlotWidthKey) }
    }

    /// Claude 状态提醒是否触发 pill 底部下拉展示。
    @Published var claudeStretchHintEnabled: Bool {
        didSet { UserDefaults.standard.set(claudeStretchHintEnabled, forKey: claudeStretchHintEnabledKey) }
    }

    /// Claude 状态提醒展示后是否自动缩回。
    @Published var claudeHintAutoCollapseEnabled: Bool {
        didSet { UserDefaults.standard.set(claudeHintAutoCollapseEnabled, forKey: claudeHintAutoCollapseEnabledKey) }
    }

    /// Claude 提醒自动缩回延迟（秒）。
    @Published var claudeHintAutoCollapseDelay: Double {
        didSet { UserDefaults.standard.set(claudeHintAutoCollapseDelay, forKey: claudeHintAutoCollapseDelayKey) }
    }

    /// 是否启用 iTerm2 外部会话输出捕获（实验特性）。
    @Published var claudeEnableITerm2Capture: Bool {
        didSet { UserDefaults.standard.set(claudeEnableITerm2Capture, forKey: claudeEnableITerm2CaptureKey) }
    }

    /// iTerm2 捕获轮询间隔（秒）。
    @Published var claudeITerm2PollInterval: Double {
        didSet { UserDefaults.standard.set(claudeITerm2PollInterval, forKey: claudeITerm2PollIntervalKey) }
    }

    /// Task 面板内容字号基准。
    @Published var taskPanelFontSize: Double {
        didSet { UserDefaults.standard.set(taskPanelFontSize, forKey: taskPanelFontSizeKey) }
    }

    /// 从收缩态点击药丸展开时默认进入的面板（无「异常」路由时）。
    @Published var defaultExpandedPanel: ExpandedPanelMode {
        didSet { UserDefaults.standard.set(defaultExpandedPanel.rawValue, forKey: defaultExpandedPanelKey) }
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
        self.autoHideCollapsedPillInFullscreen = UserDefaults.standard.object(forKey: autoHideCollapsedPillInFullscreenKey) as? Bool ?? false

        let leftRaw = UserDefaults.standard.string(forKey: pillLeftSlotKey) ?? ""
        self.pillLeftSlot = PillSideWidget(rawValue: leftRaw) ?? .battery
        let rightRaw = UserDefaults.standard.string(forKey: pillRightSlotKey) ?? ""
        self.pillRightSlot = PillSideWidget(rawValue: rightRaw) ?? .networkSpeed

        let flareRadius = UserDefaults.standard.object(forKey: pillFlareRadiusKey) as? Double
        self.pillFlareRadius = CGFloat(flareRadius ?? 4)

        let overhang = UserDefaults.standard.object(forKey: pillVisualWidthOverhangKey) as? Double
        self.pillVisualWidthOverhang = CGFloat(overhang ?? 3)

        let heightOverhang = UserDefaults.standard.object(forKey: pillVisualHeightOverhangKey) as? Double
        self.pillVisualHeightOverhang = CGFloat(heightOverhang ?? 0)

        let slotW = UserDefaults.standard.object(forKey: pillSideSlotWidthKey) as? Double
        self.pillSideSlotWidth = CGFloat(slotW ?? 52)

        self.claudeStretchHintEnabled = UserDefaults.standard.object(forKey: claudeStretchHintEnabledKey) as? Bool ?? true
        self.claudeHintAutoCollapseEnabled = UserDefaults.standard.object(forKey: claudeHintAutoCollapseEnabledKey) as? Bool ?? true
        let collapseDelay = UserDefaults.standard.object(forKey: claudeHintAutoCollapseDelayKey) as? Double
        self.claudeHintAutoCollapseDelay = max(1, min(10, collapseDelay ?? 3))

        self.claudeEnableITerm2Capture = UserDefaults.standard.object(forKey: claudeEnableITerm2CaptureKey) as? Bool ?? false
        let pollInterval = UserDefaults.standard.object(forKey: claudeITerm2PollIntervalKey) as? Double
        self.claudeITerm2PollInterval = max(1, min(5, pollInterval ?? 1.5))
        let taskFontSize = UserDefaults.standard.object(forKey: taskPanelFontSizeKey) as? Double
        self.taskPanelFontSize = max(10, min(16, taskFontSize ?? 12))
        let defaultPanelRaw = UserDefaults.standard.string(forKey: defaultExpandedPanelKey) ?? ""
        self.defaultExpandedPanel = ExpandedPanelMode(rawValue: defaultPanelRaw) ?? .appStore
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
