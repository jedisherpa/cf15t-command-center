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
/// Parses raw USB HID Report 0x91 (10-finger multi-touch) and Report 0x03 (single-touch),
/// dispatches synthetic NSEvent clicks directly into the CF15T Command Center window on the CF15T,
/// and snaps the system cursor back to the primary MacBook screen after each touch.
final class SiSTouchHardwareDriver {
    static let shared = SiSTouchHardwareDriver()

    static let sisVendorID: Int = 1111   // 0x0457 Silicon Integrated System Co.
    static let sisProductID: Int = 2073  // 0x0819 SiS HID Touch Controller

    var isRemapToCF15TEnabled: Bool = true
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
        notifyObserver()
    }

    // MARK: - Raw HID Packet Decoder (Report 0x91 Multi-Touch & Report 0x03 Mouse)

    private func handleRawReport(reportID: UInt32, ptr: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length > 0 else { return }
        let bytes = UnsafeBufferPointer(start: ptr, count: length)

        if reportID == 0x91 && length >= 51 {
            // Report 0x91 (145): 54-byte 5-finger packet
            // Byte 0 is 0x91; each of the 5 fingers is 10 bytes starting at offset 1 + i*10
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

        if let first = contacts.first {
            primaryTouchPoint = CGPoint(x: first.normalizedX, y: first.normalizedY)
        }

        if touchingNow && !wasPrimaryTouching {
            // Finger just touched down on CF15T!
            wasPrimaryTouching = true
            lastDispatchedDownPoint = primaryTouchPoint
            if isRemapToCF15TEnabled {
                dispatchTouchToCommandCenterWindow(phase: .began, normalizedPt: primaryTouchPoint)
            }
        } else if touchingNow && wasPrimaryTouching {
            // Finger dragging on CF15T
            if isRemapToCF15TEnabled {
                dispatchTouchToCommandCenterWindow(phase: .moved, normalizedPt: primaryTouchPoint)
            }
        } else if !touchingNow && wasPrimaryTouching {
            // Finger lifted off CF15T!
            wasPrimaryTouching = false
            if isRemapToCF15TEnabled {
                dispatchTouchToCommandCenterWindow(phase: .ended, normalizedPt: lastDispatchedDownPoint)
            }
            if CursorSnapbackEngine.shared.isSnapbackEnabled {
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

    /// Directly converts the CF15T normalized (0..1, 0..1) touch coordinate into the
    /// CF15T display & Command Center window coordinate space and sends a real AppKit mouse event.
    private func dispatchTouchToCommandCenterWindow(phase: TouchPhaseType, normalizedPt: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 1. Warp cursor to the CF15T screen coordinate so visual cursor matches touch
            var displayCount: UInt32 = 0
            CGGetOnlineDisplayList(0, nil, &displayCount)
            var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
            CGGetOnlineDisplayList(displayCount, &displays, &displayCount)

            if let cf15tDisplay = displays.first(where: { CGDisplayIsBuiltin($0) == 0 }) {
                let bounds = CGDisplayBounds(cf15tDisplay)
                let targetX = bounds.minX + normalizedPt.x * bounds.width
                let targetY = bounds.minY + normalizedPt.y * bounds.height
                CGWarpMouseCursorPosition(CGPoint(x: targetX, y: targetY))
                CGAssociateMouseAndMouseCursorPosition(1)
            }

            // 2. Synthesize NSEvent directly into the CF15T Command Center NSWindow
            guard let window = self.targetCommandCenterWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                  let screen = window.screen else {
                return
            }

            // Map normalized screen touch (top-left origin) to AppKit screen point (bottom-left origin)
            let screenFrame = screen.frame
            let screenPoint = NSPoint(
                x: screenFrame.minX + normalizedPt.x * screenFrame.width,
                y: screenFrame.maxY - normalizedPt.y * screenFrame.height
            )

            // Convert screen point into window coordinates
            let windowPoint = NSPoint(
                x: screenPoint.x - window.frame.minX,
                y: screenPoint.y - window.frame.minY
            )

            guard windowPoint.x >= 0, windowPoint.x <= window.frame.width,
                  windowPoint.y >= 0, windowPoint.y <= window.frame.height else {
                return
            }

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
