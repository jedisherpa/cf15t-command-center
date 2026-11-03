import Cocoa
import SwiftUI
import Combine

@MainActor
final class CommandCenterViewModel: ObservableObject {
    // MARK: - Published State

    @Published var openWindows: [MonitoredWindow] = []
    @Published var stageWindowID: CGWindowID?
    @Published var excludedWindowIDs: Set<CGWindowID> = []

    @Published var agentSnapshots: [AgentStatusSnapshot] = []
    @Published var runningTasks: [RunningTaskItem] = []

    // Voice Assistant Deck (Grok Bot <-> Dot / Configurable)
    @Published var slotA: VoiceAssistantConfig = .defaultSlotA {
        didSet { saveVoiceConfigs() }
    }
    @Published var slotB: VoiceAssistantConfig = .defaultSlotB {
        didSet { saveVoiceConfigs() }
    }
    @Published var activeVoiceSlotID: String = "slotA"
    @Published var exclusiveMicHandoff: Bool = true
    @Published var systemMicMuted: Bool = false
    @Published var systemMicVolume: Float = 0.85
    @Published var audioInputDeviceName: String = "Built-in Microphone"

    // Window Tiling & CF15T Options
    @Published var tilingMode: TilingLayoutMode = .centerStageBorder
    @Published var targetDisplayMode: TargetDisplayMode = .primaryDisplay
    @Published var autoTileRealWindowsOnTap: Bool = true
    @Published var captureLivePreviews: Bool = true
    @Published var cursorSnapbackEnabled: Bool = true {
        didSet {
            CursorSnapbackEngine.shared.isSnapbackEnabled = cursorSnapbackEnabled
        }
    }
    @Published var keepAwakeEnabled: Bool = true {
        didSet {
            KeepAwakeWorker.shared.setKeepAwake(enabled: keepAwakeEnabled)
            statusBannerMessage = keepAwakeEnabled
                ? "Keep-Awake Worker ON — Sleep & Screensaver blocked on both screens"
                : "Keep-Awake Worker OFF — Standard macOS sleep timers restored"
        }
    }
    @Published var sisHardwareConnected: Bool = false
    @Published var sisIsTouching: Bool = false
    @Published var sisNormalizedPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var sisActiveContacts: [SiSTouchContact] = []
    @Published var sisRemapToCF15TEnabled: Bool = true {
        didSet {
            SiSTouchHardwareDriver.shared.isRemapToCF15TEnabled = sisRemapToCF15TEnabled
        }
    }
    @Published var isAccessibilityGranted: Bool = false
    @Published var connectedScreenCount: Int = 1
    @Published var statusBannerMessage: String = "Ready — Tap any border window to expand it Center Stage"

    @Published var isShowingVoiceSlotEditor: Bool = false

    private var refreshTimer: Timer?
    private let defaultsKeySlotA = "cf15t.voice.slotA"
    private let defaultsKeySlotB = "cf15t.voice.slotB"

    init() {
        loadVoiceConfigs()
        isAccessibilityGranted = WindowTilingEngine.shared.isAccessibilityTrusted(promptIfNeeded: false)
        CursorSnapbackEngine.shared.isSnapbackEnabled = cursorSnapbackEnabled
        CursorSnapbackEngine.shared.startMonitoring()
        KeepAwakeWorker.shared.setKeepAwake(enabled: keepAwakeEnabled)

        SiSTouchHardwareDriver.shared.isRemapToCF15TEnabled = sisRemapToCF15TEnabled
        SiSTouchHardwareDriver.shared.onTouchStateChanged = { [weak self] connected, touching, pt, contacts in
            guard let self = self else { return }
            self.sisHardwareConnected = connected
            self.sisIsTouching = touching
            self.sisNormalizedPoint = pt
            self.sisActiveContacts = contacts
        }
        SiSTouchHardwareDriver.shared.start()

        refreshAudioState()
        refreshAll(captureImages: true)
        startPeriodicRefresh()
    }

    func startPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.refreshAudioState()
                self.refreshAll(captureImages: self.captureLivePreviews)
            }
        }
    }

    // MARK: - Computed Stage & Border Windows

    var visibleTiledWindows: [MonitoredWindow] {
        let filtered = openWindows.filter { !excludedWindowIDs.contains($0.id) }
        return Array(filtered.prefix(9))
    }

    var currentStageWindow: MonitoredWindow? {
        let pool = visibleTiledWindows
        if let stageID = stageWindowID, let match = pool.first(where: { $0.id == stageID }) {
            return match
        }
        return pool.first
    }

    var currentBorderWindows: [MonitoredWindow] {
        guard let stage = currentStageWindow else { return [] }
        return visibleTiledWindows.filter { $0.id != stage.id }
    }

    // MARK: - Refresh Logic

    func refreshAll(captureImages: Bool = true) {
        connectedScreenCount = NSScreen.screens.count
        isAccessibilityGranted = WindowTilingEngine.shared.isAccessibilityTrusted(promptIfNeeded: false)

        let fetchedWindows = WindowTilingEngine.shared.fetchOpenWindows(capturePreviews: captureImages)
        self.openWindows = fetchedWindows

        if let currentID = stageWindowID, fetchedWindows.contains(where: { $0.id == currentID }) {
            // Keep existing stage selection
        } else {
            // Smart default: prefer active Voice Agent window (Grok Bot or Dot/ChatGPT), then any AI agent, then first window
            let activeSlot = (activeVoiceSlotID == "slotA") ? slotA : slotB
            if let voiceWin = fetchedWindows.first(where: { matchesVoiceSlot($0, slot: activeSlot) }) {
                stageWindowID = voiceWin.id
            } else if let aiWin = fetchedWindows.first(where: { $0.platform != nil }) {
                stageWindowID = aiWin.id
            } else {
                stageWindowID = fetchedWindows.first?.id
            }
        }

        let scanResult = AgentAndTaskMonitor.shared.scanPlatformsAndTasks(openWindows: fetchedWindows)
        self.agentSnapshots = scanResult.agents
        self.runningTasks = scanResult.tasks
    }

    // MARK: - Real Per-Window Telemetry & Voice Channel Matching

    func matchesVoiceSlot(_ window: MonitoredWindow, slot: VoiceAssistantConfig) -> Bool {
        let appLower = window.appName.lowercased()
        let titleLower = window.windowTitle.lowercased()
        let targetAppLower = slot.targetAppName.lowercased()
        let dispLower = slot.displayName.lowercased()
        return (!targetAppLower.isEmpty && appLower.contains(targetAppLower)) ||
               (!dispLower.isEmpty && (appLower.contains(dispLower) || titleLower.contains(dispLower)))
    }

    func voiceSlotMatch(for window: MonitoredWindow) -> (slotID: String, channelCode: String, displayName: String, isActiveTarget: Bool, isMicLive: Bool)? {
        if matchesVoiceSlot(window, slot: slotA) {
            return (
                slotID: "slotA",
                channelCode: "CH-01",
                displayName: slotA.displayName,
                isActiveTarget: activeVoiceSlotID == "slotA",
                isMicLive: slotA.isMicEnabled && !systemMicMuted
            )
        }
        if matchesVoiceSlot(window, slot: slotB) {
            return (
                slotID: "slotB",
                channelCode: "CH-02",
                displayName: slotB.displayName,
                isActiveTarget: activeVoiceSlotID == "slotB",
                isMicLive: slotB.isMicEnabled && !systemMicMuted
            )
        }
        return nil
    }

    func cpuPercent(for window: MonitoredWindow) -> Double {
        if let plat = window.platform,
           let snap = agentSnapshots.first(where: { $0.platform == plat }) {
            return snap.cpuPercent
        }
        let matchingTasks = runningTasks.filter {
            $0.pid == window.ownerPID ||
            $0.commandName.localizedCaseInsensitiveContains(window.appName)
        }
        return matchingTasks.reduce(0.0) { $0 + $1.cpuPercent }
    }

    func memoryMB(for window: MonitoredWindow) -> Double {
        if let plat = window.platform,
           let snap = agentSnapshots.first(where: { $0.platform == plat }) {
            return snap.memoryMB
        }
        let matchingTasks = runningTasks.filter {
            $0.pid == window.ownerPID ||
            $0.commandName.localizedCaseInsensitiveContains(window.appName)
        }
        return matchingTasks.reduce(0.0) { $0 + $1.memoryMB }
    }

    func refreshAudioState() {
        let mgr = CoreAudioMicManager.shared
        systemMicMuted = mgr.isSystemMicMuted()
        systemMicVolume = mgr.getInputVolumeScalar()
        audioInputDeviceName = mgr.defaultInputDeviceName()

        if systemMicMuted {
            slotA.isMicEnabled = false
            slotB.isMicEnabled = false
        }
    }

    // MARK: - Tap Border Window -> Promote to Center Stage + Tile Real Windows

    func promoteWindowToStage(_ window: MonitoredWindow) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            stageWindowID = window.id
        }

        // Always bring the selected application/window to the front immediately
        WindowTilingEngine.shared.focusWindow(window)

        if autoTileRealWindowsOnTap && WindowTilingEngine.shared.isAccessibilityTrusted(promptIfNeeded: false) {
            applyRealScreenTilingNow(stageWindow: window, promptIfUntrusted: false)
        } else {
            statusBannerMessage = "Switched to \(window.appName) (\(Int(window.bounds.width))×\(Int(window.bounds.height)))"
        }
    }

    func applyRealScreenTilingNow(stageWindow: MonitoredWindow? = nil, promptIfUntrusted: Bool = true) {
        guard let stage = stageWindow ?? currentStageWindow else {
            statusBannerMessage = "No open windows available to tile"
            return
        }

        WindowTilingEngine.shared.focusWindow(stage)

        if !WindowTilingEngine.shared.isAccessibilityTrusted(promptIfNeeded: promptIfUntrusted) {
            if promptIfUntrusted {
                WindowTilingEngine.shared.openSystemAccessibilitySettings()
            }
            statusBannerMessage = "Activated \(stage.appName) — Toggle ON 'CF15T Command Center' in Accessibility to resize windows"
            return
        }

        let borders = visibleTiledWindows.filter { $0.id != stage.id }
        WindowTilingEngine.shared.tileWindowsOnScreen(
            stageWindow: stage,
            borderWindows: borders,
            mode: tilingMode,
            targetDisplay: targetDisplayMode
        )

        statusBannerMessage = "Tiled \(1 + borders.count) windows (\(tilingMode.shortLabel)) — Stage: \(stage.appName)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshAll(captureImages: true)
        }
    }

    func restoreOriginalWindowPositions() {
        WindowTilingEngine.shared.restoreOriginalWindowFrames(windows: openWindows)
        statusBannerMessage = "Restored original window positions and sizes"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshAll(captureImages: true)
        }
    }

    func toggleWindowInclusion(_ window: MonitoredWindow) {
        if excludedWindowIDs.contains(window.id) {
            excludedWindowIDs.remove(window.id)
        } else {
            excludedWindowIDs.insert(window.id)
        }
    }

    // MARK: - Voice Assistant Switching (Grok Bot <-> Dot) & Mic Control

    func pingPongSwitchVoiceAssistants() {
        let nextSlotID = (activeVoiceSlotID == "slotA") ? "slotB" : "slotA"
        switchToVoiceSlot(nextSlotID, toggleMicIfExclusive: exclusiveMicHandoff)
    }

    func switchToVoiceSlot(_ slotID: String, toggleMicIfExclusive: Bool = true) {
        activeVoiceSlotID = slotID
        let targetSlot = (slotID == "slotA") ? slotA : slotB

        CoreAudioMicManager.shared.activateOrLaunchAssistant(targetSlot)

        // Also promote that assistant's window to Center Stage if open
        if let matchingWin = openWindows.first(where: { win in
            win.appName.localizedCaseInsensitiveContains(targetSlot.targetAppName) ||
            win.appName.localizedCaseInsensitiveContains(targetSlot.displayName) ||
            win.windowTitle.localizedCaseInsensitiveContains(targetSlot.displayName)
        }) {
            promoteWindowToStage(matchingWin)
        }

        if toggleMicIfExclusive {
            if slotID == "slotA" {
                setSlotMic("slotA", enabled: true)
                slotB.isMicEnabled = false
            } else {
                setSlotMic("slotB", enabled: true)
                slotA.isMicEnabled = false
            }
        } else {
            statusBannerMessage = "Switched to \(targetSlot.displayName)"
        }
    }

    func toggleSlotMic(_ slotID: String) {
        if slotID == "slotA" {
            setSlotMic("slotA", enabled: !slotA.isMicEnabled)
        } else {
            setSlotMic("slotB", enabled: !slotB.isMicEnabled)
        }
    }

    func setSlotMic(_ slotID: String, enabled: Bool) {
        let mgr = CoreAudioMicManager.shared

        if slotID == "slotA" {
            slotA.isMicEnabled = enabled
            if enabled && exclusiveMicHandoff {
                slotB.isMicEnabled = false
            }
            if enabled {
                activeVoiceSlotID = "slotA"
                mgr.setSystemMicMuted(false)
                systemMicMuted = false
                mgr.triggerVoiceShortcut(for: slotA, activateAppFirst: true)
                statusBannerMessage = "\(slotA.displayName) Mic ON (Live) — \(slotB.displayName) Muted"
            } else {
                mgr.triggerVoiceShortcut(for: slotA, activateAppFirst: false)
                if !slotB.isMicEnabled {
                    mgr.setSystemMicMuted(true)
                    systemMicMuted = true
                }
                statusBannerMessage = "\(slotA.displayName) Mic Muted"
            }
        } else {
            slotB.isMicEnabled = enabled
            if enabled && exclusiveMicHandoff {
                slotA.isMicEnabled = false
            }
            if enabled {
                activeVoiceSlotID = "slotB"
                mgr.setSystemMicMuted(false)
                systemMicMuted = false
                mgr.triggerVoiceShortcut(for: slotB, activateAppFirst: true)
                statusBannerMessage = "\(slotB.displayName) Mic ON (Live) — \(slotA.displayName) Muted"
            } else {
                mgr.triggerVoiceShortcut(for: slotB, activateAppFirst: false)
                if !slotA.isMicEnabled {
                    mgr.setSystemMicMuted(true)
                    systemMicMuted = true
                }
                statusBannerMessage = "\(slotB.displayName) Mic Muted"
            }
        }
    }

    func toggleSystemMasterMicMute() {
        let newMuted = !systemMicMuted
        CoreAudioMicManager.shared.setSystemMicMuted(newMuted)
        systemMicMuted = newMuted
        if newMuted {
            slotA.isMicEnabled = false
            slotB.isMicEnabled = false
            statusBannerMessage = "System Hardware Microphone Muted (0% Input)"
        } else {
            systemMicVolume = CoreAudioMicManager.shared.getInputVolumeScalar()
            statusBannerMessage = "System Hardware Microphone Unmuted (\(Int(systemMicVolume * 100))%)"
        }
    }

    func updateMicVolume(_ newVol: Float) {
        systemMicVolume = newVol
        CoreAudioMicManager.shared.setInputVolume(newVol)
        systemMicMuted = (newVol <= 0.01)
    }

    // MARK: - Launch or Focus Agent Platform

    func activateOrLaunchPlatform(_ snapshot: AgentStatusSnapshot) {
        if let win = openWindows.first(where: { $0.platform == snapshot.platform }) {
            promoteWindowToStage(win)
            return
        }
        if let pid = snapshot.primaryPID, let app = NSRunningApplication(processIdentifier: pid) {
            NSApp.yieldActivation(to: app)
            app.unhide()
            app.activate(options: [.activateAllWindows])
            if let bundleURL = app.bundleURL {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: cfg, completionHandler: nil)
            }
            statusBannerMessage = "Activated \(snapshot.platform.rawValue)"
            return
        }
        for path in snapshot.platform.appPaths {
            if FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
                statusBannerMessage = "Launching \(snapshot.platform.rawValue)..."
                return
            }
        }
        statusBannerMessage = "\(snapshot.platform.rawValue) is not installed in /Applications"
    }

    func snapPanelToCF15T() {
        statusBannerMessage = CursorSnapbackEngine.shared.moveCommandCenterWindowToCF15T()
    }

    func requestAccessibilityPermission() {
        WindowTilingEngine.shared.openSystemAccessibilitySettings()
        statusBannerMessage = "Opened System Settings → Accessibility (toggle ON 'CF15T Command Center')"
    }

    // MARK: - Persistence for Voice Slots

    private func loadVoiceConfigs() {
        let defaults = UserDefaults.standard
        if let dataA = defaults.data(forKey: defaultsKeySlotA),
           let decodedA = try? JSONDecoder().decode(VoiceAssistantConfig.self, from: dataA) {
            slotA = decodedA
        }
        if let dataB = defaults.data(forKey: defaultsKeySlotB),
           let decodedB = try? JSONDecoder().decode(VoiceAssistantConfig.self, from: dataB) {
            if decodedB.displayName == "Dot" && decodedB.targetAppName == "Claude" {
                slotB = .defaultSlotB
                saveVoiceConfigs()
            } else {
                slotB = decodedB
            }
        }
    }

    private func saveVoiceConfigs() {
        let defaults = UserDefaults.standard
        if let dataA = try? JSONEncoder().encode(slotA) {
            defaults.set(dataA, forKey: defaultsKeySlotA)
        }
        if let dataB = try? JSONEncoder().encode(slotB) {
            defaults.set(dataB, forKey: defaultsKeySlotB)
        }
    }
}
