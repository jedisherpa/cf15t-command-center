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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func createAndShowMainWindow() {
        let contentView = CommandCenterMainView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)

        // Default to 1500x880 on main screen, or full visibleFrame on external 1920x1080 CF15T screen
        let screens = NSScreen.screens
        let targetScreen: NSScreen = {
            if screens.count > 1 {
                return screens.dropFirst().first(where: {
                    Int($0.frame.width) == 1920 && Int($0.frame.height) == 1080
                }) ?? screens[1]
            }
            return screens.first!
        }()

        let initialFrame: NSRect = {
            if screens.count > 1 {
                return targetScreen.visibleFrame
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
        window.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1.0)
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 1024, height: 640)
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
        menu.addItem(withTitle: "Swap Voice Assistant (Grok Bot ⇄ Dot)", action: #selector(swapVoiceAction), keyEquivalent: "g")
        menu.addItem(withTitle: "Toggle Master Microphone Mute", action: #selector(toggleMasterMicAction), keyEquivalent: "m")
        menu.addItem(withTitle: "Toggle Keep-Awake (Prevent Sleep & Screensaver)", action: #selector(toggleKeepAwakeAction), keyEquivalent: "k")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Tile Open Windows (Center Stage + Border)", action: #selector(tileNowAction), keyEquivalent: "t")
        menu.addItem(withTitle: "Move Command Center to CF15T Screen", action: #selector(moveToCF15TAction), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit CF15T Command Center", action: #selector(quitAction), keyEquivalent: "q")

        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
        self.statusItem = item
    }

    @objc private func showMainWindowAction() {
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

    @objc private func moveToCF15TAction() {
        viewModel.snapPanelToCF15T()
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
