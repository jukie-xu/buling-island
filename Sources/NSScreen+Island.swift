import AppKit
import CoreGraphics

extension NSScreen {

    /// `NSScreen` 对应的 Core Graphics 显示器 ID。
    var islandDisplayID: CGDirectDisplayID? {
        guard let num = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return num.uint32Value
    }

    /// 是否为 **内建面板**（MacBook 液晶屏等）。外接、Sidecar 等一般为 false。
    var isBuiltInDisplay: Bool {
        guard let id = islandDisplayID else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }
}
