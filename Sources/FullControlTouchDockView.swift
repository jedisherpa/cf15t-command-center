import SwiftUI

// MARK: - 1. Big, Calm, Nearsighted & Sensory-Friendly Mode + App Switcher Bar

struct DualOperatingModeSwitcherBanner: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        VStack(spacing: 8) {
            topModeSelectorRow
            activeModeQuickDeckRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    viewModel.operatingMode == .fullControl
                        ? Color(red: 0.06, green: 0.16, blue: 0.14)
                        : Color(red: 0.07, green: 0.11, blue: 0.19)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    viewModel.operatingMode == .fullControl
                        ? Color(red: 0.15, green: 0.92, blue: 0.58)
                        : Color(red: 0.25, green: 0.78, blue: 1.0),
                    lineWidth: 2.5
                )
        )
    }

    private var topModeSelectorRow: some View {
        let isOrchestrate = (viewModel.operatingMode == .orchestrate)
        let isFullControl = (viewModel.operatingMode == .fullControl)

        return HStack(spacing: 10) {
            // Mode 1 Button: LAPTOP + TOUCH (Orchestrate)
            Button(action: {
                viewModel.setOperatingMode(.orchestrate)
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "laptopcomputer.and.ipad")
                        .font(.system(size: 26, weight: .black))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("1. LAPTOP + TOUCH")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        Text("Switch apps on your laptop screen")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .opacity(0.90)
                    }
                    Spacer(minLength: 4)
                    if isOrchestrate {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .black))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 13)
                        .fill(isOrchestrate ? Color(red: 0.22, green: 0.78, blue: 1.0) : Color.white.opacity(0.10))
                )
                .foregroundColor(isOrchestrate ? .black : .white)
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(isOrchestrate ? Color.white : Color.white.opacity(0.20), lineWidth: isOrchestrate ? 2.5 : 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Mode 2 Button: TOUCHSCREEN ONLY (Full Control / Travel / Laptop Closed)
            Button(action: {
                viewModel.setOperatingMode(.fullControl)
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 26, weight: .black))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("2. TOUCHSCREEN ONLY")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        Text("Close laptop lid · Do everything here")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .opacity(0.90)
                    }
                    Spacer(minLength: 4)
                    if isFullControl {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .black))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 13)
                        .fill(isFullControl ? Color(red: 0.14, green: 0.88, blue: 0.54) : Color.white.opacity(0.10))
                )
                .foregroundColor(isFullControl ? .black : .white)
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(isFullControl ? Color.white : Color.white.opacity(0.20), lineWidth: isFullControl ? 2.5 : 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Big Nearsighted Layout & Text Size Controls (1 Big App / 2 Apps / 4 Apps / Big Text / Settings)
            nearsightedVisionControlsGroup
        }
    }

    private var nearsightedVisionControlsGroup: some View {
        HStack(spacing: 7) {
            // How many big apps on screen: 1 BIG | 2 SPLIT | 4 GRID
            ForEach([
                (count: 1, label: "1 BIG APP", icon: "rectangle.fill"),
                (count: 2, label: "2 APPS", icon: "rectangle.split.2x1.fill"),
                (count: 4, label: "4 APPS", icon: "rectangle.lefthalf.inset.filled")
            ], id: \.count) { preset in
                let isSelected = (viewModel.maxTiledWindows == preset.count)
                Button(action: {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        viewModel.maxTiledWindows = preset.count
                        if preset.count == 2 {
                            viewModel.tilingMode = .dualVoiceSplit
                        } else if preset.count >= 3 {
                            viewModel.tilingMode = .leftStagePerimeter
                        }
                        viewModel.saveDashboardPreferencesAsDefaults()
                    }
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: preset.icon)
                            .font(.system(size: 18, weight: .black))
                        Text(preset.label)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(isSelected ? Color(red: 1.0, green: 0.78, blue: 0.18) : Color.white.opacity(0.12))
                    )
                    .foregroundColor(isSelected ? .black : .white)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Giant Text Zoom Buttons (A- / A+)
            Button(action: {
                viewModel.feedFontScale = max(1.10, viewModel.feedFontScale - 0.18)
                viewModel.saveDashboardPreferencesAsDefaults()
            }) {
                Text("A-")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.14))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.feedFontScale = min(2.20, viewModel.feedFontScale + 0.18)
                viewModel.saveDashboardPreferencesAsDefaults()
            }) {
                Text("A+")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 1.0, green: 0.78, blue: 0.18))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Big Settings & Choose Apps Button
            Button(action: {
                viewModel.isShowingSettingsSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .black))
                    Text("APPS")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.16))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var activeModeQuickDeckRow: some View {
        HStack(spacing: 8) {
            quickProgramTouchStrip

            Spacer(minLength: 4)

            // View Mode Selector right in the top bar (No extra wasted bar below!)
            HStack(spacing: 5) {
                ForEach([
                    (mode: TileContentViewMode.splitVisualAndFeed, icon: "rectangle.split.2x1.fill", title: "SCREEN + WORDS"),
                    (mode: TileContentViewMode.simplifiedReader, icon: "text.bubble.fill", title: "BIG WORDS"),
                    (mode: TileContentViewMode.liveSmartZoom, icon: "photo.fill", title: "SCREEN ONLY")
                ], id: \.mode.id) { item in
                    let isSel = (viewModel.tileContentViewMode == item.mode)
                    Button(action: {
                        viewModel.tileContentViewMode = item.mode
                        viewModel.saveDashboardPreferencesAsDefaults()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .black))
                            Text(item.title)
                                .font(.system(size: 13, weight: .black, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isSel ? Color(red: 0.22, green: 0.78, blue: 1.0) : Color.white.opacity(0.12))
                        .foregroundColor(isSel ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.operatingMode == .fullControl {
                Button(action: {
                    viewModel.toggleFullControlTouchKeyboard()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "keyboard.fill")
                            .font(.system(size: 15, weight: .black))
                        Text(viewModel.showTouchKeyboardInDock ? "HIDE KEYBOARD" : "KEYBOARD")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(viewModel.showTouchKeyboardInDock ? Color(red: 1.0, green: 0.78, blue: 0.18) : Color.white.opacity(0.14))
                    .foregroundColor(viewModel.showTouchKeyboardInDock ? .black : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        if viewModel.showTouchKeyboardInDock && !viewModel.isFullControlDocked {
            TouchQuickKeyboardView(viewModel: viewModel)
        }
    }

    private var quickProgramTouchStrip: some View {
        let allShownWindows = viewModel.openWindows.filter {
            !viewModel.excludedWindowIDs.contains($0.id) && viewModel.isProgramDisplayed($0.appName)
        }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allShownWindows) { win in
                    let isStage = (viewModel.currentStageWindow?.id == win.id)
                    let isRec = viewModel.isDictating(for: win)
                    HStack(spacing: 5) {
                        Button(action: {
                            viewModel.promoteWindowToStage(win)
                        }) {
                            HStack(spacing: 8) {
                                if let icon = win.appIcon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 26, height: 26)
                                }
                                Text(win.appName)
                                    .font(.system(size: 16, weight: .black, design: .rounded))
                                    .foregroundColor(isStage ? .black : .white)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 12)
                            .padding(.trailing, 8)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Big 1-Tap Mic Button on every app pill
                        Button(action: {
                            viewModel.toggleVoiceDictation(for: win)
                        }) {
                            Image(systemName: isRec ? "stop.circle.fill" : "mic.fill")
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(.white)
                                .padding(7)
                                .background(
                                    Circle()
                                        .fill(isRec ? Color(red: 0.96, green: 0.22, blue: 0.26) : Color(red: 0.12, green: 0.72, blue: 0.44))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 5)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isStage
                                    ? Color(red: 1.0, green: 0.80, blue: 0.20)
                                    : Color.white.opacity(0.14)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isStage ? Color.white : Color.white.opacity(0.22), lineWidth: isStage ? 2.5 : 1)
                    )
                }
            }
        }
    }
}

// MARK: - 2. Per-Tile Live Voice Dictation Overlay & Nearsighted AAC Bottom Action Deck

struct PerTileVoiceDictationOverlay: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    @ObservedObject var dictationEngine = UniversalVoiceDictationEngine.shared
    let window: MonitoredWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.25, blue: 0.25))
                    .frame(width: 18, height: 18)

                Text("🎙️ LISTENING FOR \(window.appName.uppercased())")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                // Big Audio Level Bar
                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(Color(red: 0.15, green: 0.95, blue: 0.58))
                            .frame(width: max(12, barGeo.size.width * CGFloat(viewModel.dictationEngine.audioLevel)))
                    }
                }
                .frame(width: 140, height: 14)

                Spacer()

                Toggle("Auto-Send When Done Talking", isOn: $dictationEngine.autoSendOnSilence)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            // Large-Print Editable Transcript Box
            TextField(
                "Speak now — your words appear here in big print...",
                text: $dictationEngine.liveTranscript
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .onSubmit {
                viewModel.dictationEngine.stopAndSendDictation(pressReturn: true)
            }

            HStack(spacing: 12) {
                Button(action: {
                    viewModel.dictationEngine.stopAndSendDictation(pressReturn: true)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20, weight: .black))
                        Text("SEND NOW ⏎")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.14, green: 0.88, blue: 0.52))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.dictationEngine.stopAndSendDictation(pressReturn: false)
                }) {
                    HStack(spacing: 7) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 18, weight: .black))
                        Text("PASTE ONLY")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.24, green: 0.78, blue: 1.0))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    viewModel.dictationEngine.cancelDictation()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .black))
                        Text("CANCEL")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.20))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.07, green: 0.09, blue: 0.15).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 1.0, green: 0.32, blue: 0.32), lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.75), radius: 14)
    }
}

struct FullControlTileBottomDeck: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let window: MonitoredWindow
    let isCenterStage: Bool

    var body: some View {
        // Non-Verbal AAC 1-Tap Picture-Symbol Board shown on every tile!
        AACSymbolActionStrip(
            viewModel: viewModel,
            window: window,
            isCenterStage: isCenterStage
        )
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
