import SwiftUI

// MARK: - 1. Prominent Dual-Mode Banner: ORCHESTRATE vs. FULL CONTROL (Works With Laptop Open or Closed)

struct DualOperatingModeSwitcherBanner: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        VStack(spacing: 6) {
            topModeSelectorRow
            activeModeQuickDeckRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(
                    viewModel.operatingMode == .fullControl
                        ? Color(red: 0.08, green: 0.16, blue: 0.14)
                        : Color(red: 0.06, green: 0.10, blue: 0.18)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    viewModel.operatingMode == .fullControl
                        ? Color(red: 0.15, green: 1.0, blue: 0.62).opacity(0.75)
                        : Color(red: 0.20, green: 0.86, blue: 1.0).opacity(0.65),
                    lineWidth: 1.5
                )
        )
    }

    private var topModeSelectorRow: some View {
        let isOrchestrate = (viewModel.operatingMode == .orchestrate)
        let isFullControl = (viewModel.operatingMode == .fullControl)

        return HStack(spacing: 10) {
            // Mode 1 Button: ORCHESTRATE (Main Screen Switcher)
            Button(action: {
                viewModel.setOperatingMode(.orchestrate)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 15, weight: .black))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MODE 1: ORCHESTRATE (MAIN SCREEN)")
                            .font(.system(size: 11.5, weight: .black, design: .monospaced))
                        Text("Programs on MacBook screen · Tap CF15T to switch/tile them")
                            .font(.system(size: 9.5, weight: .medium))
                            .opacity(0.85)
                    }
                    Spacer(minLength: 4)
                    Text(isOrchestrate ? "ACTIVE" : "TAP TO ACTIVATE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isOrchestrate ? Color.black.opacity(0.25) : Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isOrchestrate ? Color(red: 0.20, green: 0.86, blue: 1.0) : Color.white.opacity(0.08))
                )
                .foregroundColor(isOrchestrate ? .black : .white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Mode 2 Button: FULL CONTROL (Run Everything on CF15T — Laptop Open or Closed!)
            Button(action: {
                viewModel.setOperatingMode(.fullControl)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "ipad.landscape.badge.play")
                        .font(.system(size: 15, weight: .black))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MODE 2: FULL CONTROL (ON THIS TOUCHSCREEN)")
                            .font(.system(size: 11.5, weight: .black, design: .monospaced))
                        Text("Moves apps onto CF15T · Works with laptop open or closed in Ubers/trains")
                            .font(.system(size: 9.5, weight: .medium))
                            .opacity(0.85)
                    }
                    Spacer(minLength: 4)
                    Text(isFullControl ? "ACTIVE" : "TAP TO ACTIVATE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isFullControl ? Color.black.opacity(0.25) : Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isFullControl ? Color(red: 0.15, green: 1.0, blue: 0.62) : Color.white.opacity(0.08))
                )
                .foregroundColor(isFullControl ? .black : .white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Live Clamshell / Lid Sensor & Optional Battery Lid-Close Lock Button
            clamshellStatusControlButton
        }
    }

    private var clamshellStatusControlButton: some View {
        let lidClosed = viewModel.isLaptopLidClosed
        let lockArmed = viewModel.isClamshellBatterySleepDisabled

        return Button(action: {
            viewModel.toggleClamshellBatterySleepLock()
        }) {
            HStack(spacing: 7) {
                Image(systemName: lockArmed ? "lock.laptopcomputer" : "laptopcomputer.trianglebadge.exclamationmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(lockArmed ? Color(red: 0.15, green: 1.0, blue: 0.62) : Color(red: 1.0, green: 0.78, blue: 0.18))

                VStack(alignment: .leading, spacing: 1) {
                    Text(lidClosed ? "LID: CLOSED (CLAMSHELL)" : "LAPTOP LID: OPEN")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Text(lockArmed ? "SAFE TO CLOSE LID (BATTERY ON)" : "TAP TO ARM LID-CLOSED LOCK")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(lockArmed ? Color(red: 0.15, green: 1.0, blue: 0.62) : Color(red: 1.0, green: 0.78, blue: 0.18))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(lockArmed ? Color(red: 0.15, green: 1.0, blue: 0.62).opacity(0.16) : Color(red: 1.0, green: 0.78, blue: 0.18).opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(lockArmed ? Color(red: 0.15, green: 1.0, blue: 0.62) : Color(red: 1.0, green: 0.78, blue: 0.18), lineWidth: 1.2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var activeModeQuickDeckRow: some View {
        HStack(spacing: 8) {
            if viewModel.operatingMode == .orchestrate {
                // Orchestrate Tap Behavior Toggle: 1-Tap Single App Switcher vs Tile All
                HStack(spacing: 4) {
                    ForEach(OrchestrateTapActionMode.allCases) { actionMode in
                        let selected = (viewModel.orchestrateTapAction == actionMode)
                        Button(action: {
                            viewModel.orchestrateTapAction = actionMode
                            viewModel.saveDashboardPreferencesAsDefaults()
                        }) {
                            Text(actionMode.shortLabel.uppercased())
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(selected ? Color(red: 0.20, green: 0.86, blue: 1.0) : Color.white.opacity(0.08))
                                .foregroundColor(selected ? .black : .white.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("TAP TO SWITCH MAIN SCREEN:")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 0.20, green: 0.86, blue: 1.0))

                quickProgramTouchStrip

            } else {
                // FULL CONTROL Mode Quick Controls (when viewing Matrix in Full Control mode)
                Button(action: {
                    if let stage = viewModel.currentStageWindow {
                        viewModel.openWindowInFullControlCanvas(stage)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text("DOCK BAR & USE \(viewModel.currentStageWindow?.appName.uppercased() ?? "ACTIVE APP") ON CF15T")
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.15, green: 1.0, blue: 0.62))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.tileAllBelowFullControlDock()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "uiwindow.split.2x1")
                        Text("DOCK BAR & TILE ALL APPS ON CF15T")
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.20, green: 0.86, blue: 1.0))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.toggleFullControlTouchKeyboard()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "keyboard.fill")
                        Text(viewModel.showTouchKeyboardInDock ? "HIDE TOUCH KEYBOARD" : "⌨️ TOUCH KEYBOARD")
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(viewModel.showTouchKeyboardInDock ? Color(red: 1.0, green: 0.78, blue: 0.18) : Color.white.opacity(0.12))
                    .foregroundColor(viewModel.showTouchKeyboardInDock ? .black : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("TAP APP TO OPEN ON CF15T:")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))

                quickProgramTouchStrip
            }
        }
        if viewModel.showTouchKeyboardInDock && !viewModel.isFullControlDocked {
            TouchQuickKeyboardView(viewModel: viewModel)
        }
    }

    private var quickProgramTouchStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.visibleTiledWindows) { win in
                    let isStage = (viewModel.currentStageWindow?.id == win.id)
                    Button(action: {
                        viewModel.promoteWindowToStage(win)
                    }) {
                        HStack(spacing: 6) {
                            if let icon = win.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                            Text(win.appName.uppercased())
                                .font(.system(size: 10.5, weight: .black, design: .monospaced))
                                .foregroundColor(isStage ? .black : .white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    isStage
                                        ? Color(red: 1.0, green: 0.78, blue: 0.18)
                                        : Color.white.opacity(0.12)
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 2. Always-On-Top Touch Command Dock (Shown at Top of CF15T When Using Live Apps in FULL CONTROL)

struct FullControlDockedTopBarView: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        VStack(spacing: 6) {
            mainDockToolbarRow
            if viewModel.showTouchKeyboardInDock {
                TouchQuickKeyboardView(viewModel: viewModel)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.04, green: 0.06, blue: 0.10))
        .overlay(
            Rectangle()
                .fill(Color(red: 0.15, green: 1.0, blue: 0.62))
                .frame(height: 2.5),
            alignment: .bottom
        )
    }

    private var mainDockToolbarRow: some View {
        HStack(spacing: 7) {
            // 1. Return to ORCHESTRATE Mode (Moves programs back to Main MacBook Screen)
            Button(action: {
                viewModel.setOperatingMode(.orchestrate)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 13, weight: .black))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ORCHESTRATE")
                            .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        Text("TO MAC SCREEN")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(red: 0.20, green: 0.86, blue: 1.0))
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 2. Expand back to Full Command Center Matrix on CF15T
            Button(action: {
                viewModel.expandFullControlMatrix()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.3x2.fill")
                        .font(.system(size: 13, weight: .black))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MATRIX VIEW")
                            .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        Text("FULL DASHBOARD")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(red: 0.15, green: 1.0, blue: 0.62))
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 3. Tile All Apps on CF15T Below Dock
            Button(action: {
                viewModel.tileAllBelowFullControlDock()
            }) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("⊞ TILE ALL")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Text("ON CF15T")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 4. 1-Tap App Switcher on CF15T (Tap any app to fill the CF15T screen below the dock)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.visibleTiledWindows) { win in
                        let isCurrent = (viewModel.currentStageWindow?.id == win.id)
                        Button(action: {
                            viewModel.openWindowInFullControlCanvas(win)
                        }) {
                            HStack(spacing: 6) {
                                if let icon = win.appIcon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(win.appName.uppercased())
                                        .font(.system(size: 11, weight: .black, design: .monospaced))
                                        .foregroundColor(isCurrent ? .black : .white)
                                        .lineLimit(1)
                                    Text(isCurrent ? "ACTIVE BELOW" : "TAP TO FILL")
                                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(isCurrent ? .black.opacity(0.75) : .white.opacity(0.55))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(isCurrent ? Color(red: 1.0, green: 0.78, blue: 0.18) : Color.white.opacity(0.10))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 4)

            // 5. Voice Assistant Quick Buttons (Grok Bot / Dot)
            Button(action: {
                viewModel.toggleSlotMic("slotA")
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.slotA.isMicEnabled ? "mic.fill" : "mic.slash")
                    Text(viewModel.slotA.displayName.uppercased())
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(viewModel.slotA.isMicEnabled ? Color(red: 1.0, green: 0.38, blue: 0.18) : Color.white.opacity(0.10))
                .foregroundColor(viewModel.slotA.isMicEnabled ? .black : .white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.toggleSlotMic("slotB")
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.slotB.isMicEnabled ? "mic.fill" : "mic.slash")
                    Text(viewModel.slotB.displayName.uppercased())
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(viewModel.slotB.isMicEnabled ? Color(red: 0.15, green: 1.0, blue: 0.62) : Color.white.opacity(0.10))
                .foregroundColor(viewModel.slotB.isMicEnabled ? .black : .white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 6. Touch Scroll & Keyboard Buttons + Lid-Close Lock
            Button(action: {
                viewModel.scrollActiveApp(deltaY: 240)
            }) {
                Text("▲ SCRL")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.10))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.scrollActiveApp(deltaY: -240)
            }) {
                Text("▼ SCRL")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.10))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.toggleFullControlTouchKeyboard()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "keyboard.fill")
                    Text("KEYBOARD")
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(viewModel.showTouchKeyboardInDock ? Color(red: 1.0, green: 0.78, blue: 0.18) : Color(red: 0.20, green: 0.86, blue: 1.0))
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.toggleClamshellBatterySleepLock()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.isClamshellBatterySleepDisabled ? "lock.laptopcomputer" : "laptopcomputer")
                    Text(viewModel.isClamshellBatterySleepDisabled ? "LID LOCK ON" : "LID LOCK")
                }
                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(viewModel.isClamshellBatterySleepDisabled ? Color(red: 0.15, green: 1.0, blue: 0.62) : Color.white.opacity(0.10))
                .foregroundColor(viewModel.isClamshellBatterySleepDisabled ? .black : .white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 3. Built-In Touch QWERTY Keyboard & Quick-Send Deck (For Laptop-Closed Travel Use)

struct TouchQuickKeyboardView: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    private let row1 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
    private let row2 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "?", "/"]
    private let row3 = ["a", "s", "d", "f", "g", "h", "j", "k", "l", ":", "'", "."]
    private let row4 = ["z", "x", "c", "v", "b", "n", "m", ",", "!"]

    var body: some View {
        VStack(spacing: 5) {
            // Top Quick-Send & Action Keys Bar
            HStack(spacing: 6) {
                Text("TYPE TO \(viewModel.currentStageWindow?.appName.uppercased() ?? "ACTIVE APP"):")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))

                TextField("Tap keys below or type here, then tap SEND ⏎...", text: $viewModel.quickTypeText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .bold))
                    .onSubmit {
                        viewModel.sendQuickTypeText(pressReturn: true)
                    }

                Button(action: {
                    viewModel.sendQuickTypeText(pressReturn: true)
                }) {
                    Text("SEND ⏎")
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.15, green: 1.0, blue: 0.62))
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.sendSpecialKeyToActiveApp(keyCode: 36, label: "RETURN")
                }) {
                    Text("⏎ ENTER")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.sendSpecialKeyToActiveApp(keyCode: 51, label: "BACKSPACE")
                }) {
                    Text("⌫ BKSP")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.sendSpecialKeyToActiveApp(keyCode: 9, flags: .maskCommand, label: "⌘V PASTE")
                }) {
                    Text("⌘V PASTE")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.sendSpecialKeyToActiveApp(keyCode: 8, flags: .maskCommand, label: "⌘C COPY")
                }) {
                    Text("⌘C COPY")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.sendSpecialKeyToActiveApp(keyCode: 53, label: "ESC")
                }) {
                    Text("ESC")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Touch Key Rows (tapping any key types directly into the active app!)
            keyRowView(keys: row1)
            keyRowView(keys: row2)
            keyRowView(keys: row3)
            HStack(spacing: 4) {
                ForEach(row4, id: \.self) { k in
                    touchKeyButton(label: k.uppercased(), value: k)
                }
                Button(action: {
                    viewModel.appendTouchCharacter(" ")
                }) {
                    Text("SPACEBAR")
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.16))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func keyRowView(keys: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { k in
                touchKeyButton(label: k.uppercased(), value: k)
            }
        }
    }

    private func touchKeyButton(label: String, value: String) -> some View {
        Button(action: {
            viewModel.appendTouchCharacter(value)
        }) {
            Text(label)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
