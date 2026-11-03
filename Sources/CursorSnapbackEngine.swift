import Cocoa
import ApplicationServices

final class CursorSnapbackEngine {
    static let shared = CursorSnapbackEngine()

    var isSnapbackEnabled: Bool = true
    private(set) var lastMainScreenPoint: CGPoint = CGPoint(x: 600, y: 450)
    private var localMouseUpMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private var globalMouseUpMonitor: Any?

    private init() {}

    func startMonitoring() {
        stopMonitoring()

        // Track cursor position whenever moving on the primary display (outside Command Center window)
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.recordMainScreenCursorIfApplicable()
        }

        // When clicking inside the Command Center app with Snapback enabled, restore cursor to previous position
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }
            if self.isSnapbackEnabled && NSScreen.screens.count > 1 {
                let targetPt = self.lastMainScreenPoint
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.065) {
                    CGWarpMouseCursorPosition(targetPt)
                    CGAssociateMouseAndMouseCursorPosition(1)
                }
            }
            return event
        }

        // Also watch global mouse-up on secondary display (CF15T) if user touches another window on CF15T in Orchestrate mode
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self, self.isSnapbackEnabled, NSScreen.screens.count > 1 else { return }
            let currentQuartz = self.currentQuartzCursorPosition()
            if !self.isPointOnPrimaryScreen(currentQuartz) {
                let targetPt = self.lastMainScreenPoint
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    CGWarpMouseCursorPosition(targetPt)
                    CGAssociateMouseAndMouseCursorPosition(1)
                }
            }
        }
    }

    func stopMonitoring() {
        if let m = localMouseUpMonitor { NSEvent.removeMonitor(m); localMouseUpMonitor = nil }
        if let m = globalMouseMoveMonitor { NSEvent.removeMonitor(m); globalMouseMoveMonitor = nil }
        if let m = globalMouseUpMonitor { NSEvent.removeMonitor(m); globalMouseMoveMonitor = nil }
    }

    func warpBackToSavedMainScreenPositionNow() {
        guard NSScreen.screens.count > 1 else { return }
        let targetPt = lastMainScreenPoint
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            CGWarpMouseCursorPosition(targetPt)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    private func recordMainScreenCursorIfApplicable() {
        let pt = currentQuartzCursorPosition()
        if isPointOnPrimaryScreen(pt) {
            lastMainScreenPoint = pt
        }
    }

    private func currentQuartzCursorPosition() -> CGPoint {
        if let ev = CGEvent(source: nil) {
            return ev.location
        }
        let cocoaPt = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first?.frame.height ?? 1080
        return CGPoint(x: cocoaPt.x, y: primaryH - cocoaPt.y)
    }

    private func isPointOnPrimaryScreen(_ quartzPt: CGPoint) -> Bool {
        guard let primary = NSScreen.screens.first else { return true }
        let rect = CGRect(x: 0, y: 0, width: primary.frame.width, height: primary.frame.height)
        return rect.contains(quartzPt)
    }

    // MARK: - Resolve CF15T Screen (Supports Both Dual-Screen and Lid-Closed Single-Screen Clamshell)

    func resolveCF15TScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let external = screens.first(where: { scr in
            if let id = scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                return CGDisplayIsBuiltin(id) == 0
            }
            return false
        }) {
            return external
        }
        return screens.first
    }

    // MARK: - Move Command Center Window to CF15T Display & Shield Against Lid-Close Window Dumping

    func moveCommandCenterWindowToCF15T() -> String {
        return configureCommandCenterWindowFrame(dockedTopBar: false, dockHeight: 112, alwaysOnTop: false)
    }

    func configureCommandCenterWindowFrame(
        dockedTopBar: Bool,
        dockHeight: CGFloat = 112,
        alwaysOnTop: Bool = false
    ) -> String {
        guard let window = SiSTouchHardwareDriver.shared.targetCommandCenterWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return "Command Center window not found"
        }
        guard let targetScreen = resolveCF15TScreen() else {
            return "No active display found"
        }

        let vis = targetScreen.visibleFrame
        window.collectionBehavior = [.managed, .fullScreenPrimary, .canJoinAllSpaces]

        if dockedTopBar {
            let clampedH = min(vis.height * 0.52, max(96, dockHeight))
            let dockRect = NSRect(
                x: vis.minX,
                y: vis.maxY - clampedH,
                width: vis.width,
                height: clampedH
            )
            window.minSize = NSSize(width: 640, height: 88)
            window.level = .floating
            window.setFrame(dockRect, display: true, animate: true)
            window.orderFrontRegardless()
            return "Docked Touch Control Bar at top of \(targetScreen.localizedName) — Live App active below"
        } else {
            window.minSize = NSSize(width: 900, height: 540)
            // When alwaysOnTop is true (FULL CONTROL mode or Laptop Lid Closed), keep Command Center at .floating
            // so macOS NEVER dumps open laptop windows on top of the Command Center!
            window.level = alwaysOnTop ? .floating : .normal
            window.setFrame(vis, display: true, animate: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            return "Command Center active on \(targetScreen.localizedName) (\(alwaysOnTop ? "Always-On-Top Full Control Shield" : "Orchestrate Mode"))"
        }
    }
}
