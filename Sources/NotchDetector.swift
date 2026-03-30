import AppKit

struct NotchInfo {
    let exists: Bool
    let rect: CGRect       // Notch rect in screen coordinates (bottom-left origin)
    let screenFrame: CGRect
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    static let `default` = NotchInfo(
        exists: false,
        rect: .zero,
        screenFrame: NotchDetector.islandTargetScreen()?.frame ?? .zero,
        notchWidth: 220,
        notchHeight: 38
    )
}

final class NotchDetector {

    /// 灵动岛锚定的屏幕：**仅考虑内建显示器**（MacBook 本体屏），不包含外接扩展屏。
    /// 优先选带刘海（`safeAreaInsets.top > 0`）的内建屏；无内建则回退单屏场景（如 Mac mini）。
    static func islandTargetScreen() -> NSScreen? {
        let all = NSScreen.screens
        let builtIn = all.filter(\.isBuiltInDisplay)
        let pool: [NSScreen] = builtIn.isEmpty ? all : builtIn
        if let notched = pool.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return pool.first
    }

    /// 刘海宽度：读数变化小于该值则保持缓存（辅助区在切换 App / Stage 等时会偶发抖动）。
    private static let layoutWidthStick: CGFloat = 10
    /// 刘海高度（安全区顶 inset）：变化绝对值小于该值则保持缓存。
    /// 重要：之前对「略变高」0.5pt 就即时跟新，多任务后系统常会短暂报大 `safeAreaInsets.top`，导致 pill 永久变高。
    private static let layoutHeightStick: CGFloat = 6

    private static var layoutCache: NotchInfo?
    private static var layoutScreenFrame: CGRect?

    /// 当前瞬时读数（安全区、辅助区可能随系统动画跳动）。
    static func detect() -> NotchInfo {
        computeRaw()
    }

    /// 用于 pill / 面板定位：水平始终按**屏幕几何中心**对齐，并对高度/宽度抖动做对称滞回。
    static func layoutNotch() -> NotchInfo {
        let raw = computeRaw()
        guard let screen = islandTargetScreen() else {
            layoutCache = nil
            layoutScreenFrame = nil
            return raw
        }

        guard let prevFrame = layoutScreenFrame else {
            layoutScreenFrame = screen.frame
            layoutCache = raw
            return raw
        }
        if screenFrameMeaningfullyChanged(prevFrame, screen.frame) {
            layoutScreenFrame = screen.frame
            layoutCache = raw
            return raw
        }

        guard let cache = layoutCache else {
            layoutCache = raw
            return raw
        }

        let wJump = abs(raw.notchWidth - cache.notchWidth)
        let hJump = abs(raw.notchHeight - cache.notchHeight)
        if wJump >= layoutWidthStick || hJump >= layoutHeightStick {
            layoutCache = raw
            return raw
        }

        return pinNotch(cache, to: screen)
    }

    /// 避免 `screen.frame` 浮点/API 抖动的误触发，与上次比较时超过 ~1pt 才算换屏/改分辨率。
    private static func screenFrameMeaningfullyChanged(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.width - b.width) > 1
            || abs(a.height - b.height) > 1
            || abs(a.origin.x - b.origin.x) > 1
            || abs(a.origin.y - b.origin.y) > 1
    }

    /// 用当前 `screen` 更新 y / screenFrame；宽度高度取缓存，中心保持 `midX`。
    private static func pinNotch(_ info: NotchInfo, to screen: NSScreen) -> NotchInfo {
        let midX = screen.frame.midX
        let x = midX - info.notchWidth / 2
        let y = screen.frame.maxY - info.notchHeight
        return NotchInfo(
            exists: info.exists,
            rect: CGRect(x: x, y: y, width: info.notchWidth, height: info.notchHeight),
            screenFrame: screen.frame,
            notchWidth: info.notchWidth,
            notchHeight: info.notchHeight
        )
    }

    private static func computeRaw() -> NotchInfo {
        guard let screen = islandTargetScreen() else {
            return .default
        }

        let safeTop = screen.safeAreaInsets.top

        guard safeTop > 0 else {
            let fallbackWidth: CGFloat = 220
            let fallbackHeight: CGFloat = 38
            let midX = screen.frame.midX
            let x = midX - fallbackWidth / 2
            let y = screen.frame.maxY - fallbackHeight
            return NotchInfo(
                exists: false,
                rect: CGRect(x: x, y: y, width: fallbackWidth, height: fallbackHeight),
                screenFrame: screen.frame,
                notchWidth: fallbackWidth,
                notchHeight: fallbackHeight
            )
        }

        let auxLeft = screen.auxiliaryTopLeftArea ?? .zero
        let auxRight = screen.auxiliaryTopRightArea ?? .zero

        let notchWidth = screen.frame.width - auxLeft.width - auxRight.width
        let notchHeight = safeTop
        let midX = screen.frame.midX
        let notchX = midX - notchWidth / 2
        let notchY = screen.frame.maxY - notchHeight

        return NotchInfo(
            exists: true,
            rect: CGRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight),
            screenFrame: screen.frame,
            notchWidth: notchWidth,
            notchHeight: notchHeight
        )
    }
}
