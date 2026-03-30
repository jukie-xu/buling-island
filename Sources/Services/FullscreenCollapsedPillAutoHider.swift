import AppKit
import CoreGraphics

/// Best-effort fullscreen detection for hiding the collapsed pill.
/// We avoid any private APIs and rely on window geometry heuristics.
@MainActor
final class FullscreenCollapsedPillAutoHider {

    private weak var viewModel: IslandViewModel?
    private var tokens: [NSObjectProtocol] = []
    private var timer: Timer?

    private var lastHidden: Bool = false
    private var lastEvalAt: Date = .distantPast

    /// Only auto-hide for browsers and media players. Everything else (e.g. WeChat) won't trigger.
    private static let allowedBundleIDs: Set<String> = [
        // Browsers
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "com.apple.SafariTechnologyPreview",

        // Players
        "com.apple.QuickTimePlayerX",
        "com.apple.TV",
        "com.apple.Music",
        "com.colliderli.iina",
        "org.videolan.vlc",
        "io.mpv",
    ]

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        start()
    }

    // App 生命周期内常驻，不依赖 deinit 做清理。

    func start() {
        stop()

        let center = NotificationCenter.default
        let wCenter = NSWorkspace.shared.notificationCenter

        func observe(_ c: NotificationCenter, _ name: Notification.Name) {
            let t = c.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.evaluateSoon()
                }
            }
            tokens.append(t)
        }

        observe(center, NSApplication.didBecomeActiveNotification)
        observe(center, NSApplication.didChangeScreenParametersNotification)
        observe(wCenter, NSWorkspace.activeSpaceDidChangeNotification)
        observe(wCenter, NSWorkspace.didActivateApplicationNotification)

        // Low-frequency polling to catch browsers/video players that don't emit obvious signals.
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        RunLoop.main.add(timer!, forMode: .common)

        evaluateSoon()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
    }

    private func evaluateSoon() {
        // Avoid thrashing during rapid space transitions.
        if Date().timeIntervalSince(lastEvalAt) < 0.18 { return }
        evaluate()
    }

    private func evaluate() {
        lastEvalAt = Date()

        guard let vm = viewModel else { return }
        let s = SettingsManager.shared

        // Only apply in collapsed state.
        guard vm.state == .collapsed else {
            if lastHidden {
                lastHidden = false
                PanelManager.shared.setCollapsedPillHiddenForFullscreen(false)
            }
            return
        }

        guard s.islandEnabled else { return }

        // Feature toggle.
        guard s.autoHideCollapsedPillInFullscreen else {
            if lastHidden {
                lastHidden = false
                PanelManager.shared.setCollapsedPillHiddenForFullscreen(false)
            }
            return
        }

        let shouldConsiderDisplay = isMainDisplayBuiltinOrMirrored()
        let isFullscreenLike = shouldConsiderDisplay ? isFrontmostAppFullscreenLikeOnMainScreen() : false
        let hide = isFullscreenLike

        if hide != lastHidden {
            lastHidden = hide
            PanelManager.shared.setCollapsedPillHiddenForFullscreen(hide)
        }
    }

    private func isMainDisplayBuiltinOrMirrored() -> Bool {
        guard let screen = NSScreen.main,
              let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return true }

        let did = CGDirectDisplayID(truncating: num)
        if CGDisplayIsBuiltin(did) != 0 { return true }
        if CGDisplayIsInMirrorSet(did) != 0 { return true }
        return false
    }

    private func isFrontmostAppFullscreenLikeOnMainScreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if front.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        guard let bid = front.bundleIdentifier, Self.allowedBundleIDs.contains(bid) else { return false }

        guard let screen = NSScreen.main else { return false }
        let screenFrame = screen.frame
        let screenArea = max(1, screenFrame.width * screenFrame.height)

        let frontPID = front.processIdentifier

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }

        var bestCoverage: CGFloat = 0

        for w in info {
            guard let ownerPID = w[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == frontPID
            else { continue }

            // Layer 0 is normal windows. Higher layers are overlays/menus.
            if let layer = w[kCGWindowLayer as String] as? Int, layer != 0 { continue }
            if let alpha = w[kCGWindowAlpha as String] as? CGFloat, alpha < 0.5 { continue }
            if let onScreen = w[kCGWindowIsOnscreen as String] as? Bool, !onScreen { continue }

            guard let boundsDict = w[kCGWindowBounds as String] as? [String: Any],
                  let b = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            // Compute coverage against main screen frame.
            let intersection = b.intersection(screenFrame)
            if intersection.isNull { continue }
            let coverage = (intersection.width * intersection.height) / screenArea
            bestCoverage = max(bestCoverage, coverage)
        }

        // Heuristic threshold: fullscreen windows generally cover almost all visible area.
        return bestCoverage >= 0.92
    }
}

