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

        // Also watch global mouse-up on secondary display (CF15T) if user touches another window on CF15T
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
        if let m = globalMouseUpMonitor { NSEvent.removeMonitor(m); globalMouseUpMonitor = nil }
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

    // MARK: - Move Command Center Window to CF15T Display

    func moveCommandCenterWindowToCF15T() -> String {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else {
            return "Command Center window not found"
        }
        let screens = NSScreen.screens
        if screens.count > 1 {
            // Prefer a 1920x1080 screen or the first external display
            let targetScreen = screens.dropFirst().first(where: {
                Int($0.frame.width) == 1920 && Int($0.frame.height) == 1080
            }) ?? screens[1]

            let vis = targetScreen.visibleFrame
            window.setFrame(vis, display: true, animate: true)
            return "Moved Command Center to \(targetScreen.localizedName) (\(Int(targetScreen.frame.width))×\(Int(targetScreen.frame.height)))"
        } else {
            if let main = screens.first {
                window.setFrame(main.visibleFrame, display: true, animate: true)
            }
            return "CF15T not plugged in yet — maximized on built-in display"
        }
    }
}
