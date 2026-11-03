import Cocoa
import IOKit
import IOKit.pwr_mgt

/// Dedicated Keep-Awake, Anti-Screensaver & Clamshell Lid-Closed Travel Worker for CF15T Command Center.
/// Combines:
/// 1. kIOPMAssertionTypePreventUserIdleDisplaySleep (keeps Built-in & CF15T screens on)
/// 2. kIOPMAssertionTypePreventUserIdleSystemSleep + kIOPMAssertPreventSystemSleep (keeps CPU & USB-C display alive)
/// 3. Periodic IOPMAssertionDeclareUserActivity (kIOPMUserActiveLocal) every 15s to block the screensaver
/// 4. Managed /usr/bin/caffeinate -disu -w <pid> worker subprocess tied to the app's lifecycle
/// 5. Live IOKit IOPMrootDomain Clamshell Lid Sensor (AppleClamshellState) & Battery Lid-Close Override (SleepDisabled / pmset disablesleep).
final class KeepAwakeWorker {
    static let shared = KeepAwakeWorker()

    private(set) var isActive: Bool = false
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var systemSleepAssertionID: IOPMAssertionID = 0
    private var preventSystemSleepAssertionID: IOPMAssertionID = 0
    private var userActivityAssertionID: IOPMAssertionID = 0
    private var hasDisplayAssertion: Bool = false
    private var hasSystemAssertion: Bool = false
    private var hasPreventSystemSleepAssertion: Bool = false

    private var heartbeatTimer: Timer?
    private var caffeinateProcess: Process?
    private(set) var activatedAt: Date?
    private var isRunningPmsetAuth: Bool = false

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
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
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

    // MARK: - Live IOKit Clamshell Lid State & SleepDisabled Queries

    /// Reads `AppleClamshellState` directly from `IOPMrootDomain` in the IOKit registry.
    /// Returns `true` when the MacBook physical lid is closed.
    func isLaptopLidClosed() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return false }
        defer { IOObjectRelease(rootDomain) }

        if let prop = IORegistryEntryCreateCFProperty(
            rootDomain,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool {
            return prop
        }
        return false
    }

    /// Reads `SleepDisabled` directly from `IOPMrootDomain` in the IOKit registry.
    /// When `true`, macOS will NOT sleep even if the MacBook lid is closed on battery power (Uber/train travel mode).
    func isClamshellSleepDisabled() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return false }
        defer { IOObjectRelease(rootDomain) }

        if let prop = IORegistryEntryCreateCFProperty(
            rootDomain,
            "SleepDisabled" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool {
            return prop
        }
        return false
    }

    /// Arms or disarms kernel-level Clamshell Lid-Closed Sleep Prevention (`pmset -a disablesleep 1/0`).
    /// This allows closing the MacBook lid on battery power in an Uber or on a train while keeping the CF15T touchscreen alive.
    func setClamshellBatterySleepDisabled(
        _ disableSleep: Bool,
        completion: ((Bool, String) -> Void)? = nil
    ) {
        if isClamshellSleepDisabled() == disableSleep {
            let msg = disableSleep
                ? "Lid-Closed Travel Mode Armed — Safe to close MacBook lid on battery or AC"
                : "Standard MacBook lid-close sleep behavior restored"
            completion?(true, msg)
            return
        }

        guard !isRunningPmsetAuth else { return }
        isRunningPmsetAuth = true

        let flagValue = disableSleep ? "1" : "0"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scriptSource = "do shell script \"/usr/sbin/pmset -a disablesleep \(flagValue)\" with administrator privileges"
            var errorDict: NSDictionary?
            let script = NSAppleScript(source: scriptSource)
            _ = script?.executeAndReturnError(&errorDict)

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRunningPmsetAuth = false
                let nowDisabled = self.isClamshellSleepDisabled()
                if nowDisabled == disableSleep {
                    let msg = disableSleep
                        ? "Lid-Closed Travel Mode ARMED — You can now close the MacBook lid and run 100% from CF15T!"
                        : "Lid-Closed Travel Lock Disarmed — Laptop will sleep normally when closed on battery"
                    completion?(true, msg)
                } else {
                    let errMsg = (errorDict?[NSAppleScript.errorBriefMessage] as? String) ?? "Authorization canceled"
                    completion?(false, "Lid-Closed Battery Lock requires admin auth (\(errMsg)) — AC power clamshell still active")
                }
            }
        }
    }

    // MARK: - IOKit Power Assertions

    private func acquireIOKitAssertions() {
        let reason = "CF15T Command Center — Full Control & Orchestrate Keep-Awake" as CFString

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

        if !hasPreventSystemSleepAssertion {
            let res3 = IOPMAssertionCreateWithName(
                "PreventSystemSleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &preventSystemSleepAssertionID
            )
            hasPreventSystemSleepAssertion = (res3 == kIOReturnSuccess)
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
        if hasPreventSystemSleepAssertion {
            IOPMAssertionRelease(preventSystemSleepAssertionID)
            preventSystemSleepAssertionID = 0
            hasPreventSystemSleepAssertion = false
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
        // -d: prevent display sleep, -i: prevent idle system sleep, -s: prevent system sleep, -u: declare user active
        proc.arguments = ["-d", "-i", "-s", "-u", "-w", "\(myPID)"]
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
