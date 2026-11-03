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

    // Dual Operating Modes: ORCHESTRATE (Main Screen Switcher) vs. FULL CONTROL (Laptop Closed / Travel)
    @Published var operatingMode: CommandCenterOperatingMode = .orchestrate
    @Published var orchestrateTapAction: OrchestrateTapActionMode = .focusSingleAppOnMain
    @Published var isFullControlDocked: Bool = false
    @Published var showTouchKeyboardInDock: Bool = false
    @Published var quickTypeText: String = ""
    @Published var perTileInstructionDraft: [CGWindowID: String] = [:]
    @Published var isLaptopLidClosed: Bool = false
    @Published var isClamshellBatterySleepDisabled: Bool = false

    var dictationEngine = UniversalVoiceDictationEngine.shared
    var speechEngine = SensoryFriendlySpeechEngine.shared
    private var dictationCancellable: AnyCancellable?
    private var speechCancellable: AnyCancellable?

    // Window Tiling & CF15T Options
    @Published var tilingMode: TilingLayoutMode = .leftStagePerimeter
    @Published var targetDisplayMode: TargetDisplayMode = .primaryDisplay
    @Published var autoTileRealWindowsOnTap: Bool = true
    @Published var captureLivePreviews: Bool = true

    // Adjustable Layout, Visuals & Program Selection Settings (Nearsighted & Sensory-Friendly Big Defaults)
    @Published var isShowingSettingsSheet: Bool = false
    @Published var programSelectionMode: ProgramSelectionMode = .automatic
    @Published var customAllowedApps: Set<String> = [
        "grok bot", "chatgpt", "antigravity", "signal", "whatsapp", "claude", "codex", "google chrome"
    ]
    @Published var hiddenAppNamesInAutoMode: Set<String> = []
    @Published var defaultStageAppName: String = "" // "" = Automatic (Active Voice / AI Agent)
    @Published var tileContentViewMode: TileContentViewMode = .splitVisualAndFeed
    @Published var stageScaleFactor: Double = 0.65
    @Published var matrixWidthRatio: Double = 0.74
    @Published var isRightPanelCollapsed: Bool = true
    @Published var feedFontScale: Double = 1.48
    @Published var maxTiledWindows: Int = 4
    @Published var showFloatingFlowLines: Bool = false

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
    private let defaultsKeySelectionMode = "cf15t.programs.mode"
    private let defaultsKeyCustomAllowed = "cf15t.programs.customAllowed"
    private let defaultsKeyAutoHidden = "cf15t.programs.autoHidden"
    private let defaultsKeyDefaultStageApp = "cf15t.programs.defaultStageApp"
    private let defaultsKeyTileViewMode = "cf15t.ui.tileViewMode"
    private let defaultsKeyStageScale = "cf15t.ui.stageScale"
    private let defaultsKeyMatrixWidth = "cf15t.ui.matrixWidth"
    private let defaultsKeyFontScale = "cf15t.ui.nearsightedFontScale"
    private let defaultsKeyMaxWindows = "cf15t.ui.nearsightedMaxWindows"
    private let defaultsKeyShowFlowLines = "cf15t.ui.showFlowLines"
    private let defaultsKeyTilingMode = "cf15t.ui.nearsightedTilingMode"
    private let defaultsKeyOperatingMode = "cf15t.mode.operatingMode"
    private let defaultsKeyOrchestrateAction = "cf15t.mode.orchestrateAction"

    init() {
        loadVoiceConfigs()
        loadDashboardPreferences()
        isAccessibilityGranted = WindowTilingEngine.shared.isAccessibilityTrusted(promptIfNeeded: false)
        isLaptopLidClosed = KeepAwakeWorker.shared.isLaptopLidClosed()
        isClamshellBatterySleepDisabled = KeepAwakeWorker.shared.isClamshellSleepDisabled()

        dictationCancellable = dictationEngine.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        speechCancellable = speechEngine.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        dictationEngine.onDictationSent = { [weak self] win, text in
            guard let self = self else { return }
            self.statusBannerMessage = "🎙️ Sent dictated instruction to \(win.appName): \"\(text)\""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.refreshAll(captureImages: true)
            }
        }

        refreshAudioState()
        refreshAll(captureImages: true)
        applyModeHardwareConfiguration(for: operatingMode, isUserInitiatedSwitch: false)
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

    // MARK: - Computed Stage & Border Windows + Program Filtering

    func normalizedAppKey(_ appName: String) -> String {
        appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func isProgramDisplayed(_ appName: String) -> Bool {
        let key = normalizedAppKey(appName)
        switch programSelectionMode {
        case .automatic:
            return !hiddenAppNamesInAutoMode.contains(key)
        case .customDefaults:
            return customAllowedApps.contains(key)
        }
    }

    func toggleProgramDisplayed(_ appName: String) {
        let key = normalizedAppKey(appName)
        // Clear any one-off window ID exclusions for this app so the toggle takes effect immediately
        for win in openWindows where normalizedAppKey(win.appName) == key {
            excludedWindowIDs.remove(win.id)
        }

        switch programSelectionMode {
        case .automatic:
            if hiddenAppNamesInAutoMode.contains(key) {
                hiddenAppNamesInAutoMode.remove(key)
                statusBannerMessage = "Showing \(appName) in Window Tiling Matrix"
            } else {
                hiddenAppNamesInAutoMode.insert(key)
                statusBannerMessage = "Hidden \(appName) from Window Tiling Matrix"
            }
        case .customDefaults:
            if customAllowedApps.contains(key) {
                customAllowedApps.remove(key)
                statusBannerMessage = "Removed \(appName) from Custom Displayed Programs"
            } else {
                customAllowedApps.insert(key)
                statusBannerMessage = "Added \(appName) to Custom Displayed Programs"
            }
        }
    }

    var allSelectablePrograms: [SelectableProgramEntry] {
        var entriesByKey: [String: SelectableProgramEntry] = [:]

        // 1. Add all currently open programs
        let groupedOpen = Dictionary(grouping: openWindows, by: { normalizedAppKey($0.appName) })
        for (key, wins) in groupedOpen {
            guard let first = wins.first else { continue }
            let cat: String = {
                if first.platform != nil { return "AI AGENT" }
                let style = AppContentFeedExtractor.shared.classifyStyle(for: first)
                switch style {
                case .messagingChat: return "MESSAGING"
                case .aiAgentThread: return "AI AGENT"
                case .browserDocument: return "BROWSER"
                case .mediaNowPlaying: return "MEDIA"
                case .systemInspector: return "MAC APP"
                }
            }()
            let displayName = (key == "chatgpt") ? "ChatGPT (Dot)" : first.appName
            entriesByKey[key] = SelectableProgramEntry(
                id: key,
                displayName: displayName,
                categoryLabel: cat,
                isCurrentlyOpen: true,
                openWindowCount: wins.count,
                appIcon: first.appIcon
            )
        }

        // 2. Also include well-known AI & Messaging programs even if not currently open so defaults can be set anytime
        let presets: [(key: String, name: String, category: String)] = [
            ("grok bot", "Grok Bot", "AI VOICE"),
            ("chatgpt", "ChatGPT (Dot)", "AI VOICE"),
            ("antigravity", "Antigravity", "AI AGENT"),
            ("signal", "Signal", "MESSAGING"),
            ("whatsapp", "WhatsApp", "MESSAGING"),
            ("messages", "Messages", "MESSAGING"),
            ("claude", "Claude", "AI AGENT"),
            ("codex", "Codex", "AI AGENT"),
            ("google chrome", "Google Chrome", "BROWSER"),
            ("safari", "Safari", "BROWSER"),
            ("music", "Music", "MEDIA"),
            ("finder", "Finder", "MAC APP"),
            ("terminal", "Terminal", "MAC APP"),
            ("system settings", "System Settings", "MAC APP")
        ]

        for p in presets where entriesByKey[p.key] == nil {
            entriesByKey[p.key] = SelectableProgramEntry(
                id: p.key,
                displayName: p.name,
                categoryLabel: p.category,
                isCurrentlyOpen: false,
                openWindowCount: 0,
                appIcon: nil
            )
        }

        return entriesByKey.values.sorted { a, b in
            if a.isCurrentlyOpen != b.isCurrentlyOpen {
                return a.isCurrentlyOpen && !b.isCurrentlyOpen
            }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    var visibleTiledWindows: [MonitoredWindow] {
        let filtered = openWindows.filter { win in
            !excludedWindowIDs.contains(win.id) && isProgramDisplayed(win.appName)
        }
        return Array(filtered.prefix(max(1, maxTiledWindows)))
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

        let wasLidClosed = isLaptopLidClosed
        let nowLidClosed = KeepAwakeWorker.shared.isLaptopLidClosed()
        isLaptopLidClosed = nowLidClosed
        isClamshellBatterySleepDisabled = KeepAwakeWorker.shared.isClamshellSleepDisabled()

        let fetchedWindows = WindowTilingEngine.shared.fetchOpenWindows(capturePreviews: captureImages)
        self.openWindows = fetchedWindows

        // If the user just closed the MacBook lid, automatically switch to FULL CONTROL and shield Command Center on top!
        if !wasLidClosed && nowLidClosed {
            if operatingMode != .fullControl {
                setOperatingMode(.fullControl, promptClamshellAuthIfNeeded: false)
            } else {
                _ = CursorSnapbackEngine.shared.configureCommandCenterWindowFrame(
                    dockedTopBar: false,
                    alwaysOnTop: true
                )
            }
            statusBannerMessage = "Laptop Lid Closed — Command Center Locked ON TOP in Full Control Mode"
        }

        let currentPool = visibleTiledWindows
        if let currentID = stageWindowID, currentPool.contains(where: { $0.id == currentID }) {
            // Keep existing stage selection
        } else if !defaultStageAppName.isEmpty,
                  let preferred = currentPool.first(where: { normalizedAppKey($0.appName) == normalizedAppKey(defaultStageAppName) }) {
            stageWindowID = preferred.id
        } else {
            // Smart default: prefer active Voice Agent window (Grok Bot or Dot/ChatGPT), then any AI agent, then first window
            let activeSlot = (activeVoiceSlotID == "slotA") ? slotA : slotB
            if let voiceWin = currentPool.first(where: { matchesVoiceSlot($0, slot: activeSlot) }) {
                stageWindowID = voiceWin.id
            } else if let aiWin = currentPool.first(where: { $0.platform != nil }) {
                stageWindowID = aiWin.id
            } else {
                stageWindowID = currentPool.first?.id
            }
        }

        let scanResult = AgentAndTaskMonitor.shared.scanPlatformsAndTasks(openWindows: fetchedWindows)
        self.agentSnapshots = scanResult.agents
        self.runningTasks = scanResult.tasks
    }

    // MARK: - Dual Operating Modes: ORCHESTRATE vs. FULL CONTROL (Travel / Clamshell)

    var currentDockReserveHeight: CGFloat {
        guard operatingMode == .fullControl && isFullControlDocked else { return 0 }
        return showTouchKeyboardInDock ? 276 : 112
    }

    func setOperatingMode(_ mode: CommandCenterOperatingMode, promptClamshellAuthIfNeeded: Bool = false) {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
            operatingMode = mode
        }
        applyModeHardwareConfiguration(for: mode, isUserInitiatedSwitch: true)
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKeyOperatingMode)
    }

    private func applyModeHardwareConfiguration(for mode: CommandCenterOperatingMode, isUserInitiatedSwitch: Bool) {
        switch mode {
        case .orchestrate:
            isFullControlDocked = false
            showTouchKeyboardInDock = false
            isRightPanelCollapsed = true
            targetDisplayMode = .primaryDisplay
            cursorSnapbackEnabled = true
            SiSTouchHardwareDriver.shared.isFullControlSystemTouchMode = false
            _ = CursorSnapbackEngine.shared.configureCommandCenterWindowFrame(
                dockedTopBar: false,
                alwaysOnTop: false
            )

            if isUserInitiatedSwitch {
                // Move open programs back onto the Main MacBook Screen!
                if orchestrateTapAction == .tileAllOnMain, let stage = currentStageWindow {
                    let borders = visibleTiledWindows.filter { $0.id != stage.id }
                    WindowTilingEngine.shared.tileWindowsOnScreen(
                        stageWindow: stage,
                        borderWindows: borders,
                        mode: tilingMode,
                        targetDisplay: .primaryDisplay,
                        stageScale: CGFloat(stageScaleFactor),
                        topDockReserveHeight: 0
                    )
                } else if let stage = currentStageWindow {
                    WindowTilingEngine.shared.focusAndFillSingleWindow(
                        stage,
                        targetDisplay: .primaryDisplay,
                        topDockReserveHeight: 0,
                        fillDisplay: autoTileRealWindowsOnTap
                    )
                }
            }
            statusBannerMessage = "ORCHESTRATE MODE — Tap any tile on CF15T to switch/tile programs on your Main MacBook Screen"

        case .fullControl:
            keepAwakeEnabled = true
            isFullControlDocked = false
            // Expand the Interactive App Matrix across 100% of the screen and enable Per-Tile Voice & Command Decks!
            isRightPanelCollapsed = true
            targetDisplayMode = .externalDisplay
            cursorSnapbackEnabled = false
            SiSTouchHardwareDriver.shared.isFullControlSystemTouchMode = true
            isClamshellBatterySleepDisabled = KeepAwakeWorker.shared.isClamshellSleepDisabled()

            // Lock the Command Center FULL-SCREEN and ALWAYS-ON-TOP (.floating) on the CF15T so closing the laptop
            // NEVER dumps open laptop windows on top of the Command Center!
            _ = CursorSnapbackEngine.shared.configureCommandCenterWindowFrame(
                dockedTopBar: false,
                alwaysOnTop: true
            )

            statusBannerMessage = "🚀 FULL CONTROL MODE — Command Center Locked On Top · Use 🎙️ DICTATE on any app tile to voice-command it!"
        }
    }

    func toggleClamshellBatterySleepLock() {
        let targetState = !KeepAwakeWorker.shared.isClamshellSleepDisabled()
        KeepAwakeWorker.shared.setClamshellBatterySleepDisabled(targetState) { [weak self] _, msg in
            guard let self = self else { return }
            self.isClamshellBatterySleepDisabled = KeepAwakeWorker.shared.isClamshellSleepDisabled()
            self.statusBannerMessage = msg
        }
    }

    func openWindowInFullControlCanvas(_ window: MonitoredWindow) {
        stageWindowID = window.id
        if operatingMode != .fullControl {
            setOperatingMode(.fullControl, promptClamshellAuthIfNeeded: false)
        }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
            isFullControlDocked = true
        }
        let dockH = currentDockReserveHeight
        _ = CursorSnapbackEngine.shared.configureCommandCenterWindowFrame(dockedTopBar: true, dockHeight: dockH)
        WindowTilingEngine.shared.focusAndFillSingleWindow(
            window,
            targetDisplay: .externalDisplay,
            topDockReserveHeight: dockH,
            fillDisplay: true
        )
        statusBannerMessage = "FULL CONTROL: \(window.appName) active on CF15T below Touch Dock"
    }

    func expandFullControlMatrix() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
            isFullControlDocked = false
            showTouchKeyboardInDock = false
        }
        _ = CursorSnapbackEngine.shared.configureCommandCenterWindowFrame(dockedTopBar: false)
        refreshAll(captureImages: true)
        statusBannerMessage = "Expanded Full Command Center Matrix on CF15T"
    }

    func tileAllBelowFullControlDock() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
            isFullControlDocked = true
        }
        let dockH = currentDockReserveHeight
        _ = CursorSnapbackEngine.shared.configureCommandCenterWindowFrame(dockedTopBar: true, dockHeight: dockH)
        applyRealScreenTilingNow(stageWindow: currentStageWindow, promptIfUntrusted: false)
    }

    func toggleFullControlTouchKeyboard() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showTouchKeyboardInDock.toggle()
        }
        if isFullControlDocked {
            let dockH = currentDockReserveHeight
            _ = CursorSnapbackEngine.shared.configureCommandCenterWindowFrame(dockedTopBar: true, dockHeight: dockH)
            if let stage = currentStageWindow {
                WindowTilingEngine.shared.focusAndFillSingleWindow(
                    stage,
                    targetDisplay: .externalDisplay,
                    topDockReserveHeight: dockH,
                    fillDisplay: true
                )
            }
        }
    }

    func sendQuickTypeText(pressReturn: Bool = true) {
        let textToSend = quickTypeText
        WindowTilingEngine.shared.sendTextToTargetWindow(
            textToSend,
            pressReturn: pressReturn,
            targetWindow: currentStageWindow
        )
        if !textToSend.isEmpty {
            statusBannerMessage = "Sent \"\(textToSend)\" to \(currentStageWindow?.appName ?? "Active App")"
            quickTypeText = ""
        }
    }

    func appendTouchCharacter(_ char: String) {
        WindowTilingEngine.shared.sendTextToTargetWindow(
            char,
            pressReturn: false,
            targetWindow: currentStageWindow
        )
    }

    func sendSpecialKeyToActiveApp(keyCode: CGKeyCode, flags: CGEventFlags = [], label: String) {
        WindowTilingEngine.shared.sendKeystrokeToTargetWindow(
            keyCode: keyCode,
            flags: flags,
            targetWindow: currentStageWindow
        )
        statusBannerMessage = "Sent \(label) to \(currentStageWindow?.appName ?? "Active App")"
    }

    func scrollActiveApp(deltaY: Int32) {
        WindowTilingEngine.shared.sendScrollToTargetWindow(
            deltaY: deltaY,
            targetWindow: currentStageWindow
        )
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

        if operatingMode == .fullControl {
            // In FULL CONTROL mode, promote the tapped app to #1 Center Stage inside the Command Center
            // (keeping the Command Center Always-On-Top so desktop windows never cover it!)
            statusBannerMessage = "FULL CONTROL: \(window.appName) is now #1 Center Stage — Tap 🎙️ DICTATE to speak your next instruction"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.refreshAll(captureImages: true)
            }
            return
        }

        // In ORCHESTRATE mode, switch/focus or tile on the Main MacBook Screen
        if orchestrateTapAction == .focusSingleAppOnMain {
            WindowTilingEngine.shared.focusAndFillSingleWindow(
                window,
                targetDisplay: targetDisplayMode,
                topDockReserveHeight: 0,
                fillDisplay: autoTileRealWindowsOnTap
            )
            statusBannerMessage = "ORCHESTRATE: Switched Main Screen to \(window.appName)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.refreshAll(captureImages: true)
            }
        } else if autoTileRealWindowsOnTap && WindowTilingEngine.shared.isAccessibilityTrusted(promptIfNeeded: false) {
            applyRealScreenTilingNow(stageWindow: window, promptIfUntrusted: false)
        } else {
            WindowTilingEngine.shared.focusWindow(window)
            statusBannerMessage = "Switched to \(window.appName) (\(Int(window.bounds.width))×\(Int(window.bounds.height)))"
        }
    }

    // MARK: - Universal Per-Tile Voice Dictation & Instruction Actions (For Every App)

    func isDictating(for window: MonitoredWindow) -> Bool {
        dictationEngine.isRecording && dictationEngine.targetWindowID == window.id
    }

    func toggleVoiceDictation(for window: MonitoredWindow) {
        stageWindowID = window.id
        dictationEngine.toggleDictation(for: window)
        statusBannerMessage = dictationEngine.statusText
    }

    func sendInstructionDraft(for window: MonitoredWindow, pressReturn: Bool = true) {
        let draft = (perTileInstructionDraft[window.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            // If no typed draft, send just Return key
            if pressReturn {
                WindowTilingEngine.shared.sendKeystrokeToTargetWindow(keyCode: 36, targetWindow: window)
            }
            return
        }
        perTileInstructionDraft[window.id] = ""
        dictationEngine.deliverInstructionToWindow(draft, window: window, pressReturn: pressReturn)
    }

    func scrollWindowInBackground(_ window: MonitoredWindow, deltaY: Int32) {
        WindowTilingEngine.shared.sendScrollToTargetWindow(deltaY: deltaY, targetWindow: window)
        statusBannerMessage = "Scrolled \(window.appName) \(deltaY > 0 ? "Up" : "Down")"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshAll(captureImages: true)
        }
    }

    func executeAACSymbolCard(_ card: AACVisualSymbolCard, for window: MonitoredWindow) {
        stageWindowID = window.id
        speechEngine.speakAACConfirmation(card.spokenConfirmation)

        switch card.action {
        case .sendPrompt(let prompt, let pressReturn):
            dictationEngine.deliverInstructionToWindow(prompt, window: window, pressReturn: pressReturn)
            statusBannerMessage = "\(card.emoji) Sent to \(window.appName): \"\(prompt)\""

        case .scrollWindow(let deltaY):
            scrollWindowInBackground(window, deltaY: deltaY)

        case .sendKeyCombo(let keyCode, let flags, let label):
            WindowTilingEngine.shared.sendKeystrokeToTargetWindow(
                keyCode: keyCode,
                flags: flags,
                targetWindow: window
            )
            statusBannerMessage = "\(card.emoji) \(label) in \(window.appName)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.refreshAll(captureImages: true)
            }
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
            targetDisplay: targetDisplayMode,
            stageScale: CGFloat(stageScaleFactor),
            topDockReserveHeight: currentDockReserveHeight
        )

        statusBannerMessage = "Tiled \(1 + borders.count) windows (\(tilingMode.shortLabel)) — Stage: \(stage.appName)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshAll(captureImages: true)
        }
    }

    // MARK: - Program Filter Presets & Persistent Defaults

    func selectAllPrograms() {
        excludedWindowIDs.removeAll()
        switch programSelectionMode {
        case .automatic:
            hiddenAppNamesInAutoMode.removeAll()
        case .customDefaults:
            for entry in allSelectablePrograms {
                customAllowedApps.insert(entry.id)
            }
        }
        statusBannerMessage = "Showing all open programs in Window Tiling Matrix"
    }

    func selectAIAndMessagingProgramsOnly() {
        excludedWindowIDs.removeAll()
        let aiAndChatKeys: Set<String> = [
            "grok bot", "chatgpt", "antigravity", "signal", "whatsapp",
            "messages", "claude", "codex", "telegram", "slack", "discord"
        ]
        programSelectionMode = .customDefaults
        customAllowedApps = aiAndChatKeys
        statusBannerMessage = "Filtered Matrix to AI & Messaging apps only (Signal, ChatGPT, Grok Bot, Antigravity)"
    }

    func saveDashboardPreferencesAsDefaults() {
        let d = UserDefaults.standard
        d.set(programSelectionMode.rawValue, forKey: defaultsKeySelectionMode)
        d.set(Array(customAllowedApps), forKey: defaultsKeyCustomAllowed)
        d.set(Array(hiddenAppNamesInAutoMode), forKey: defaultsKeyAutoHidden)
        d.set(defaultStageAppName, forKey: defaultsKeyDefaultStageApp)
        d.set(tileContentViewMode.rawValue, forKey: defaultsKeyTileViewMode)
        d.set(stageScaleFactor, forKey: defaultsKeyStageScale)
        d.set(matrixWidthRatio, forKey: defaultsKeyMatrixWidth)
        d.set(feedFontScale, forKey: defaultsKeyFontScale)
        d.set(maxTiledWindows, forKey: defaultsKeyMaxWindows)
        d.set(showFloatingFlowLines, forKey: defaultsKeyShowFlowLines)
        d.set(tilingMode.rawValue, forKey: defaultsKeyTilingMode)
        d.set(operatingMode.rawValue, forKey: defaultsKeyOperatingMode)
        d.set(orchestrateTapAction.rawValue, forKey: defaultsKeyOrchestrateAction)

        statusBannerMessage = "Saved your Program Selection & Dashboard Settings as persistent Defaults"
    }

    func resetToAutomaticDefaults() {
        programSelectionMode = .automatic
        hiddenAppNamesInAutoMode.removeAll()
        excludedWindowIDs.removeAll()
        defaultStageAppName = ""
        tileContentViewMode = .splitVisualAndFeed
        stageScaleFactor = 0.65
        matrixWidthRatio = 0.74
        isRightPanelCollapsed = true
        feedFontScale = 1.48
        maxTiledWindows = 4
        showFloatingFlowLines = false
        orchestrateTapAction = .focusSingleAppOnMain
        saveDashboardPreferencesAsDefaults()
        statusBannerMessage = "Reset to Big Sensory-Friendly Program View"
    }

    private func loadDashboardPreferences() {
        let d = UserDefaults.standard
        if let modeRaw = d.string(forKey: defaultsKeySelectionMode),
           let mode = ProgramSelectionMode(rawValue: modeRaw) {
            programSelectionMode = mode
        }
        if let allowedArr = d.stringArray(forKey: defaultsKeyCustomAllowed) {
            customAllowedApps = Set(allowedArr)
        }
        if let hiddenArr = d.stringArray(forKey: defaultsKeyAutoHidden) {
            hiddenAppNamesInAutoMode = Set(hiddenArr)
        }
        if let stageApp = d.string(forKey: defaultsKeyDefaultStageApp) {
            defaultStageAppName = stageApp
        }
        if let viewRaw = d.string(forKey: defaultsKeyTileViewMode),
           let vm = TileContentViewMode(rawValue: viewRaw) {
            tileContentViewMode = vm
        }
        if d.object(forKey: defaultsKeyStageScale) != nil {
            stageScaleFactor = max(0.42, min(0.78, d.double(forKey: defaultsKeyStageScale)))
        }
        if d.object(forKey: defaultsKeyMatrixWidth) != nil {
            matrixWidthRatio = max(0.48, min(0.95, d.double(forKey: defaultsKeyMatrixWidth)))
        }
        if d.object(forKey: defaultsKeyFontScale) != nil {
            feedFontScale = max(1.10, min(2.20, d.double(forKey: defaultsKeyFontScale)))
        }
        if d.object(forKey: defaultsKeyMaxWindows) != nil {
            maxTiledWindows = max(1, min(8, d.integer(forKey: defaultsKeyMaxWindows)))
        }
        if d.object(forKey: defaultsKeyShowFlowLines) != nil {
            showFloatingFlowLines = d.bool(forKey: defaultsKeyShowFlowLines)
        }
        if let tilingRaw = d.string(forKey: defaultsKeyTilingMode),
           let tm = TilingLayoutMode(rawValue: tilingRaw) {
            tilingMode = tm
        }
        if let opRaw = d.string(forKey: defaultsKeyOperatingMode),
           let op = CommandCenterOperatingMode(rawValue: opRaw) {
            operatingMode = op
        }
        if let orchRaw = d.string(forKey: defaultsKeyOrchestrateAction),
           let oa = OrchestrateTapActionMode(rawValue: orchRaw) {
            orchestrateTapAction = oa
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
