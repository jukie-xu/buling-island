import AppKit
import SwiftUI

/// NSPanel that can become key window (needed for text field input).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PanelManager {

    static let shared = PanelManager()

    private(set) var panel: NSPanel?
    private var clickMonitor: Any?
    private var pillClickMonitor: Any?
    private var pillRect: NSRect = .zero
    private var onPillClick: (() -> Void)?

    private init() {}

    func createPanel(with contentView: some View, onPillClick: @escaping () -> Void) {
        let notch = NotchDetector.detect()

        let panelWidth: CGFloat = max(notch.notchWidth + 40, 800)
        let panelHeight: CGFloat = 535
        let x = notch.rect.midX - panelWidth / 2
        let y = notch.screenFrame.maxY - panelHeight

        let panel = KeyablePanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        // Start collapsed: ignore mouse events on the panel itself
        panel.ignoresMouseEvents = true

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
        self.onPillClick = onPillClick

        // Calculate pill rect in screen coordinates
        let pillW = notch.notchWidth + 6
        let pillH = notch.notchHeight + 2
        let pillX = notch.rect.midX - pillW / 2
        let pillY = notch.screenFrame.maxY - pillH
        self.pillRect = NSRect(x: pillX, y: pillY, width: pillW, height: pillH)

        // Start monitoring clicks on the pill area
        startPillClickMonitor()
    }

    // MARK: - State transitions

    func setExpanded() {
        panel?.ignoresMouseEvents = false
        panel?.hasShadow = true
        panel?.makeKeyAndOrderFront(nil)
        stopPillClickMonitor()

        startClickOutsideMonitor { [weak self] in
            self?.onPillClick?()
        }
    }

    func setCollapsed() {
        stopClickOutsideMonitor()
        panel?.resignKey()
        panel?.ignoresMouseEvents = true
        panel?.hasShadow = false
        startPillClickMonitor()
    }

    // MARK: - Pill click monitoring (collapsed state)

    private func startPillClickMonitor() {
        stopPillClickMonitor()
        pillClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            let screenPoint = NSEvent.mouseLocation
            if self.pillRect.contains(screenPoint) {
                DispatchQueue.main.async {
                    self.onPillClick?()
                }
            }
        }
    }

    private func stopPillClickMonitor() {
        if let monitor = pillClickMonitor {
            NSEvent.removeMonitor(monitor)
            pillClickMonitor = nil
        }
    }

    // MARK: - Click outside monitoring (expanded state)

    private var outsideMonitor: Any?
    private var outsideLocalMonitor: Any?

    func startClickOutsideMonitor(onClickOutside: @escaping () -> Void) {
        stopClickOutsideMonitor()
        // Global monitor: clicks in other apps
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let panel = self?.panel else { return }
            let screenPoint = NSEvent.mouseLocation
            if !panel.frame.contains(screenPoint) {
                onClickOutside()
            }
        }
        // Local monitor: clicks in other windows of this app (e.g. settings)
        outsideLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let panel = self?.panel else { return event }
            if event.window != panel {
                onClickOutside()
            }
            return event
        }
    }

    func stopClickOutsideMonitor() {
        if let monitor = outsideMonitor {
            NSEvent.removeMonitor(monitor)
            outsideMonitor = nil
        }
        if let monitor = outsideLocalMonitor {
            NSEvent.removeMonitor(monitor)
            outsideLocalMonitor = nil
        }
    }
}
