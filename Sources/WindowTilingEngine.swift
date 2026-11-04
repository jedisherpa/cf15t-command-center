import Cocoa
import ApplicationServices

// Dynamic C bridge for CGWindowListCreateImage on macOS 15+ (Swift 6 marks it obsoleted in headers,
// while the CoreGraphics C symbol remains present and fast).
private typealias CGWindowListCreateImageFunc = @convention(c) (
    CGRect,
    CGWindowListOption,
    CGWindowID,
    CGWindowImageOption
) -> Unmanaged<CGImage>?

final class WindowTilingEngine {
    static let shared = WindowTilingEngine()

    private var savedOriginalFrames: [CGWindowID: CGRect] = [:]
    private let createImageSym: CGWindowListCreateImageFunc?

    private init() {
        if let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
           let sym = dlsym(handle, "CGWindowListCreateImage") {
            createImageSym = unsafeBitCast(sym, to: CGWindowListCreateImageFunc.self)
        } else {
            createImageSym = nil
        }
    }

    // MARK: - Accessibility Trust Check

    func isAccessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        if promptIfNeeded {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    // MARK: - Enumerate Open Windows

    func fetchOpenWindows(capturePreviews: Bool = true, excludedPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> [MonitoredWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let runningAppsByPID: [pid_t: NSRunningApplication] = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )

        var result: [MonitoredWindow] = []
        var perAppWindowCounter: [pid_t: Int] = [:]

        let ignoredOwners: Set<String> = [
            "WindowServer", "Control Center", "Notification Center", "SystemUIServer",
            "Dock", "Spotlight", "Wallpaper", "TextInputMenuAgent", "UniversalControl",
            "CursorUIViewService", "ScreenCaptureKit", "loginwindow",
            "universalAccessAuthWarn", "MobileDeviceUpdater", "CoreServicesUIAgent",
            "UserNotificationCenter", "SecurityAgent"
        ]

        for entry in infoList {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != excludedPID else {
                continue
            }
            guard let ownerName = entry[kCGWindowOwnerName as String] as? String,
                  !ignoredOwners.contains(ownerName) else {
                continue
            }
            guard let windowNumber = entry[kCGWindowNumber as String] as? UInt32 else {
                continue
            }
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 160, bounds.height >= 120 else {
                continue
            }

            let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1.0
            if alpha < 0.05 { continue }

            let title = (entry[kCGWindowName as String] as? String) ?? ""
            let runningApp = runningAppsByPID[ownerPID]
            let bundleID = runningApp?.bundleIdentifier
            let appIcon = runningApp?.icon
            let resolvedAppName: String = {
                if let bid = bundleID?.lowercased(), bid.contains("com.openai.codex") {
                    return "Codex"
                }
                return ownerName
            }()

            let idx = perAppWindowCounter[ownerPID, default: 0]
            perAppWindowCounter[ownerPID] = idx + 1

            let detectedPlatform = detectPlatform(appName: resolvedAppName, bundleID: bundleID, windowTitle: title)
            var preview: NSImage? = nil
            if capturePreviews {
                preview = captureWindowSnapshot(windowID: CGWindowID(windowNumber))
            }

            var win = MonitoredWindow(
                id: CGWindowID(windowNumber),
                ownerPID: ownerPID,
                appName: resolvedAppName,
                bundleIdentifier: bundleID,
                windowTitle: title,
                bounds: bounds,
                windowIndexInApp: idx,
                platform: detectedPlatform,
                appIcon: appIcon,
                previewImage: preview
            )
            win.focusedContentImage = AppContentFeedExtractor.shared.cropActiveConversationImage(from: preview, for: win)
            win.liveDigest = AppContentFeedExtractor.shared.extractLiveDigest(for: win)
            result.append(win)
        }

        // Ensure Antigravity's live session thread is always visible in the matrix if active
        if !result.contains(where: { $0.platform == .antigravity }),
           let agyDigest = AppContentFeedExtractor.shared.buildAntigravityLiveDigest(window: nil) {
            let agyWin = MonitoredWindow(
                id: 999_999,
                ownerPID: ProcessInfo.processInfo.processIdentifier,
                appName: "Antigravity",
                bundleIdentifier: "com.google.antigravity",
                windowTitle: "Live Agent Workspace & Thread",
                bounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
                windowIndexInApp: 0,
                platform: .antigravity,
                appIcon: NSImage(systemSymbolName: "sparkles.rectangle.stack.fill", accessibilityDescription: "Antigravity"),
                previewImage: nil,
                liveDigest: agyDigest
            )
            result.insert(agyWin, at: min(2, result.count))
        }

        return result
    }

    func captureWindowSnapshot(windowID: CGWindowID) -> NSImage? {
        guard let fn = createImageSym else { return nil }
        // .boundsIgnoreFraming (1 << 0) | .nominalResolution (1 << 4)
        let imageOption = CGWindowImageOption(rawValue: (1 << 0) | (1 << 4))
        guard let unmanaged = fn(.null, .optionIncludingWindow, windowID, imageOption) else {
            return nil
        }
        let cgImage = unmanaged.takeRetainedValue()
        if cgImage.width <= 4 || cgImage.height <= 4 {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func detectPlatform(appName: String, bundleID: String?, windowTitle: String) -> AgentPlatform? {
        let combined = "\(appName) \(bundleID ?? "") \(windowTitle)".lowercased()
        for platform in AgentPlatform.allCases {
            for kw in platform.processMatchKeywords {
                if combined.contains(kw) {
                    return platform
                }
            }
        }
        return nil
    }

    // MARK: - Focus / Raise Single Window

    func focusWindow(_ window: MonitoredWindow) {
        if let app = NSRunningApplication(processIdentifier: window.ownerPID) {
            NSApp.yieldActivation(to: app)
            app.unhide()
            app.activate(options: [.activateAllWindows])
            if let bundleURL = app.bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: config, completionHandler: nil)
            }
        }
        if let axWin = findAXWindow(for: window) {
            AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
    }

    func openSystemAccessibilitySettings() {
        _ = isAccessibilityTrusted(promptIfNeeded: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Physically Tile Real macOS Windows ("Center Stage + Border")

    func focusAndFillSingleWindow(
        _ window: MonitoredWindow,
        targetDisplay: TargetDisplayMode,
        topDockReserveHeight: CGFloat = 0,
        fillDisplay: Bool = true
    ) {
        if savedOriginalFrames[window.id] == nil {
            savedOriginalFrames[window.id] = window.bounds
        }

        if fillDisplay && isAccessibilityTrusted(promptIfNeeded: false) {
            var canvas = resolveTargetCanvas(for: window, displayMode: targetDisplay)
            if topDockReserveHeight > 0 && canvas.height > topDockReserveHeight + 160 {
                canvas.origin.y += topDockReserveHeight
                canvas.size.height -= topDockReserveHeight
            }
            let insetFrame = sanitizeRect(canvas.insetBy(dx: 8, dy: 8)).integral
            applyFrame(insetFrame, to: window, raise: true, activateApp: true)
        }
        focusWindow(window)
    }

    func gatherAllWindowsOntoDisplay(
        windows: [MonitoredWindow],
        targetDisplay: TargetDisplayMode,
        topDockReserveHeight: CGFloat = 0
    ) {
        guard isAccessibilityTrusted(promptIfNeeded: false) else { return }
        for win in windows where win.id != 999_999 {
            if savedOriginalFrames[win.id] == nil {
                savedOriginalFrames[win.id] = win.bounds
            }
            var canvas = resolveTargetCanvas(for: win, displayMode: targetDisplay)
            if topDockReserveHeight > 0 && canvas.height > topDockReserveHeight + 160 {
                canvas.origin.y += topDockReserveHeight
                canvas.size.height -= topDockReserveHeight
            }
            let targetFrame = sanitizeRect(canvas.insetBy(dx: 10, dy: 10)).integral
            applyFrame(targetFrame, to: win, raise: true, activateApp: false)
        }
    }

    func sendKeystrokeToTargetWindow(
        keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        targetWindow: MonitoredWindow?
    ) {
        if let win = targetWindow, win.id != 999_999 {
            focusWindow(win)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let src = CGEventSource(stateID: .hidSystemState)
            if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
               let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
                down.flags = flags
                up.flags = flags
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    func sendTextToTargetWindow(
        _ text: String,
        pressReturn: Bool,
        targetWindow: MonitoredWindow?
    ) {
        guard !text.isEmpty || pressReturn else { return }
        if let win = targetWindow, win.id != 999_999 {
            focusWindow(win)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let src = CGEventSource(stateID: .hidSystemState)
            if !text.isEmpty {
                let utf16Chars = Array(text.utf16)
                if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                   let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                    down.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
                    up.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
                    down.post(tap: .cghidEventTap)
                    up.post(tap: .cghidEventTap)
                }
            }
            if pressReturn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let retDown = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true),
                       let retUp = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false) {
                        retDown.post(tap: .cghidEventTap)
                        retUp.post(tap: .cghidEventTap)
                    }
                }
            }
        }
    }

    func sendScrollToTargetWindow(deltaY: Int32, targetWindow: MonitoredWindow?) {
        if let win = targetWindow, win.id != 999_999 {
            let targetPt = CGPoint(x: win.bounds.midX, y: win.bounds.midY)
            CGWarpMouseCursorPosition(targetPt)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        if let scrollEv = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) {
            scrollEv.post(tap: .cghidEventTap)
        }
    }

    func tileWindowsOnScreen(
        stageWindow: MonitoredWindow,
        borderWindows: [MonitoredWindow],
        mode: TilingLayoutMode,
        targetDisplay: TargetDisplayMode,
        stageScale: CGFloat = 0.62,
        topDockReserveHeight: CGFloat = 0
    ) {
        let allToTile = [stageWindow] + borderWindows.filter { $0.id != stageWindow.id }
        guard !allToTile.isEmpty else { return }

        // Save original frames the first time we see each window ID
        for win in allToTile {
            if savedOriginalFrames[win.id] == nil {
                savedOriginalFrames[win.id] = win.bounds
            }
        }

        var canvas = resolveTargetCanvas(for: stageWindow, displayMode: targetDisplay)
        if topDockReserveHeight > 0 && canvas.height > topDockReserveHeight + 160 {
            canvas.origin.y += topDockReserveHeight
            canvas.size.height -= topDockReserveHeight
        }
        let frames = computeLayoutFrames(
            count: allToTile.count,
            canvas: canvas,
            mode: mode,
            stageScale: stageScale
        )

        // Apply frames to border windows first and bring them on screen, then stage window last so it's raised on top
        for (index, win) in allToTile.enumerated().reversed() {
            guard index < frames.count else { continue }
            let targetFrame = frames[index].integral
            applyFrame(targetFrame, to: win, raise: true, activateApp: index == 0)
        }
        focusWindow(stageWindow)
    }

    func restoreOriginalWindowFrames(windows: [MonitoredWindow]) {
        for win in windows {
            if let original = savedOriginalFrames[win.id] {
                applyFrame(original, to: win, raise: false, activateApp: false)
            }
        }
        savedOriginalFrames.removeAll()
    }

    // MARK: - Compute Tiling Geometry (Quartz Top-Left Origin Coordinates)

    func computeLayoutFrames(
        count: Int,
        canvas: CGRect,
        mode: TilingLayoutMode,
        gap: CGFloat = 10,
        stageScale: CGFloat = 0.62
    ) -> [CGRect] {
        guard count > 0,
              !canvas.isNull,
              !canvas.isInfinite,
              canvas.width.isFinite,
              canvas.height.isFinite,
              canvas.width >= 160,
              canvas.height >= 120 else {
            return []
        }
        let insetCanvas = canvas.insetBy(dx: gap, dy: gap)
        guard insetCanvas.width >= 100, insetCanvas.height >= 80 else {
            return []
        }

        if count == 1 {
            return [sanitizeRect(insetCanvas)]
        }

        let clampedScale = max(0.42, min(0.80, stageScale))

        let rawRects: [CGRect]
        switch mode {
        case .centerStageBorder:
            rawRects = computeCenterStageWithPerimeterBorder(count: count, area: insetCanvas, gap: gap, stageScale: clampedScale)

        case .goldenFibonacciSpiral:
            rawRects = computeGoldenFibonacciSpiral(count: count, area: insetCanvas, gap: gap)

        case .leftStagePerimeter:
            rawRects = computeLeftStageWithRightBottomBorder(count: count, area: insetCanvas, gap: gap, stageScale: clampedScale)

        case .equalSimultaneousGrid:
            rawRects = computeEqualGrid(count: count, area: insetCanvas, gap: gap)

        case .dualVoiceSplit:
            rawRects = computeDualSplitWithBottomBorder(count: count, area: insetCanvas, gap: gap)
        }

        return rawRects.map { sanitizeRect($0) }
    }

    /// Recursive Golden Ratio (φ = (1 + √5)/2 ≈ 1.6180339887) Whirling Rectangle Subdivision.
    /// Partitions the 2D screen manifold along a self-similar logarithmic spiral r(θ) = a·φ^(2θ/π).
    private func computeGoldenFibonacciSpiral(count: Int, area: CGRect, gap: CGFloat) -> [CGRect] {
        let invPhi: CGFloat = 0.6180339887498949 // (√5 - 1) / 2
        var rects: [CGRect] = []
        var remainder = area

        // Spiral up to 5 golden subdivisions; if more windows remain, subdivide the final chamber evenly
        let maxSpiralSteps = min(count - 1, 5)

        for step in 0..<maxSpiralSteps {
            let phase = step % 4
            switch phase {
            case 0: // Left Golden Chamber (61.8% width)
                let w = max(90, floor((remainder.width - gap) * invPhi))
                let chamber = CGRect(x: remainder.minX, y: remainder.minY, width: w, height: remainder.height)
                rects.append(chamber)
                remainder = CGRect(
                    x: remainder.minX + w + gap,
                    y: remainder.minY,
                    width: max(80, remainder.width - w - gap),
                    height: remainder.height
                )

            case 1: // Top Golden Chamber (61.8% height)
                let h = max(70, floor((remainder.height - gap) * invPhi))
                let chamber = CGRect(x: remainder.minX, y: remainder.minY, width: remainder.width, height: h)
                rects.append(chamber)
                remainder = CGRect(
                    x: remainder.minX,
                    y: remainder.minY + h + gap,
                    width: remainder.width,
                    height: max(70, remainder.height - h - gap)
                )

            case 2: // Right Golden Chamber (61.8% width from right)
                let w = max(90, floor((remainder.width - gap) * invPhi))
                let remW = max(80, remainder.width - w - gap)
                let chamber = CGRect(
                    x: remainder.minX + remW + gap,
                    y: remainder.minY,
                    width: w,
                    height: remainder.height
                )
                rects.append(chamber)
                remainder = CGRect(x: remainder.minX, y: remainder.minY, width: remW, height: remainder.height)

            default: // Bottom Golden Chamber (61.8% height from bottom)
                let h = max(70, floor((remainder.height - gap) * invPhi))
                let remH = max(70, remainder.height - h - gap)
                let chamber = CGRect(
                    x: remainder.minX,
                    y: remainder.minY + remH + gap,
                    width: remainder.width,
                    height: h
                )
                rects.append(chamber)
                remainder = CGRect(x: remainder.minX, y: remainder.minY, width: remainder.width, height: remH)
            }
        }

        let leftOver = count - rects.count
        if leftOver == 1 {
            rects.append(remainder)
        } else if leftOver > 1 {
            let subGrid = computeEqualGrid(count: leftOver, area: remainder, gap: max(6, gap * 0.7))
            rects.append(contentsOf: subGrid)
        }

        return rects
    }

    private func sanitizeRect(_ r: CGRect) -> CGRect {
        let safeX = (r.origin.x.isFinite && !r.origin.x.isNaN) ? r.origin.x : 0
        let safeY = (r.origin.y.isFinite && !r.origin.y.isNaN) ? r.origin.y : 0
        let safeW = (r.size.width.isFinite && !r.size.width.isNaN) ? max(48, r.size.width) : 120
        let safeH = (r.size.height.isFinite && !r.size.height.isNaN) ? max(36, r.size.height) : 80
        return CGRect(x: safeX, y: safeY, width: safeW, height: safeH)
    }

    /// Places the active window large in the center (or center-top) and arranges all other windows around the border
    /// so every single window remains visible simultaneously around the edges.
    private func computeCenterStageWithPerimeterBorder(count: Int, area: CGRect, gap: CGFloat, stageScale: CGFloat) -> [CGRect] {
        let borderCount = count - 1
        if borderCount == 1 {
            let stageW = floor((area.width - gap) * stageScale)
            let rightW = area.width - gap - stageW
            let stageRect = CGRect(x: area.minX, y: area.minY, width: stageW, height: area.height)
            let rightRect = CGRect(x: area.minX + stageW + gap, y: area.minY, width: rightW, height: area.height)
            return [stageRect, rightRect]
        }

        if borderCount == 2 {
            let stageW = floor((area.width - gap) * stageScale)
            let rightW = area.width - gap - stageW
            let stageRect = CGRect(x: area.minX, y: area.minY, width: stageW, height: area.height)
            let tileH = floor((area.height - gap) / 2.0)
            let r1 = CGRect(x: area.minX + stageW + gap, y: area.minY, width: rightW, height: tileH)
            let r2 = CGRect(x: area.minX + stageW + gap, y: area.minY + tileH + gap, width: rightW, height: area.height - tileH - gap)
            return [stageRect, r1, r2]
        }

        let sideFraction = max(0.12, (1.0 - stageScale) * 0.50)
        let bottomFraction = max(0.16, (1.0 - stageScale) * 0.60)

        if borderCount <= 4 {
            let leftW = floor(area.width * sideFraction)
            let rightW = floor(area.width * sideFraction)
            let centerW = area.width - leftW - rightW - (gap * 2)
            let bottomH = floor(area.height * bottomFraction)
            let stageH = area.height - bottomH - gap

            let stageRect = CGRect(
                x: area.minX + leftW + gap,
                y: area.minY,
                width: centerW,
                height: stageH
            )

            var results: [CGRect] = [stageRect]

            // Border 1: Left rail
            let leftRect = CGRect(x: area.minX, y: area.minY, width: leftW, height: area.height)
            results.append(leftRect)

            // Border 2: Bottom center rail (underneath stage)
            let bottomCenterRect = CGRect(
                x: area.minX + leftW + gap,
                y: area.minY + stageH + gap,
                width: centerW,
                height: bottomH
            )
            results.append(bottomCenterRect)

            // Remaining 1 or 2 tiles on Right rail
            let rightCount = borderCount - 2
            let rightTileH = floor((area.height - CGFloat(rightCount - 1) * gap) / CGFloat(rightCount))
            for i in 0..<rightCount {
                let y = area.minY + CGFloat(i) * (rightTileH + gap)
                let h = (i == rightCount - 1) ? (area.maxY - y) : rightTileH
                results.append(CGRect(
                    x: area.minX + leftW + gap + centerW + gap,
                    y: y,
                    width: rightW,
                    height: h
                ))
            }
            return results
        }

        // For 5+ border windows: Center Stage surrounded by Left rail, Right rail, and Bottom perimeter row
        let sideW = floor(area.width * sideFraction)
        let bottomH = floor(area.height * bottomFraction)
        let centerW = area.width - (sideW * 2) - (gap * 2)
        let stageH = area.height - bottomH - gap

        let stageRect = CGRect(
            x: area.minX + sideW + gap,
            y: area.minY,
            width: centerW,
            height: stageH
        )
        var results: [CGRect] = [stageRect]

        let leftCount = max(1, borderCount / 3)
        let rightCount = max(1, (borderCount - leftCount) / 2)
        let bottomCount = max(1, borderCount - leftCount - rightCount)

        // Left border column (above bottom strip)
        let leftColH = stageH
        let leftTileH = floor((leftColH - CGFloat(leftCount - 1) * gap) / CGFloat(leftCount))
        for i in 0..<leftCount {
            let y = area.minY + CGFloat(i) * (leftTileH + gap)
            let h = (i == leftCount - 1) ? (area.minY + leftColH - y) : leftTileH
            results.append(CGRect(x: area.minX, y: y, width: sideW, height: h))
        }

        // Right border column (above bottom strip)
        let rightColH = stageH
        let rightTileH = floor((rightColH - CGFloat(rightCount - 1) * gap) / CGFloat(rightCount))
        for i in 0..<rightCount {
            let y = area.minY + CGFloat(i) * (rightTileH + gap)
            let h = (i == rightCount - 1) ? (area.minY + rightColH - y) : rightTileH
            results.append(CGRect(x: area.maxX - sideW, y: y, width: sideW, height: h))
        }

        // Full-width bottom border strip
        let bottomTileW = floor((area.width - CGFloat(bottomCount - 1) * gap) / CGFloat(bottomCount))
        for i in 0..<bottomCount {
            let x = area.minX + CGFloat(i) * (bottomTileW + gap)
            let w = (i == bottomCount - 1) ? (area.maxX - x) : bottomTileW
            results.append(CGRect(x: x, y: area.minY + stageH + gap, width: w, height: bottomH))
        }

        return results
    }

    private func computeLeftStageWithRightBottomBorder(count: Int, area: CGRect, gap: CGFloat, stageScale: CGFloat) -> [CGRect] {
        let borderCount = count - 1
        let stageW = floor((area.width - gap) * stageScale)
        let rightW = area.width - gap - stageW

        if borderCount <= 3 {
            let stageRect = CGRect(x: area.minX, y: area.minY, width: stageW, height: area.height)
            var results: [CGRect] = [stageRect]
            let tileH = floor((area.height - CGFloat(borderCount - 1) * gap) / CGFloat(borderCount))
            for i in 0..<borderCount {
                let y = area.minY + CGFloat(i) * (tileH + gap)
                let h = (i == borderCount - 1) ? (area.maxY - y) : tileH
                results.append(CGRect(x: area.minX + stageW + gap, y: y, width: rightW, height: h))
            }
            return results
        } else {
            let bottomH = floor(area.height * 0.25)
            let stageH = area.height - bottomH - gap
            let stageRect = CGRect(x: area.minX, y: area.minY, width: stageW, height: stageH)
            var results: [CGRect] = [stageRect]

            let rightCount = borderCount / 2
            let bottomCount = borderCount - rightCount

            let rightTileH = floor((stageH - CGFloat(rightCount - 1) * gap) / CGFloat(rightCount))
            for i in 0..<rightCount {
                let y = area.minY + CGFloat(i) * (rightTileH + gap)
                let h = (i == rightCount - 1) ? (area.minY + stageH - y) : rightTileH
                results.append(CGRect(x: area.minX + stageW + gap, y: y, width: rightW, height: h))
            }

            let bottomTileW = floor((area.width - CGFloat(bottomCount - 1) * gap) / CGFloat(bottomCount))
            for i in 0..<bottomCount {
                let x = area.minX + CGFloat(i) * (bottomTileW + gap)
                let w = (i == bottomCount - 1) ? (area.maxX - x) : bottomTileW
                results.append(CGRect(x: x, y: area.minY + stageH + gap, width: w, height: bottomH))
            }
            return results
        }
    }

    private func computeEqualGrid(count: Int, area: CGRect, gap: CGFloat) -> [CGRect] {
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let tileW = floor((area.width - CGFloat(cols - 1) * gap) / CGFloat(cols))
        let tileH = floor((area.height - CGFloat(rows - 1) * gap) / CGFloat(rows))

        var rects: [CGRect] = []
        for idx in 0..<count {
            let r = idx / cols
            let c = idx % cols
            let x = area.minX + CGFloat(c) * (tileW + gap)
            let y = area.minY + CGFloat(r) * (tileH + gap)
            rects.append(CGRect(x: x, y: y, width: tileW, height: tileH))
        }
        return rects
    }

    private func computeDualSplitWithBottomBorder(count: Int, area: CGRect, gap: CGFloat) -> [CGRect] {
        if count <= 2 {
            let halfW = floor((area.width - gap) / 2.0)
            return [
                CGRect(x: area.minX, y: area.minY, width: halfW, height: area.height),
                CGRect(x: area.minX + halfW + gap, y: area.minY, width: area.width - halfW - gap, height: area.height)
            ]
        }
        let bottomH = floor(area.height * 0.24)
        let topH = area.height - bottomH - gap
        let halfW = floor((area.width - gap) / 2.0)
        var rects: [CGRect] = [
            CGRect(x: area.minX, y: area.minY, width: halfW, height: topH),
            CGRect(x: area.minX + halfW + gap, y: area.minY, width: area.width - halfW - gap, height: topH)
        ]
        let rem = count - 2
        let tileW = floor((area.width - CGFloat(rem - 1) * gap) / CGFloat(rem))
        for i in 0..<rem {
            let x = area.minX + CGFloat(i) * (tileW + gap)
            rects.append(CGRect(x: x, y: area.minY + topH + gap, width: tileW, height: bottomH))
        }
        return rects
    }

    // MARK: - Resolve Quartz Screen Canvas (Top-Left Origin)

    private func resolveTargetCanvas(for window: MonitoredWindow, displayMode: TargetDisplayMode) -> CGRect {
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else {
            return CGRect(x: 0, y: 28, width: 1440, height: 870)
        }
        let primaryHeight = primaryScreen.frame.height

        let chosenScreen: NSScreen
        switch displayMode {
        case .primaryDisplay:
            chosenScreen = screens.first(where: { scr in
                if let id = scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                    return CGDisplayIsBuiltin(id) != 0
                }
                return false
            }) ?? primaryScreen

        case .externalDisplay:
            chosenScreen = DisplayTargetManager.shared.commandCenterScreen() ?? screens.first(where: { scr in
                if let id = scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                    return CGDisplayIsBuiltin(id) == 0
                }
                return false
            }) ?? screens.dropFirst().first ?? primaryScreen

        case .windowCurrentDisplay:
            let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            chosenScreen = screens.first(where: { scr in
                let quartzRect = convertNSScreenVisibleToQuartz(scr, primaryHeight: primaryHeight)
                return quartzRect.insetBy(dx: -50, dy: -50).contains(center)
            }) ?? primaryScreen
        }

        return convertNSScreenVisibleToQuartz(chosenScreen, primaryHeight: primaryHeight)
    }

    private func convertNSScreenVisibleToQuartz(_ screen: NSScreen, primaryHeight: CGFloat) -> CGRect {
        let vis = screen.visibleFrame
        let quartzY = primaryHeight - (vis.origin.y + vis.size.height)
        return CGRect(x: vis.origin.x, y: quartzY, width: vis.size.width, height: vis.size.height)
    }

    // MARK: - Apply Frame via AXUIElement

    private func applyFrame(_ frame: CGRect, to window: MonitoredWindow, raise: Bool, activateApp: Bool) {
        if activateApp, let app = NSRunningApplication(processIdentifier: window.ownerPID) {
            app.activate(options: [.activateAllWindows])
        }

        guard let axWindow = findAXWindow(for: window) else { return }

        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)

        var point = frame.origin
        var size = frame.size

        if let posVal = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
        }
        // Set position a second time in case resizing across screen boundaries clamped origin first
        if let posVal = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }

        if raise {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
    }

    private func findAXWindow(for window: MonitoredWindow) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(window.ownerPID)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        guard err == .success, let axWindows = value as? [AXUIElement], !axWindows.isEmpty else {
            return nil
        }

        // 1. Try matching by exact title if non-empty
        if !window.windowTitle.isEmpty {
            for axWin in axWindows {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String,
                   title == window.windowTitle {
                    return axWin
                }
            }
        }

        // 2. Try matching by closest position & size
        var bestMatch: AXUIElement?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for axWin in axWindows {
            if let rect = getAXWindowRect(axWin) {
                let dist = hypot(rect.origin.x - window.bounds.origin.x, rect.origin.y - window.bounds.origin.y) +
                           hypot(rect.size.width - window.bounds.size.width, rect.size.height - window.bounds.size.height)
                if dist < bestDistance {
                    bestDistance = dist
                    bestMatch = axWin
                }
            }
        }
        if let bestMatch { return bestMatch }

        // 3. Fallback to windowIndexInApp
        if window.windowIndexInApp < axWindows.count {
            return axWindows[window.windowIndexInApp]
        }
        return axWindows.first
    }

    private func getAXWindowRect(_ axWin: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef,
              let sizeVal = sizeRef else {
            return nil
        }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pt)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }
}
