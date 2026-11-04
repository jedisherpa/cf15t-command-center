import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?
    var statusItem: NSStatusItem?
    let viewModel = CommandCenterViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.paulcooper.cf15t-command-center") where app.processIdentifier != myPID {
            app.forceTerminate()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        setupMenuBarStatusItem()
        createAndShowMainWindow()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleScreenParametersChanged() {
        Task { @MainActor in
            let lidClosed = KeepAwakeWorker.shared.isLaptopLidClosed()
            if lidClosed && viewModel.operatingMode != .fullControl {
                viewModel.setOperatingMode(.fullControl)
            }
            let shieldOnTop = (viewModel.operatingMode == .fullControl || lidClosed)
            let isDocked = (viewModel.operatingMode == .fullControl && viewModel.isFullControlDocked)
            _ = CursorSnapbackEngine.shared.configureCommandCenterWindowFrame(
                dockedTopBar: isDocked,
                dockHeight: viewModel.currentDockReserveHeight,
                alwaysOnTop: shieldOnTop
            )
            viewModel.refreshAll(captureImages: true)

            // Re-assert Always-On-Top shield after macOS finishes migrating Clamshell windows
            for delay in [0.35, 0.90] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    let keepShield = (self.viewModel.operatingMode == .fullControl || KeepAwakeWorker.shared.isLaptopLidClosed())
                    _ = CursorSnapbackEngine.shared.configureCommandCenterWindowFrame(
                        dockedTopBar: self.viewModel.isFullControlDocked,
                        dockHeight: self.viewModel.currentDockReserveHeight,
                        alwaysOnTop: keepShield
                    )
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func createAndShowMainWindow() {
        let contentView = CommandCenterMainView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)

        // Full screen on the touchscreen (15.6" CF15T or 12.3" bar), or a centred window on the laptop alone
        let screens = NSScreen.screens
        let targetScreen: NSScreen = DisplayTargetManager.shared.commandCenterScreen() ?? screens.first!
        let onExternal = !DisplayTargetManager.shared.isBuiltIn(targetScreen)

        let initialFrame: NSRect = {
            if onExternal {
                return DisplayTargetManager.shared.usableFrame(for: targetScreen)
            } else {
                let vis = targetScreen.visibleFrame
                let w = min(1400, vis.width * 0.94)
                let h = min(860, vis.height * 0.90)
                return NSRect(
                    x: vis.midX - w / 2.0,
                    y: vis.midY - h / 2.0,
                    width: w,
                    height: h
                )
            }
        }()

        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CF15T Auxiliary Command Center — Windows • Agents • Voice (Grok Bot ⇄ Dot)"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Hide the traffic-light buttons so they don't sit on top of the touch controls (quit from the menu bar item)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // The app places itself on the touchscreen; don't let touches near the top drag the window around
        window.isMovable = false
        window.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1.0)
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 640, height: 360)
        window.setFrame(initialFrame, display: true)
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.mainWindow = window
        SiSTouchHardwareDriver.shared.targetCommandCenterWindow = window
    }

    private func setupMenuBarStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.center.inset.filled.badge.plus", accessibilityDescription: "CF15T Command Center")
            button.title = " CF15T"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show CF15T Command Center", action: #selector(showMainWindowAction), keyEquivalent: "0")
        menu.addItem(withTitle: "Mode 1: ORCHESTRATE (Main Screen Switcher)", action: #selector(switchToOrchestrateAction), keyEquivalent: "1")
        menu.addItem(withTitle: "Mode 2: FULL CONTROL (Laptop Closed / Travel)", action: #selector(switchToFullControlAction), keyEquivalent: "2")
        menu.addItem(withTitle: "Settings & Program Selection...", action: #selector(openSettingsAction), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Swap Voice Assistant (Grok Bot ⇄ Dot)", action: #selector(swapVoiceAction), keyEquivalent: "g")
        menu.addItem(withTitle: "Toggle Master Microphone Mute", action: #selector(toggleMasterMicAction), keyEquivalent: "m")
        menu.addItem(withTitle: "Toggle Keep-Awake (Prevent Sleep & Screensaver)", action: #selector(toggleKeepAwakeAction), keyEquivalent: "k")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Tile Open Windows (Center Stage + Border)", action: #selector(tileNowAction), keyEquivalent: "t")
        menu.addItem(withTitle: "Move Command Center to Next Screen", action: #selector(moveToNextScreenAction), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit CF15T Command Center", action: #selector(quitAction), keyEquivalent: "q")

        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
        self.statusItem = item
    }

    @objc private func showMainWindowAction() {
        if viewModel.operatingMode == .fullControl && viewModel.isFullControlDocked {
            viewModel.expandFullControlMatrix()
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func switchToOrchestrateAction() {
        viewModel.setOperatingMode(.orchestrate)
    }

    @objc private func switchToFullControlAction() {
        viewModel.setOperatingMode(.fullControl, promptClamshellAuthIfNeeded: true)
    }

    @objc private func openSettingsAction() {
        if viewModel.operatingMode == .fullControl && viewModel.isFullControlDocked {
            viewModel.expandFullControlMatrix()
        }
        viewModel.isShowingSettingsSheet = true
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func swapVoiceAction() {
        viewModel.pingPongSwitchVoiceAssistants()
    }

    @objc private func toggleMasterMicAction() {
        viewModel.toggleSystemMasterMicMute()
    }

    @objc private func toggleKeepAwakeAction() {
        viewModel.keepAwakeEnabled.toggle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeepAwakeWorker.shared.stop()
    }

    @objc private func tileNowAction() {
        viewModel.applyRealScreenTilingNow()
    }

    @objc private func moveToNextScreenAction() {
        viewModel.moveCommandCenterToNextScreen()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}

@main
struct CF15TCommandCenterMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
