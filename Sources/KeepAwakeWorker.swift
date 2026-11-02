import Cocoa
import IOKit.pwr_mgt

/// Dedicated Keep-Awake & Anti-Screensaver Worker for CF15T Command Center.
/// Combines three macOS power assertions:
/// 1. kIOPMAssertionTypePreventUserIdleDisplaySleep (keeps both Built-in & CF15T screens on)
/// 2. kIOPMAssertionTypePreventUserIdleSystemSleep (keeps CPU & background agents active)
/// 3. Periodic IOPMAssertionDeclareUserActivity (kIOPMUserActiveLocal) every 20s to reset the screensaver timer
/// 4. Managed /usr/bin/caffeinate -diu -w <pid> worker subprocess tied to the app's lifecycle.
final class KeepAwakeWorker {
    static let shared = KeepAwakeWorker()

    private(set) var isActive: Bool = false
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var systemSleepAssertionID: IOPMAssertionID = 0
    private var userActivityAssertionID: IOPMAssertionID = 0
    private var hasDisplayAssertion: Bool = false
    private var hasSystemAssertion: Bool = false

    private var heartbeatTimer: Timer?
    private var caffeinateProcess: Process?
    private(set) var activatedAt: Date?

    private init() {}

    func setKeepAwake(enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        activatedAt = Date()

        acquireIOKitAssertions()
        declareUserActivityPulse()
        startCaffeinateSubprocess()

        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            self?.declareUserActivityPulse()
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        activatedAt = nil

        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        releaseIOKitAssertions()
        stopCaffeinateSubprocess()
    }

    private func acquireIOKitAssertions() {
        let reason = "CF15T Command Center — Keep Display & System Awake (Prevent Screensaver)" as CFString

        if !hasDisplayAssertion {
            let res1 = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &displaySleepAssertionID
            )
            hasDisplayAssertion = (res1 == kIOReturnSuccess)
        }

        if !hasSystemAssertion {
            let res2 = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &systemSleepAssertionID
            )
            hasSystemAssertion = (res2 == kIOReturnSuccess)
        }
    }

    private func releaseIOKitAssertions() {
        if hasDisplayAssertion {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
            hasDisplayAssertion = false
        }
        if hasSystemAssertion {
            IOPMAssertionRelease(systemSleepAssertionID)
            systemSleepAssertionID = 0
            hasSystemAssertion = false
        }
        if userActivityAssertionID != 0 {
            IOPMAssertionRelease(userActivityAssertionID)
            userActivityAssertionID = 0
        }
    }

    private func declareUserActivityPulse() {
        guard isActive else { return }
        let reason = "CF15T Command Center Active Control Surface" as CFString
        IOPMAssertionDeclareUserActivity(
            reason,
            kIOPMUserActiveLocal,
            &userActivityAssertionID
        )
    }

    private func startCaffeinateSubprocess() {
        stopCaffeinateSubprocess()
        let myPID = ProcessInfo.processInfo.processIdentifier
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -d: prevent display sleep, -i: prevent idle system sleep, -u: declare user active, -w: exit when app PID exits
        proc.arguments = ["-d", "-i", "-u", "-w", "\(myPID)"]
        do {
            try proc.run()
            caffeinateProcess = proc
        } catch {
            caffeinateProcess = nil
        }
    }

    private func stopCaffeinateSubprocess() {
        if let proc = caffeinateProcess {
            if proc.isRunning {
                proc.terminate()
            }
            caffeinateProcess = nil
        }
    }
}
