import Foundation
import SwiftUI

extension Notification.Name {
    /// 灵动岛显示/点击展开等偏好变更，需同步面板与全局监听。
    static let panelInteractionPrefsDidChange = Notification.Name("buling.panelInteractionPrefsDidChange")
}

@MainActor
final class SettingsManager: ObservableObject {

    static let shared = SettingsManager()

    @Published var expandAnimation: ExpandAnimation {
        didSet { UserDefaults.standard.set(expandAnimation.rawValue, forKey: SettingsSchema.Key.expandAnimation) }
    }

    @Published var collapseAnimation: CollapseAnimation {
        didSet { UserDefaults.standard.set(collapseAnimation.rawValue, forKey: SettingsSchema.Key.collapseAnimation) }
    }

    /// Whether user has set a custom pill color (vs. auto follow system)
    @Published var useCustomPillColor: Bool {
        didSet { UserDefaults.standard.set(useCustomPillColor, forKey: SettingsSchema.Key.useCustomPillColor) }
    }

    @Published var pillBorderColor: Color {
        didSet { savePillColor() }
    }

    @Published var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: SettingsSchema.Key.displayMode) }
    }

    /// 关闭后隐藏刘海面板（等同于「关闭灵动岛」）。
    @Published var islandEnabled: Bool {
        didSet {
            UserDefaults.standard.set(islandEnabled, forKey: SettingsSchema.Key.islandEnabled)
            NotificationCenter.default.post(name: .panelInteractionPrefsDidChange, object: nil)
        }
    }

    /// 是否在收缩态下允许点击刘海区域展开。
    @Published var clickToExpand: Bool {
        didSet {
            UserDefaults.standard.set(clickToExpand, forKey: SettingsSchema.Key.clickToExpand)
            NotificationCenter.default.post(name: .panelInteractionPrefsDidChange, object: nil)
        }
    }

    /// 全屏场景下自动隐藏收缩态 pill（仅收缩态；展开面板不受影响）。
    @Published var autoHideCollapsedPillInFullscreen: Bool {
        didSet {
            UserDefaults.standard.set(autoHideCollapsedPillInFullscreen, forKey: SettingsSchema.Key.autoHideCollapsedPillInFullscreen)
            NotificationCenter.default.post(name: .panelInteractionPrefsDidChange, object: nil)
        }
    }

    /// 收缩态 pill 左侧扩展区展示内容。
    @Published var pillLeftSlot: PillSideWidget {
        didSet { UserDefaults.standard.set(pillLeftSlot.rawValue, forKey: SettingsSchema.Key.pillLeftSlot) }
    }

    /// 收缩态 pill 右侧扩展区展示内容。
    @Published var pillRightSlot: PillSideWidget {
        didSet { UserDefaults.standard.set(pillRightSlot.rawValue, forKey: SettingsSchema.Key.pillRightSlot) }
    }

    // MARK: - Pill appearance tuning

    /// 收缩态 pill 顶角外撇弯角尺度（越小越“尖/紧”，越大越“圆润”）。
    @Published var pillFlareRadius: CGFloat {
        didSet { UserDefaults.standard.set(Double(pillFlareRadius), forKey: SettingsSchema.Key.pillFlareRadius) }
    }

    /// 收缩态 pill 两侧额外可视宽度（用于把 P0 推得更外侧，让外撇更圆润），单侧值。
    @Published var pillVisualWidthOverhang: CGFloat {
        didSet { UserDefaults.standard.set(Double(pillVisualWidthOverhang), forKey: SettingsSchema.Key.pillVisualWidthOverhang) }
    }

    /// 收缩态 pill 额外可视高度（用于让 pill 略高于 notch，从而更“饱满”），为额外叠加值。
    @Published var pillVisualHeightOverhang: CGFloat {
        didSet { UserDefaults.standard.set(Double(pillVisualHeightOverhang), forKey: SettingsSchema.Key.pillVisualHeightOverhang) }
    }

    /// 收缩态 pill 左/右信息槽固定宽度（电量/网速）。
    @Published var pillSideSlotWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(pillSideSlotWidth), forKey: SettingsSchema.Key.pillSideSlotWidth) }
    }

    /// Claude 状态提醒是否触发 pill 底部下拉展示。
    @Published var claudeStretchHintEnabled: Bool {
        didSet { UserDefaults.standard.set(claudeStretchHintEnabled, forKey: SettingsSchema.Key.claudeStretchHintEnabled) }
    }

    /// Claude 状态提醒展示后是否自动缩回。
    @Published var claudeHintAutoCollapseEnabled: Bool {
        didSet { UserDefaults.standard.set(claudeHintAutoCollapseEnabled, forKey: SettingsSchema.Key.claudeHintAutoCollapseEnabled) }
    }

    /// Claude 提醒自动缩回延迟（秒）。
    @Published var claudeHintAutoCollapseDelay: Double {
        didSet { UserDefaults.standard.set(claudeHintAutoCollapseDelay, forKey: SettingsSchema.Key.claudeHintAutoCollapseDelay) }
    }

    /// 是否启用 iTerm2 外部会话输出捕获（实验特性）。
    @Published var claudeEnableITerm2Capture: Bool {
        didSet { UserDefaults.standard.set(claudeEnableITerm2Capture, forKey: SettingsSchema.Key.claudeEnableITerm2Capture) }
    }

    /// iTerm2 捕获轮询间隔（秒）。
    @Published var claudeITerm2PollInterval: Double {
        didSet { UserDefaults.standard.set(claudeITerm2PollInterval, forKey: SettingsSchema.Key.claudeITerm2PollInterval) }
    }

    /// Task 面板内容字号基准。
    @Published var taskPanelFontSize: Double {
        didSet { UserDefaults.standard.set(taskPanelFontSize, forKey: SettingsSchema.Key.taskPanelFontSize) }
    }

    /// 展开态允许显示的面板集合；至少保留一个。
    @Published var enabledExpandedPanels: Set<ExpandedPanelMode> {
        didSet {
            let sanitized = Self.sanitizedEnabledExpandedPanels(enabledExpandedPanels)
            if sanitized != enabledExpandedPanels {
                enabledExpandedPanels = sanitized
                return
            }
            UserDefaults.standard.set(Self.encodeExpandedPanels(enabledExpandedPanels), forKey: SettingsSchema.Key.enabledExpandedPanels)
            if !enabledExpandedPanels.contains(defaultExpandedPanel) {
                defaultExpandedPanel = preferredDefaultExpandedPanel()
            }
        }
    }

    /// 从收缩态点击药丸展开时默认进入的面板（无「异常」路由时）。
    @Published var defaultExpandedPanel: ExpandedPanelMode {
        didSet {
            let sanitized = normalizedExpandedPanelMode(defaultExpandedPanel)
            if sanitized != defaultExpandedPanel {
                defaultExpandedPanel = sanitized
                return
            }
            UserDefaults.standard.set(defaultExpandedPanel.rawValue, forKey: SettingsSchema.Key.defaultExpandedPanel)
        }
    }

    private init() {
        let expandRaw = UserDefaults.standard.string(forKey: SettingsSchema.Key.expandAnimation) ?? ""
        self.expandAnimation = ExpandAnimation(rawValue: expandRaw) ?? .spring

        let collapseRaw = UserDefaults.standard.string(forKey: SettingsSchema.Key.collapseAnimation) ?? ""
        self.collapseAnimation = CollapseAnimation(rawValue: collapseRaw) ?? .spring

        self.useCustomPillColor = UserDefaults.standard.object(forKey: SettingsSchema.Key.useCustomPillColor) as? Bool
            ?? SettingsSchema.Default.useCustomPillColor
        self.pillBorderColor = Self.loadPillColor()

        let modeRaw = UserDefaults.standard.string(forKey: SettingsSchema.Key.displayMode) ?? ""
        self.displayMode = DisplayMode(rawValue: modeRaw) ?? .grid

        self.islandEnabled = UserDefaults.standard.object(forKey: SettingsSchema.Key.islandEnabled) as? Bool
            ?? SettingsSchema.Default.islandEnabled
        self.clickToExpand = UserDefaults.standard.object(forKey: SettingsSchema.Key.clickToExpand) as? Bool
            ?? SettingsSchema.Default.clickToExpand
        self.autoHideCollapsedPillInFullscreen = UserDefaults.standard.object(forKey: SettingsSchema.Key.autoHideCollapsedPillInFullscreen) as? Bool
            ?? SettingsSchema.Default.autoHideCollapsedPillInFullscreen

        let leftRaw = UserDefaults.standard.string(forKey: SettingsSchema.Key.pillLeftSlot) ?? ""
        self.pillLeftSlot = PillSideWidget(rawValue: leftRaw) ?? SettingsSchema.Default.pillLeftSlot
        let rightRaw = UserDefaults.standard.string(forKey: SettingsSchema.Key.pillRightSlot) ?? ""
        self.pillRightSlot = PillSideWidget(rawValue: rightRaw) ?? SettingsSchema.Default.pillRightSlot

        let flareRadius = UserDefaults.standard.object(forKey: SettingsSchema.Key.pillFlareRadius) as? Double
        self.pillFlareRadius = CGFloat(flareRadius ?? Double(SettingsSchema.Default.pillFlareRadius))

        let overhang = UserDefaults.standard.object(forKey: SettingsSchema.Key.pillVisualWidthOverhang) as? Double
        self.pillVisualWidthOverhang = CGFloat(overhang ?? Double(SettingsSchema.Default.pillVisualWidthOverhang))

        let heightOverhang = UserDefaults.standard.object(forKey: SettingsSchema.Key.pillVisualHeightOverhang) as? Double
        self.pillVisualHeightOverhang = CGFloat(heightOverhang ?? Double(SettingsSchema.Default.pillVisualHeightOverhang))

        let slotW = UserDefaults.standard.object(forKey: SettingsSchema.Key.pillSideSlotWidth) as? Double
        self.pillSideSlotWidth = CGFloat(slotW ?? Double(SettingsSchema.Default.pillSideSlotWidth))

        self.claudeStretchHintEnabled = UserDefaults.standard.object(forKey: SettingsSchema.Key.claudeStretchHintEnabled) as? Bool
            ?? SettingsSchema.Default.claudeStretchHintEnabled
        self.claudeHintAutoCollapseEnabled = UserDefaults.standard.object(forKey: SettingsSchema.Key.claudeHintAutoCollapseEnabled) as? Bool
            ?? SettingsSchema.Default.claudeHintAutoCollapseEnabled
        let collapseDelay = UserDefaults.standard.object(forKey: SettingsSchema.Key.claudeHintAutoCollapseDelay) as? Double
        self.claudeHintAutoCollapseDelay = max(1, min(10, collapseDelay ?? SettingsSchema.Default.claudeHintAutoCollapseDelay))

        self.claudeEnableITerm2Capture = UserDefaults.standard.object(forKey: SettingsSchema.Key.claudeEnableITerm2Capture) as? Bool
            ?? SettingsSchema.Default.claudeEnableITerm2Capture
        let pollInterval = UserDefaults.standard.object(forKey: SettingsSchema.Key.claudeITerm2PollInterval) as? Double
        self.claudeITerm2PollInterval = max(1, min(5, pollInterval ?? SettingsSchema.Default.claudeITerm2PollInterval))
        let taskFontSize = UserDefaults.standard.object(forKey: SettingsSchema.Key.taskPanelFontSize) as? Double
        self.taskPanelFontSize = max(10, min(16, taskFontSize ?? SettingsSchema.Default.taskPanelFontSize))
        let enabledExpandedPanels = Self.decodeExpandedPanels(
            UserDefaults.standard.stringArray(forKey: SettingsSchema.Key.enabledExpandedPanels)
        )
        self.enabledExpandedPanels = enabledExpandedPanels
        let defaultPanelRaw = UserDefaults.standard.string(forKey: SettingsSchema.Key.defaultExpandedPanel) ?? ""
        let requestedDefaultPanel = ExpandedPanelMode(rawValue: defaultPanelRaw) ?? SettingsSchema.Default.defaultExpandedPanel
        self.defaultExpandedPanel = enabledExpandedPanels.contains(requestedDefaultPanel)
            ? requestedDefaultPanel
            : Self.preferredExpandedPanel(from: enabledExpandedPanels)
    }

    private func savePillColor() {
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: NSColor(pillBorderColor),
            requiringSecureCoding: false
        ) {
            UserDefaults.standard.set(data, forKey: SettingsSchema.Key.pillBorderColor)
        }
    }

    private static func loadPillColor() -> Color {
        guard let data = UserDefaults.standard.data(forKey: SettingsSchema.Key.pillBorderColor),
              let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else {
            return .white
        }
        return Color(nsColor)
    }

    var orderedEnabledExpandedPanels: [ExpandedPanelMode] {
        ExpandedPanelMode.allCases.filter { enabledExpandedPanels.contains($0) }
    }

    func isExpandedPanelEnabled(_ mode: ExpandedPanelMode) -> Bool {
        enabledExpandedPanels.contains(mode)
    }

    func normalizedExpandedPanelMode(_ mode: ExpandedPanelMode) -> ExpandedPanelMode {
        guard enabledExpandedPanels.contains(mode) else {
            return preferredDefaultExpandedPanel()
        }
        return mode
    }

    func preferredDefaultExpandedPanel() -> ExpandedPanelMode {
        Self.preferredExpandedPanel(from: enabledExpandedPanels)
    }

    private static func decodeExpandedPanels(_ rawValues: [String]?) -> Set<ExpandedPanelMode> {
        let decoded = Set((rawValues ?? []).compactMap(ExpandedPanelMode.init(rawValue:)))
        return sanitizedEnabledExpandedPanels(decoded.isEmpty ? SettingsSchema.Default.enabledExpandedPanels : decoded)
    }

    private static func encodeExpandedPanels(_ modes: Set<ExpandedPanelMode>) -> [String] {
        ExpandedPanelMode.allCases
            .filter { modes.contains($0) }
            .map(\.rawValue)
    }

    private static func sanitizedEnabledExpandedPanels(_ modes: Set<ExpandedPanelMode>) -> Set<ExpandedPanelMode> {
        let filtered = Set(ExpandedPanelMode.allCases.filter { modes.contains($0) })
        if filtered.isEmpty {
            return [SettingsSchema.Default.defaultExpandedPanel]
        }
        return filtered
    }

    private static func preferredExpandedPanel(from modes: Set<ExpandedPanelMode>) -> ExpandedPanelMode {
        for mode in ExpandedPanelMode.allCases where modes.contains(mode) {
            return mode
        }
        return SettingsSchema.Default.defaultExpandedPanel
    }
}
