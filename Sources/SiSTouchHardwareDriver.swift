import Cocoa
import IOKit.hid
import ApplicationServices

struct SiSTouchContact: Identifiable, Equatable {
    let id: Int
    let normalizedX: CGFloat // 0.0 .. 1.0
    let normalizedY: CGFloat // 0.0 .. 1.0
}

/// Directly interfaces with the Caperave CF15T's onboard Silicon Integrated Systems (SiS)
/// 10-point capacitive USB touch controller (VID: 0x0457 / 1111, PID: 0x0819 / 2073).
/// Supports two operating modes:
/// - ORCHESTRATE Mode: Routes CF15T touches to the Command Center HUD and snaps the cursor back to the MacBook display.
/// - FULL CONTROL Mode (Laptop Closed / Travel): Routes 1-finger touches to both the Command Center Dock AND any macOS app window
///   on the CF15T via system-wide CGEvent injection, plus 2-finger touch scrolling across any app.
final class SiSTouchHardwareDriver {
    static let shared = SiSTouchHardwareDriver()

    static let sisVendorID: Int = 1111   // 0x0457 Silicon Integrated System Co.
    static let sisProductID: Int = 2073  // 0x0819 SiS HID Touch Controller

    var isRemapToCF15TEnabled: Bool = true
    var isFullControlSystemTouchMode: Bool = false
    weak var targetCommandCenterWindow: NSWindow?

    var onTouchStateChanged: ((Bool, Bool, CGPoint, [SiSTouchContact]) -> Void)?

    private var hidManager: IOHIDManager?
    private var reportBuffers: [Int: UnsafeMutablePointer<UInt8>] = [:]
    private let reportBufferSize = 1024

    private(set) var isHardwareConnected: Bool = false
    private(set) var isTouching: Bool = false
    private(set) var primaryTouchPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private(set) var activeContacts: [SiSTouchContact] = []

    private var wasPrimaryTouching: Bool = false
    private var lastDispatchedDownPoint: CGPoint = .zero
    private var lastTwoFingerMidpoint: CGPoint? = nil

    private init() {}

    func start() {
        guard hidManager == nil else { return }

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.sisVendorID,
            kIOHIDProductIDKey as String: Self.sisProductID
        ]
        IOHIDManagerSetDeviceMatching(mgr, matchDict as CFDictionary)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, device in
            guard let ctx = ctx else { return }
            let driver = Unmanaged<SiSTouchHardwareDriver>.fromOpaque(ctx).takeUnretainedValue()
            driver.registerDeviceReportCallback(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, _ in
            guard let ctx = ctx else { return }
            let driver = Unmanaged<SiSTouchHardwareDriver>.fromOpaque(ctx).takeUnretainedValue()
            driver.handleDeviceRemoved()
        }, context)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

        if openResult == kIOReturnSuccess,
           let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
           !devs.isEmpty {
            for dev in devs {
                registerDeviceReportCallback(dev)
            }
            isHardwareConnected = true
        } else {
            isHardwareConnected = false
        }

        self.hidManager = mgr
        notifyObserver()
    }

    private func registerDeviceReportCallback(_ device: IOHIDDevice) {
        let devHash = CFHash(device)
        let buf: UnsafeMutablePointer<UInt8>
        if let existing = reportBuffers[Int(devHash)] {
            buf = existing
        } else {
            buf = UnsafeMutablePointer<UInt8>.allocate(capacity: reportBufferSize)
            buf.initialize(repeating: 0, count: reportBufferSize)
            reportBuffers[Int(devHash)] = buf
        }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buf,
            reportBufferSize,
            { ctx, _, _, _, reportID, reportPtr, reportLength in
                guard let ctx = ctx else { return }
                let driver = Unmanaged<SiSTouchHardwareDriver>.fromOpaque(ctx).takeUnretainedValue()
                driver.handleRawReport(reportID: reportID, ptr: reportPtr, length: reportLength)
            },
            context
        )

        isHardwareConnected = true
        notifyObserver()
    }

    private func handleDeviceRemoved() {
        isHardwareConnected = false
        isTouching = false
        activeContacts = []
        lastTwoFingerMidpoint = nil
        notifyObserver()
    }

    // MARK: - Raw HID Packet Decoder (Report 0x91 Multi-Touch & Report 0x03 Mouse)

    private func handleRawReport(reportID: UInt32, ptr: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length > 0 else { return }
        let bytes = UnsafeBufferPointer(start: ptr, count: length)

        if reportID == 0x91 && length >= 51 {
            // Report 0x91 (145): 54-byte 5-finger packet
            var contacts: [SiSTouchContact] = []
            for i in 0..<5 {
                let base = 1 + (i * 10)
                guard base + 5 < length else { break }
                let statusByte = bytes[base]
                let tipSwitch = (statusByte & 0x01) != 0
                let contactID = Int(bytes[base + 1])
                let rawX = UInt16(bytes[base + 2]) | (UInt16(bytes[base + 3]) << 8)
                let rawY = UInt16(bytes[base + 4]) | (UInt16(bytes[base + 5]) << 8)

                if tipSwitch && rawX <= 4095 && rawY <= 4095 {
                    let nx = CGFloat(rawX) / 4095.0
                    let ny = CGFloat(rawY) / 4095.0
                    contacts.append(SiSTouchContact(id: contactID, normalizedX: nx, normalizedY: ny))
                }
            }
            processDecodedContacts(contacts)

        } else if reportID == 0x03 && length >= 6 {
            // Report 0x03: 6-byte Single-Touch Mouse Emulation packet
            let buttonDown = (bytes[1] & 0x01) != 0
            let rawX = UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
            let rawY = UInt16(bytes[4]) | (UInt16(bytes[5]) << 8)
            if buttonDown && rawX <= 4095 && rawY <= 4095 {
                let nx = CGFloat(rawX) / 4095.0
                let ny = CGFloat(rawY) / 4095.0
                processDecodedContacts([SiSTouchContact(id: 0, normalizedX: nx, normalizedY: ny)])
            } else {
                processDecodedContacts([])
            }
        }
    }

    private func processDecodedContacts(_ contacts: [SiSTouchContact]) {
        activeContacts = contacts
        let touchingNow = !contacts.isEmpty
        isTouching = touchingNow

        // Two-finger scroll support on the CF15T touchscreen!
        if contacts.count >= 2 {
            let c0 = contacts[0]
            let c1 = contacts[1]
            let mid = CGPoint(x: (c0.normalizedX + c1.normalizedX) * 0.5, y: (c0.normalizedY + c1.normalizedY) * 0.5)
            if let prevMid = lastTwoFingerMidpoint {
                let dxPixels = Int32((mid.x - prevMid.x) * 1920.0 * 1.4)
                let dyPixels = Int32((mid.y - prevMid.y) * 1080.0 * 1.4)
                if abs(dyPixels) >= 2 || abs(dxPixels) >= 2 {
                    dispatchTwoFingerScroll(dxPixels: dxPixels, dyPixels: dyPixels, atNormalized: mid)
                }
            }
            lastTwoFingerMidpoint = mid
            notifyObserver()
            return
        } else {
            lastTwoFingerMidpoint = nil
        }

        if let first = contacts.first {
            primaryTouchPoint = CGPoint(x: first.normalizedX, y: first.normalizedY)
        }

        if touchingNow && !wasPrimaryTouching {
            wasPrimaryTouching = true
            lastDispatchedDownPoint = primaryTouchPoint
            if isRemapToCF15TEnabled || isFullControlSystemTouchMode {
                dispatchTouchToCF15T(phase: .began, normalizedPt: primaryTouchPoint)
            }
        } else if touchingNow && wasPrimaryTouching {
            if isRemapToCF15TEnabled || isFullControlSystemTouchMode {
                dispatchTouchToCF15T(phase: .moved, normalizedPt: primaryTouchPoint)
            }
        } else if !touchingNow && wasPrimaryTouching {
            wasPrimaryTouching = false
            if isRemapToCF15TEnabled || isFullControlSystemTouchMode {
                dispatchTouchToCF15T(phase: .ended, normalizedPt: lastDispatchedDownPoint)
            }
            if !isFullControlSystemTouchMode && CursorSnapbackEngine.shared.isSnapbackEnabled {
                CursorSnapbackEngine.shared.warpBackToSavedMainScreenPositionNow()
            }
        }

        notifyObserver()
    }

    private enum TouchPhaseType {
        case began
        case moved
        case ended
    }

    /// Resolves the Quartz display bounds of the CF15T monitor (works both when MacBook lid is open with 2 displays
    /// and when MacBook lid is closed in Full Control clamshell mode where CF15T is the sole active display).
    private func resolveCF15TDisplayQuartzBounds() -> CGRect {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        if displayCount > 0 {
            var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
            CGGetOnlineDisplayList(displayCount, &displays, &displayCount)
            if let externalDisplay = displays.first(where: { CGDisplayIsBuiltin($0) == 0 }) {
                return CGDisplayBounds(externalDisplay)
            }
            if let firstDisplay = displays.first {
                return CGDisplayBounds(firstDisplay)
            }
        }
        return CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    private func dispatchTwoFingerScroll(dxPixels: Int32, dyPixels: Int32, atNormalized normalizedPt: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let bounds = self.resolveCF15TDisplayQuartzBounds()
            let targetX = bounds.minX + normalizedPt.x * bounds.width
            let targetY = bounds.minY + normalizedPt.y * bounds.height
            CGWarpMouseCursorPosition(CGPoint(x: targetX, y: targetY))
            CGAssociateMouseAndMouseCursorPosition(1)

            if let scrollEv = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: dyPixels,
                wheel2: dxPixels,
                wheel3: 0
            ) {
                scrollEv.post(tap: .cghidEventTap)
            }
        }
    }

    /// Converts the CF15T normalized (0..1, 0..1) touch coordinate into the CF15T display space.
    /// - If the touch lands inside our Command Center / Touch Dock window, sends an AppKit NSEvent directly to it.
    /// - If in FULL CONTROL mode and the touch lands on an external app window (Signal, ChatGPT, Grok Bot, etc.),
    ///   synthesizes a system-wide CGEvent click/drag on the CF15T display.
    private func dispatchTouchToCF15T(phase: TouchPhaseType, normalizedPt: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let bounds = self.resolveCF15TDisplayQuartzBounds()
            let targetQuartzPt = CGPoint(
                x: bounds.minX + normalizedPt.x * bounds.width,
                y: bounds.minY + normalizedPt.y * bounds.height
            )
            CGWarpMouseCursorPosition(targetQuartzPt)
            CGAssociateMouseAndMouseCursorPosition(1)

            // Check if the touch is inside our visible Command Center / Touch Dock NSWindow
            if let window = self.targetCommandCenterWindow ?? NSApp.windows.first(where: { $0.isVisible }),
               let screen = window.screen {
                let screenFrame = screen.frame
                let screenPoint = NSPoint(
                    x: screenFrame.minX + normalizedPt.x * screenFrame.width,
                    y: screenFrame.maxY - normalizedPt.y * screenFrame.height
                )

                let windowPoint = NSPoint(
                    x: screenPoint.x - window.frame.minX,
                    y: screenPoint.y - window.frame.minY
                )

                if windowPoint.x >= 0, windowPoint.x <= window.frame.width,
                   windowPoint.y >= 0, windowPoint.y <= window.frame.height {
                    let eventType: NSEvent.EventType
                    switch phase {
                    case .began:
                        if !window.isKeyWindow {
                            window.makeKeyAndOrderFront(nil)
                        }
                        eventType = .leftMouseDown
                    case .moved:
                        eventType = .leftMouseDragged
                    case .ended:
                        eventType = .leftMouseUp
                    }

                    if let syntheticEvent = NSEvent.mouseEvent(
                        with: eventType,
                        location: windowPoint,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 1,
                        pressure: phase == .ended ? 0.0 : 1.0
                    ) {
                        window.sendEvent(syntheticEvent)
                    }
                    return
                }
            }

            // If touch is outside the Command Center window (e.g. inside Signal, ChatGPT, Grok Bot, Chrome on CF15T):
            // In FULL CONTROL mode, post a system-wide mouse click/drag at targetQuartzPt on the CF15T!
            if self.isFullControlSystemTouchMode {
                let cgType: CGEventType
                switch phase {
                case .began: cgType = .leftMouseDown
                case .moved: cgType = .leftMouseDragged
                case .ended: cgType = .leftMouseUp
                }
                if let mouseEv = CGEvent(
                    mouseEventSource: nil,
                    mouseType: cgType,
                    mouseCursorPosition: targetQuartzPt,
                    mouseButton: .left
                ) {
                    mouseEv.post(tap: .cghidEventTap)
                }
            }
        }
    }

    private func notifyObserver() {
        let connected = isHardwareConnected
        let touching = isTouching
        let pt = primaryTouchPoint
        let contacts = activeContacts
        DispatchQueue.main.async { [weak self] in
            self?.onTouchStateChanged?(connected, touching, pt, contacts)
        }
    }
}
