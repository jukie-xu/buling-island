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
        screenFrame: NSScreen.main?.frame ?? .zero,
        notchWidth: 220,
        notchHeight: 38
    )
}

final class NotchDetector {

    static func detect() -> NotchInfo {
        guard let screen = NSScreen.main else {
            return .default
        }

        let safeTop = screen.safeAreaInsets.top

        guard safeTop > 0 else {
            // No notch — fallback to top-center of screen
            let fallbackWidth: CGFloat = 220
            let fallbackHeight: CGFloat = 38
            let x = screen.frame.midX - fallbackWidth / 2
            let y = screen.frame.maxY - fallbackHeight
            return NotchInfo(
                exists: false,
                rect: CGRect(x: x, y: y, width: fallbackWidth, height: fallbackHeight),
                screenFrame: screen.frame,
                notchWidth: fallbackWidth,
                notchHeight: fallbackHeight
            )
        }

        // Calculate notch position from auxiliary areas
        let auxLeft = screen.auxiliaryTopLeftArea ?? .zero
        let auxRight = screen.auxiliaryTopRightArea ?? .zero

        // Notch X starts where the left auxiliary area ends
        let notchX = screen.frame.origin.x + auxLeft.width
        // Notch width is the gap between left and right auxiliary areas
        let notchWidth = screen.frame.width - auxLeft.width - auxRight.width
        let notchHeight = safeTop
        // Notch Y is at the top of the screen (macOS bottom-left origin)
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
