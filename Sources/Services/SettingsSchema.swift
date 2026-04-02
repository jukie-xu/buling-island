import Foundation
import SwiftUI

enum SettingsSchema {
    enum Key {
        static let expandAnimation = "expandAnimation"
        static let collapseAnimation = "collapseAnimation"
        static let pillBorderColor = "pillBorderColor"
        static let useCustomPillColor = "useCustomPillColor"
        static let displayMode = "displayMode"
        static let islandEnabled = "islandEnabled"
        static let clickToExpand = "clickToExpand"
        static let autoHideCollapsedPillInFullscreen = "autoHideCollapsedPillInFullscreen"
        static let pillLeftSlot = "pillLeftSlot"
        static let pillRightSlot = "pillRightSlot"
        static let pillFlareRadius = "pillFlareRadius"
        static let pillVisualWidthOverhang = "pillVisualWidthOverhang"
        static let pillVisualHeightOverhang = "pillVisualHeightOverhang"
        static let pillSideSlotWidth = "pillSideSlotWidth"
        static let claudeStretchHintEnabled = "claudeStretchHintEnabled"
        static let claudeHintAutoCollapseEnabled = "claudeHintAutoCollapseEnabled"
        static let claudeHintAutoCollapseDelay = "claudeHintAutoCollapseDelay"
        static let claudeEnableITerm2Capture = "claudeEnableITerm2Capture"
        static let claudeITerm2PollInterval = "claudeITerm2PollInterval"
        static let taskPanelFontSize = "taskPanelFontSize"
        static let defaultExpandedPanel = "defaultExpandedPanel"
    }

    enum Default {
        static let useCustomPillColor = false
        static let islandEnabled = true
        static let clickToExpand = true
        static let autoHideCollapsedPillInFullscreen = false
        static let pillLeftSlot: PillSideWidget = .battery
        static let pillRightSlot: PillSideWidget = .networkSpeed
        static let pillFlareRadius: CGFloat = 4
        static let pillVisualWidthOverhang: CGFloat = 3
        static let pillVisualHeightOverhang: CGFloat = 0
        static let pillSideSlotWidth: CGFloat = 52
        static let claudeStretchHintEnabled = true
        static let claudeHintAutoCollapseEnabled = true
        static let claudeHintAutoCollapseDelay = 3.0
        static let claudeEnableITerm2Capture = false
        static let claudeITerm2PollInterval = 1.5
        static let taskPanelFontSize = 12.0
        static let defaultExpandedPanel: ExpandedPanelMode = .appStore
    }
}
