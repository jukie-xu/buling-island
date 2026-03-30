import SwiftUI

/// 展开态刘海面板为纯黑底时，子视图应使用浅色前景（标签、占位等）。
private struct UseLightContentOnIslandPanelKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var useLightContentOnIslandPanel: Bool {
        get { self[UseLightContentOnIslandPanelKey.self] }
        set { self[UseLightContentOnIslandPanelKey.self] = newValue }
    }
}
