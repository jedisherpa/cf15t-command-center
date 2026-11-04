import Cocoa
import IOKit.hid
import ApplicationServices

struct SiSTouchContact: Identifiable, Equatable {
    let id: Int
    let normalizedX: CGFloat // 0.0 .. 1.0
    let normalizedY: CGFloat // 0.0 .. 1.0
}

/// Touch input for the Command Center screens.
///
/// - The Caperave CF15T (15.6") uses a Silicon Integrated Systems (SiS) 10-point USB controller
///   (VID 0x0457 / PID 0x0819). Its raw packets are decoded directly.
/// - Any other standard USB touchscreen (HID Digitizer · Touch Screen), such as the 12.3" wide bar screen,
///   is read through the generic HID element values (X, Y, tip switch).
///
/// Each touch device is mapped to its own screen, so touches land in the right place when both screens are plugged in.
/// - ORCHESTRATE mode: touches drive the Command Center window, then the cursor snaps back to the laptop screen.
/// - FULL CONTROL mode (lid closed / travel): touches also click and drag any app window on that screen,
///   plus 2-finger scrolling.
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

    /// Per-device gesture state, so two touchscreens never confuse each other.
    private final class TouchStream {
        var wasPrimaryTouching: Bool = false
        var lastDispatchedDownPoint: CGPoint = .zero
        var isCurrentTouchDragging: Bool = false
        var lastTwoFingerMidpoint: CGPoint? = nil
        var currentEventNumber: Int = 100
        let resolveScreen: () -> NSScreen?

        init(resolveScreen: @escaping () -> NSScreen?) {
            self.resolveScreen = resolveScreen
        }
    }

    /// Generic HID digitizer: finger slots keyed by their parent collection.
    private struct FingerSlot {
        var tip: Bool = false
        var x: CGFloat = -1
        var y: CGFloat = -1
    }

    private final class GenericDigitizerState {
        var slots: [Int: FingerSlot] = [:]
        var flushScheduled: Bool = false
        let stream: TouchStream

        init(stream: TouchStream) {
            self.stream = stream
        }
    }

    private let sisStream = TouchStream(resolveScreen: { DisplayTargetManager.shared.cf15tScreen() })
    private var genericDevices: [Int: GenericDigitizerState] = [:]
    private var connectedDeviceKeys: Set<Int> = []
    private var connectedLogicalIDs: Set<String> = []
    private var hasReceivedMultiTouch0x91: Bool = false

    private init() {}

    // MARK: - Start

    func start() {
        guard hidManager == nil else { return }

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Match any standard touchscreen (Digitizer page 0x0D, usage 0x04 = Touch Screen), including SiS 0x0457:0x0819.
        // Using a single matching dictionary avoids IOHIDManager creating duplicate IOHIDDevice instances for SiS,
        // while still excluding trackpads (usage 0x05) and mice.
        let touchScreenMatch: [String: Any] = [
            kIOHIDPrimaryUsagePageKey as String: 0x0D,
            kIOHIDPrimaryUsageKey as String: 0x04
        ]
        IOHIDManagerSetDeviceMatching(mgr, touchScreenMatch as CFDictionary)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, device in
            guard let ctx = ctx else { return }
            let driver = Unmanaged<SiSTouchHardwareDriver>.fromOpaque(ctx).takeUnretainedValue()
            driver.attachDevice(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, device in
            guard let ctx = ctx else { return }
            let driver = Unmanaged<SiSTouchHardwareDriver>.fromOpaque(ctx).takeUnretainedValue()
            driver.handleDeviceRemoved(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))

        if openResult == kIOReturnSuccess,
           let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> {
            for dev in devs {
                attachDevice(dev)
            }
        }

        self.hidManager = mgr
        notifyObserver()
    }

    // MARK: - Device attach / detach

    private func deviceKey(_ device: IOHIDDevice) -> Int {
        Int(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? -1
    }

    private func deviceLogicalID(_ device: IOHIDDevice) -> String {
        let vid = intProperty(device, kIOHIDVendorIDKey)
        let pid = intProperty(device, kIOHIDProductIDKey)
        let loc = intProperty(device, kIOHIDLocationIDKey)
        return "\(vid):\(pid):\(loc)"
    }

    private func attachDevice(_ device: IOHIDDevice) {
        let key = deviceKey(device)
        let logicalID = deviceLogicalID(device)
        guard !connectedDeviceKeys.contains(key), !connectedLogicalIDs.contains(logicalID) else { return }
        connectedDeviceKeys.insert(key)
        connectedLogicalIDs.insert(logicalID)

        // Seize the USB touchscreen so macOS WindowServer does NOT treat finger touches as mouse cursor movements.
        // This lets the user's physical mouse, trackpad, and trackball keep independent control of the cursor.
        _ = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))

        let vid = intProperty(device, kIOHIDVendorIDKey)
        let pid = intProperty(device, kIOHIDProductIDKey)
        if vid == Self.sisVendorID && pid == Self.sisProductID {
            registerSiSReportCallback(device, key: key)
        } else {
            registerGenericValueCallback(device, key: key)
        }

        isHardwareConnected = true
        notifyObserver()
    }

    private func registerSiSReportCallback(_ device: IOHIDDevice, key: Int) {
        let buf: UnsafeMutablePointer<UInt8>
        if let existing = reportBuffers[key] {
            buf = existing
        } else {
            buf = UnsafeMutablePointer<UInt8>.allocate(capacity: reportBufferSize)
            buf.initialize(repeating: 0, count: reportBufferSize)
            reportBuffers[key] = buf
        }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buf,
            reportBufferSize,
            { ctx, _, _, _, reportID, reportPtr, reportLength in
                guard let ctx = ctx else { return }
                let driver = Unmanaged<SiSTouchHardwareDriver>.fromOpaque(ctx).takeUnretainedValue()
                driver.handleSiSRawReport(reportID: reportID, ptr: reportPtr, length: reportLength)
            },
            context
        )
    }

    private func registerGenericValueCallback(_ device: IOHIDDevice, key: Int) {
        let stream = TouchStream(resolveScreen: { DisplayTargetManager.shared.secondaryTouchScreen() })
        genericDevices[key] = GenericDigitizerState(stream: stream)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceRegisterInputValueCallback(device, { ctx, _, _, value in
            guard let ctx = ctx else { return }
            let driver = Unmanaged<SiSTouchHardwareDriver>.fromOpaque(ctx).takeUnretainedValue()
            driver.handleGenericValue(value)
        }, context)
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        let key = deviceKey(device)
        let logicalID = deviceLogicalID(device)
        connectedDeviceKeys.remove(key)
        connectedLogicalIDs.remove(logicalID)
        genericDevices.removeValue(forKey: key)
        if let buf = reportBuffers.removeValue(forKey: key) {
            buf.deallocate()
        }
        isHardwareConnected = !connectedDeviceKeys.isEmpty
        isTouching = false
        activeContacts = []
        notifyObserver()
    }

    // MARK: - SiS Raw HID Packet Decoder (Report 0x91 Multi-Touch & Report 0x03 Mouse)

    private func handleSiSRawReport(reportID: UInt32, ptr: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length > 0 else { return }
        let bytes = UnsafeBufferPointer(start: ptr, count: length)

        if reportID == 0x91 && length >= 51 {
            hasReceivedMultiTouch0x91 = true
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
            processDecodedContacts(contacts, stream: sisStream)

        } else if reportID == 0x03 && length >= 6 && !hasReceivedMultiTouch0x91 {
            // Report 0x03: 6-byte Single-Touch Mouse Emulation fallback (only used if 0x91 isn't active)
            let buttonDown = (bytes[1] & 0x01) != 0
            let rawX = UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
            let rawY = UInt16(bytes[4]) | (UInt16(bytes[5]) << 8)
            if buttonDown && rawX <= 4095 && rawY <= 4095 {
                let nx = CGFloat(rawX) / 4095.0
                let ny = CGFloat(rawY) / 4095.0
                processDecodedContacts([SiSTouchContact(id: 0, normalizedX: nx, normalizedY: ny)], stream: sisStream)
            } else {
                processDecodedContacts([], stream: sisStream)
            }
        }
    }

    // MARK: - Generic HID Digitizer Decoder (any standard touchscreen)

    private func handleGenericValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let state = genericDevices[deviceKey(device)] else { return }

        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        let slotKey: Int
        if let parent = IOHIDElementGetParent(element) {
            slotKey = Int(IOHIDElementGetCookie(parent))
        } else {
            slotKey = 0
        }

        var slot = state.slots[slotKey] ?? FingerSlot()

        switch (page, usage) {
        case (0x0D, 0x42): // Tip Switch (finger touching)
            slot.tip = intValue != 0
        case (0x0D, 0x33): // Touch (some panels use this instead of Tip Switch)
            slot.tip = intValue != 0
        case (0x01, 0x30): // X
            slot.x = normalized(intValue, element: element)
        case (0x01, 0x31): // Y
            slot.y = normalized(intValue, element: element)
        case (0x0D, 0x54): // Contact Count
            if intValue == 0 {
                state.slots.removeAll()
                scheduleGenericFlush(state)
            }
            return
        default:
            return
        }

        state.slots[slotKey] = slot
        scheduleGenericFlush(state)
    }

    private func normalized(_ raw: CFIndex, element: IOHIDElement) -> CGFloat {
        let minV = IOHIDElementGetLogicalMin(element)
        let maxV = IOHIDElementGetLogicalMax(element)
        guard maxV > minV else { return -1 }
        let n = CGFloat(raw - minV) / CGFloat(maxV - minV)
        return min(1.0, max(0.0, n))
    }

    /// All values of one HID report arrive in the same run-loop pass, so flush once afterwards.
    private func scheduleGenericFlush(_ state: GenericDigitizerState) {
        guard !state.flushScheduled else { return }
        state.flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            state.flushScheduled = false
            let contacts: [SiSTouchContact] = state.slots
                .sorted(by: { $0.key < $1.key })
                .compactMap { entry in
                    let s = entry.value
                    guard s.tip, s.x >= 0, s.y >= 0 else { return nil }
                    return SiSTouchContact(id: entry.key, normalizedX: s.x, normalizedY: s.y)
                }
            self.processDecodedContacts(contacts, stream: state.stream)
        }
    }

    // MARK: - Gesture handling (shared by every touchscreen)

    private func processDecodedContacts(_ contacts: [SiSTouchContact], stream: TouchStream) {
        activeContacts = contacts
        let touchingNow = !contacts.isEmpty
        isTouching = touchingNow

        // Two-finger scroll
        if contacts.count >= 2 {
            let c0 = contacts[0]
            let c1 = contacts[1]
            let mid = CGPoint(x: (c0.normalizedX + c1.normalizedX) * 0.5, y: (c0.normalizedY + c1.normalizedY) * 0.5)
            if let prevMid = stream.lastTwoFingerMidpoint {
                let delta = CGPoint(x: mid.x - prevMid.x, y: mid.y - prevMid.y)
                dispatchTwoFingerScroll(normalizedDelta: delta, atNormalized: mid, stream: stream)
            }
            stream.lastTwoFingerMidpoint = mid
            notifyObserver()
            return
        } else {
            stream.lastTwoFingerMidpoint = nil
        }

        if let first = contacts.first {
            primaryTouchPoint = CGPoint(x: first.normalizedX, y: first.normalizedY)
        }

        let shouldDispatch = isRemapToCF15TEnabled || isFullControlSystemTouchMode

        if touchingNow && !stream.wasPrimaryTouching {
            stream.wasPrimaryTouching = true
            stream.isCurrentTouchDragging = false
            stream.lastDispatchedDownPoint = primaryTouchPoint
            if shouldDispatch {
                dispatchTouch(phase: .began, normalizedPt: primaryTouchPoint, stream: stream)
            }
        } else if touchingNow && stream.wasPrimaryTouching {
            let moveDist = hypot(
                primaryTouchPoint.x - stream.lastDispatchedDownPoint.x,
                primaryTouchPoint.y - stream.lastDispatchedDownPoint.y
            )
            // Ignore micro-jitter (< 1.4% of screen) during a tap so SwiftUI Buttons don't cancel the click
            if stream.isCurrentTouchDragging || moveDist >= 0.014 {
                stream.isCurrentTouchDragging = true
                if shouldDispatch {
                    dispatchTouch(phase: .moved, normalizedPt: primaryTouchPoint, stream: stream)
                }
            }
        } else if !touchingNow && stream.wasPrimaryTouching {
            stream.wasPrimaryTouching = false
            let releasePoint = stream.isCurrentTouchDragging ? primaryTouchPoint : stream.lastDispatchedDownPoint
            stream.isCurrentTouchDragging = false
            if shouldDispatch {
                dispatchTouch(phase: .ended, normalizedPt: releasePoint, stream: stream)
            }
        }

        notifyObserver()
    }

    private enum TouchPhaseType {
        case began
        case moved
        case ended
    }

    private func dispatchTwoFingerScroll(normalizedDelta: CGPoint, atNormalized normalizedPt: CGPoint, stream: TouchStream) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let screen = stream.resolveScreen() else { return }
            let screenFrame = screen.frame
            let dxPixels = Int32(normalizedDelta.x * screenFrame.width * 1.4)
            let dyPixels = Int32(normalizedDelta.y * screenFrame.height * 1.4)
            guard abs(dyPixels) >= 2 || abs(dxPixels) >= 2 else { return }

            let screenPoint = NSPoint(
                x: screenFrame.minX + normalizedPt.x * screenFrame.width,
                y: screenFrame.maxY - normalizedPt.y * screenFrame.height
            )

            // Deliver scroll directly into the Command Center window without moving the mouse cursor
            if let window = self.targetCommandCenterWindow ?? NSApp.windows.first(where: { $0.isVisible }),
               window.isVisible,
               window.frame.contains(screenPoint),
               let cgScroll = CGEvent(
                   scrollWheelEvent2Source: nil,
                   units: .pixel,
                   wheelCount: 2,
                   wheel1: dyPixels,
                   wheel2: dxPixels,
                   wheel3: 0
               ),
               let nsScroll = NSEvent(cgEvent: cgScroll) {
                window.sendEvent(nsScroll)
            }
        }
    }

    /// Converts a normalized (0..1, 0..1) touch on a given touchscreen into that screen's space.
    /// - If the touch lands inside the Command Center window, sends a direct AppKit NSEvent to it
    ///   WITHOUT moving or hijacking the macOS mouse cursor.
    /// - Only if touching an external app window outside the Command Center in FULL CONTROL dock mode
    ///   does it post a system-wide CGEvent.
    private func dispatchTouch(phase: TouchPhaseType, normalizedPt: CGPoint, stream: TouchStream) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let screen = stream.resolveScreen() else { return }

            let screenFrame = screen.frame
            let screenPoint = NSPoint(
                x: screenFrame.minX + normalizedPt.x * screenFrame.width,
                y: screenFrame.maxY - normalizedPt.y * screenFrame.height
            )

            if let window = self.targetCommandCenterWindow ?? NSApp.windows.first(where: { $0.isVisible }),
               window.isVisible,
               window.frame.contains(screenPoint) {
                // Instrument-panel button actuation: fire immediately on touch-down (.began) at the exact contact point
                // so finger roll or lift never delays or cancels a SwiftUI button press.
                guard phase == .began else { return }

                if !window.isKeyWindow {
                    window.makeKey()
                }

                let windowPoint = NSPoint(
                    x: screenPoint.x - window.frame.minX,
                    y: screenPoint.y - window.frame.minY
                )
                stream.currentEventNumber += 1
                let evNum = stream.currentEventNumber
                let winNum = window.windowNumber
                let now = ProcessInfo.processInfo.systemUptime

                if let downEvent = NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: windowPoint,
                    modifierFlags: [],
                    timestamp: now,
                    windowNumber: winNum,
                    context: nil,
                    eventNumber: evNum,
                    clickCount: 1,
                    pressure: 1.0
                ) {
                    window.sendEvent(downEvent)
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.018) { [weak window] in
                    guard let window = window else { return }
                    if let upEvent = NSEvent.mouseEvent(
                        with: .leftMouseUp,
                        location: windowPoint,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: winNum,
                        context: nil,
                        eventNumber: evNum,
                        clickCount: 1,
                        pressure: 0.0
                    ) {
                        window.sendEvent(upEvent)
                    }
                }
                return
            }

            // Outside the Command Center (e.g. docked mode where an app sits below the top bar):
            if self.isFullControlSystemTouchMode {
                let bounds = DisplayTargetManager.shared.quartzBounds(of: screen)
                let targetQuartzPt = CGPoint(
                    x: bounds.minX + normalizedPt.x * bounds.width,
                    y: bounds.minY + normalizedPt.y * bounds.height
                )
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
