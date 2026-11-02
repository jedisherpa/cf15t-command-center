import Cocoa
import IOKit.hid
import ApplicationServices

/// Directly interfaces with the Caperave CF15T's onboard Silicon Integrated Systems (SiS)
/// 10-point capacitive USB touch controller (VID: 0x0457 / 1111, PID: 0x0819 / 2073).
/// Maps raw 0..4095 touch coordinates directly to the CF15T display in Extended Desktop mode.
final class SiSTouchHardwareDriver {
    static let shared = SiSTouchHardwareDriver()

    static let sisVendorID: Int = 1111   // 0x0457 Silicon Integrated System Co.
    static let sisProductID: Int = 2073  // 0x0819 SiS HID Touch Controller

    var isRemapToCF15TEnabled: Bool = true
    var onTouchStateChanged: ((Bool, Bool, CGPoint, Int) -> Void)? // (connected, touching, normalizedPt, contactCount)

    private var hidManager: IOHIDManager?
    private(set) var isHardwareConnected: Bool = false
    private(set) var isTouching: Bool = false
    private(set) var normalizedTouchPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private(set) var activeContactCount: Int = 0

    private var currentRawX: Int = 2048
    private var currentRawY: Int = 2048
    private var wasTouching: Bool = false
    private var savedPreTouchMainCursor: CGPoint = CGPoint(x: 600, y: 450)

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

        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, _ in
            guard let ctx = ctx else { return }
            let driver = Unmanaged<SiSTouchHardwareDriver>.fromOpaque(ctx).takeUnretainedValue()
            driver.handleDeviceMatched()
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, _ in
            guard let ctx = ctx else { return }
            let driver = Unmanaged<SiSTouchHardwareDriver>.fromOpaque(ctx).takeUnretainedValue()
            driver.handleDeviceRemoved()
        }, context)

        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            guard let ctx = ctx else { return }
            let driver = Unmanaged<SiSTouchHardwareDriver>.fromOpaque(ctx).takeUnretainedValue()
            driver.handleHIDInputValue(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

        if let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>, !devs.isEmpty {
            isHardwareConnected = (openResult == kIOReturnSuccess)
        } else {
            isHardwareConnected = false
        }

        self.hidManager = mgr
        notifyObserver()
    }

    private func handleDeviceMatched() {
        isHardwareConnected = true
        notifyObserver()
    }

    private func handleDeviceRemoved() {
        isHardwareConnected = false
        isTouching = false
        activeContactCount = 0
        notifyObserver()
    }

    private func handleHIDInputValue(_ value: IOHIDValue) {
        let elem = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(elem)
        let usage = IOHIDElementGetUsage(elem)
        let intVal = IOHIDValueGetIntegerValue(value)

        var stateUpdated = false

        // Generic Desktop X (0x01, 0x30) & Y (0x01, 0x31) -> Logical 0..4095
        if usagePage == 0x01 && usage == 0x30 {
            if intVal >= 0 && intVal <= 4095 {
                currentRawX = intVal
                normalizedTouchPoint.x = CGFloat(intVal) / 4095.0
                stateUpdated = true
            }
        } else if usagePage == 0x01 && usage == 0x31 {
            if intVal >= 0 && intVal <= 4095 {
                currentRawY = intVal
                normalizedTouchPoint.y = CGFloat(intVal) / 4095.0
                stateUpdated = true
            }
        } else if (usagePage == 0x0D && usage == 0x42) || (usagePage == 0x09 && usage == 0x01) {
            // Digitizer Tip Switch (0x0D, 0x42) or Button 1 (0x09, 0x01)
            let touchingNow = (intVal != 0)
            if touchingNow != isTouching {
                isTouching = touchingNow
                stateUpdated = true
                handleTouchTransition(touchingNow: touchingNow)
            }
        } else if usagePage == 0x0D && usage == 0x54 {
            // Contact Count (0..10)
            if intVal >= 0 && intVal <= 10 {
                activeContactCount = intVal
                stateUpdated = true
            }
        }

        if stateUpdated {
            if isTouching && isRemapToCF15TEnabled {
                warpCursorToCF15TIfExtended()
            }
            notifyObserver()
        }
    }

    private func handleTouchTransition(touchingNow: Bool) {
        if touchingNow && !wasTouching {
            wasTouching = true
            if activeContactCount == 0 { activeContactCount = 1 }
            savedPreTouchMainCursor = CursorSnapbackEngine.shared.lastMainScreenPoint
            if isRemapToCF15TEnabled {
                warpCursorToCF15TIfExtended()
            }
        } else if !touchingNow && wasTouching {
            wasTouching = false
            activeContactCount = 0
            if CursorSnapbackEngine.shared.isSnapbackEnabled {
                CursorSnapbackEngine.shared.warpBackToSavedMainScreenPositionNow()
            }
        }
    }

    private func warpCursorToCF15TIfExtended() {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        guard displayCount > 1 else { return }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displays, &displayCount)

        // Find external CF15T display (non-builtin)
        guard let cf15tDisplay = displays.first(where: { CGDisplayIsBuiltin($0) == 0 }) else {
            return
        }
        let bounds = CGDisplayBounds(cf15tDisplay)
        let targetX = bounds.minX + normalizedTouchPoint.x * bounds.width
        let targetY = bounds.minY + normalizedTouchPoint.y * bounds.height
        let targetPt = CGPoint(x: targetX, y: targetY)

        CGWarpMouseCursorPosition(targetPt)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func notifyObserver() {
        let connected = isHardwareConnected
        let touching = isTouching
        let pt = normalizedTouchPoint
        let contacts = activeContactCount
        DispatchQueue.main.async { [weak self] in
            self?.onTouchStateChanged?(connected, touching, pt, contacts)
        }
    }
}
