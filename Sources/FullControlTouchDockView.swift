import SwiftUI

// MARK: - 1. Prominent Dual-Mode Banner: ORCHESTRATE vs. FULL CONTROL (Standalone Touchscreen Cockpit)

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
                        ? Color(red: 0.05, green: 0.17, blue: 0.13)
                        : Color(red: 0.06, green: 0.10, blue: 0.18)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    viewModel.operatingMode == .fullControl
                        ? Color(red: 0.15, green: 1.0, blue: 0.62)
                        : Color(red: 0.20, green: 0.86, blue: 1.0).opacity(0.65),
                    lineWidth: viewModel.operatingMode == .fullControl ? 2.2 : 1.5
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
                        Text("MODE 1: ORCHESTRATE (MAIN SCREEN SWITCHER)")
                            .font(.system(size: 11.5, weight: .black, design: .monospaced))
                        Text("Tap tiles here to switch & tile programs on your open MacBook screen")
                            .font(.system(size: 9.5, weight: .medium))
                            .opacity(0.85)
                    }
                    Spacer(minLength: 4)
                    Text(isOrchestrate ? "ACTIVE" : "SWITCH TO ORCHESTRATE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .padding(.horizontal, 7)
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

            // Mode 2 Button: FULL CONTROL (Standalone Laptop-Closed / Travel Touchscreen Mode)
            Button(action: {
                viewModel.setOperatingMode(.fullControl)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "ipad.landscape.badge.play")
                        .font(.system(size: 15, weight: .black))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MODE 2: FULL CONTROL (STANDALONE · LAPTOP CLOSED READY)")
                            .font(.system(size: 11.5, weight: .black, design: .monospaced))
                        Text("Locks Command Center ON TOP · Full-screen app stations + 🎙️ Voice Dictate on every app")
                            .font(.system(size: 9.5, weight: .medium))
                            .opacity(0.85)
                    }
                    Spacer(minLength: 4)
                    Text(isFullControl ? "ACTIVE · ON TOP" : "SWITCH TO FULL CONTROL")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .padding(.horizontal, 7)
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
                    Text(lidClosed ? "LID: CLOSED (SHIELD ON)" : "LAPTOP LID: OPEN")
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

                Text("TAP TO SWITCH MAIN SCREEN (OR TAP 🎙️ ON ANY TILE TO DICTATE):")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 0.20, green: 0.86, blue: 1.0))

                quickProgramTouchStrip

            } else {
                // FULL CONTROL Mode Quick Controls (Standalone Cockpit Mode)
                HStack(spacing: 5) {
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))
                    Text("ALWAYS-ON-TOP SHIELD ACTIVE (CLOSING LAPTOP WILL NOT COVER COMMAND CENTER)")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(red: 0.15, green: 1.0, blue: 0.62).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 5))

                if let stage = viewModel.currentStageWindow {
                    Button(action: {
                        viewModel.toggleVoiceDictation(for: stage)
                    }) {
                        let isRec = viewModel.isDictating(for: stage)
                        HStack(spacing: 5) {
                            Image(systemName: isRec ? "stop.circle.fill" : "mic.fill")
                            Text(isRec ? "SEND DICTATION TO \(stage.appName.uppercased()) ⏎" : "🎙️ DICTATE TO #1 \(stage.appName.uppercased())")
                        }
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isRec ? Color(red: 1.0, green: 0.28, blue: 0.28) : Color(red: 1.0, green: 0.78, blue: 0.18))
                        .foregroundColor(isRec ? .white : .black)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

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

                if let stage = viewModel.currentStageWindow {
                    Button(action: {
                        viewModel.openWindowInFullControlCanvas(stage)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "macwindow")
                            Text("PEEK RAW \(stage.appName.uppercased()) WINDOW")
                        }
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.10))
                        .foregroundColor(.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)
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
                    let isRec = viewModel.isDictating(for: win)
                    HStack(spacing: 3) {
                        Button(action: {
                            viewModel.promoteWindowToStage(win)
                        }) {
                            HStack(spacing: 5) {
                                if let icon = win.appIcon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 15, height: 15)
                                }
                                Text(win.appName.uppercased())
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .foregroundColor(isStage ? .black : .white)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 8)
                            .padding(.trailing, 5)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Quick 1-Tap Mic Button on every chip in the top strip too!
                        Button(action: {
                            viewModel.toggleVoiceDictation(for: win)
                        }) {
                            Image(systemName: isRec ? "waveform.circle.fill" : "mic.fill")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(isRec ? .white : (isStage ? .black : Color(red: 0.15, green: 1.0, blue: 0.62)))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 4)
                                .background(
                                    Circle()
                                        .fill(isRec ? Color(red: 1.0, green: 0.22, blue: 0.22) : Color.black.opacity(0.22))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Voice dictate instruction to \(win.appName)")
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                isStage
                                    ? Color(red: 1.0, green: 0.78, blue: 0.18)
                                    : Color.white.opacity(0.12)
                            )
                    )
                }
            }
        }
    }
}

// MARK: - 2. Per-Tile Live Voice Dictation Overlay & Full-Control Bottom Action Deck

struct PerTileVoiceDictationOverlay: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    @ObservedObject var dictationEngine = UniversalVoiceDictationEngine.shared
    let window: MonitoredWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.22, blue: 0.22))
                    .frame(width: 11, height: 11)

                Text("🎙️ VOICE DICTATING TO \(window.appName.uppercased())")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                // Live Audio Level Bar
                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(Color(red: 0.15, green: 1.0, blue: 0.62))
                            .frame(width: max(8, barGeo.size.width * CGFloat(viewModel.dictationEngine.audioLevel)))
                    }
                }
                .frame(width: 90, height: 8)

                Spacer()

                Toggle("Auto-Send on Pause", isOn: $dictationEngine.autoSendOnSilence)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }

            // Live Editable Transcript Box
            TextField(
                "Speak now — your words for \(window.appName) appear here live (or type directly)...",
                text: $dictationEngine.liveTranscript
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, weight: .bold))
            .onSubmit {
                viewModel.dictationEngine.stopAndSendDictation(pressReturn: true)
            }

            HStack(spacing: 8) {
                Button(action: {
                    viewModel.dictationEngine.stopAndSendDictation(pressReturn: true)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "paperplane.fill")
                        Text("SEND & PRESS ENTER IN \(window.appName.uppercased()) ⏎")
                    }
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(red: 0.15, green: 1.0, blue: 0.62))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.dictationEngine.stopAndSendDictation(pressReturn: false)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("INSERT WITHOUT ENTER")
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(red: 0.20, green: 0.86, blue: 1.0))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    viewModel.dictationEngine.cancelDictation()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                        Text("CANCEL")
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.16))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.15).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 1.0, green: 0.30, blue: 0.30), lineWidth: 2.2)
        )
        .shadow(color: .black.opacity(0.65), radius: 10)
    }
}

struct FullControlTileBottomDeck: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let window: MonitoredWindow
    let isCenterStage: Bool

    private var draftBinding: Binding<String> {
        Binding(
            get: { viewModel.perTileInstructionDraft[window.id] ?? "" },
            set: { viewModel.perTileInstructionDraft[window.id] = $0 }
        )
    }

    var body: some View {
        let isRec = viewModel.isDictating(for: window)

        HStack(spacing: 6) {
            // 1. Primary Per-Tile Voice Dictate Button
            Button(action: {
                viewModel.toggleVoiceDictation(for: window)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: isRec ? "waveform.circle.fill" : "mic.fill")
                        .font(.system(size: isCenterStage ? 12 : 10, weight: .black))
                    Text(isRec ? "SEND VOICE ⏎" : (isCenterStage ? "🎙️ DICTATE TO \(window.appName.uppercased())" : "🎙️ DICTATE"))
                        .font(.system(size: isCenterStage ? 10.5 : 9, weight: .black, design: .monospaced))
                        .lineLimit(1)
                }
                .padding(.horizontal, isCenterStage ? 10 : 7)
                .padding(.vertical, isCenterStage ? 6 : 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isRec ? Color(red: 1.0, green: 0.25, blue: 0.25) : Color(red: 0.15, green: 1.0, blue: 0.62))
                )
                .foregroundColor(isRec ? .white : .black)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCenterStage {
                // 2. Inline Quick Instruction Input Field on Center Stage Tile
                TextField("Or type instruction for \(window.appName) & press Return ⏎...", text: draftBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .semibold))
                    .onSubmit {
                        viewModel.sendInstructionDraft(for: window, pressReturn: true)
                    }

                Button(action: {
                    viewModel.sendInstructionDraft(for: window, pressReturn: true)
                }) {
                    Text("SEND ⏎")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color(red: 1.0, green: 0.78, blue: 0.18))
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer(minLength: 2)
            }

            // 3. Per-Tile Scroll Up / Scroll Down Buttons
            Button(action: {
                viewModel.scrollWindowInBackground(window, deltaY: 220)
            }) {
                Text("▲")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.14))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Scroll \(window.appName) Up")

            Button(action: {
                viewModel.scrollWindowInBackground(window, deltaY: -220)
            }) {
                Text("▼")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.14))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Scroll \(window.appName) Down")

            if isCenterStage {
                Button(action: {
                    viewModel.openWindowInFullControlCanvas(window)
                }) {
                    Text("PEEK APP")
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(Color(red: 0.20, green: 0.86, blue: 1.0))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(red: 0.04, green: 0.11, blue: 0.10).opacity(0.95))
    }
}

// MARK: - 3. Always-On-Top Touch Command Dock (When Peeking at a Raw App Window in FULL CONTROL)

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
            // 1. Expand back to Full Command Center Matrix on CF15T
            Button(action: {
                viewModel.expandFullControlMatrix()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.3x2.fill")
                        .font(.system(size: 13, weight: .black))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("BACK TO COMMAND CENTER")
                            .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        Text("FULL MATRIX VIEW")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.15, green: 1.0, blue: 0.62))
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 2. Return to ORCHESTRATE Mode
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

            // 3. 1-Tap App Switcher + Per-App Dictation
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
                                    Text(isCurrent ? "ACTIVE BELOW" : "TAP TO PEEK")
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

            if let stage = viewModel.currentStageWindow {
                Button(action: {
                    viewModel.toggleVoiceDictation(for: stage)
                }) {
                    let isRec = viewModel.isDictating(for: stage)
                    HStack(spacing: 4) {
                        Image(systemName: isRec ? "waveform.circle.fill" : "mic.fill")
                        Text(isRec ? "SEND ⏎" : "🎙️ DICTATE")
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isRec ? Color(red: 1.0, green: 0.25, blue: 0.25) : Color(red: 0.15, green: 1.0, blue: 0.62))
                    .foregroundColor(isRec ? .white : .black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

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
        }
    }
}

// MARK: - 4. Built-In Touch QWERTY Keyboard & Quick-Send Deck

struct TouchQuickKeyboardView: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    private let row1 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
    private let row2 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "?", "/"]
    private let row3 = ["a", "s", "d", "f", "g", "h", "j", "k", "l", ":", "'", "."]
    private let row4 = ["z", "x", "c", "v", "b", "n", "m", ",", "!"]

    var body: some View {
        VStack(spacing: 5) {
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
