import SwiftUI
import AppKit

struct CommandCenterMainView: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    private var totalSystemCPULoad: Double {
        let agentSum = viewModel.agentSnapshots.reduce(0.0) { $0 + $1.cpuPercent }
        let taskSum = viewModel.runningTasks.prefix(8).reduce(0.0) { $0 + $1.cpuPercent }
        return max(agentSum, taskSum)
    }

    private var currentGearNumber: Int {
        switch viewModel.tilingMode {
        case .centerStageBorder: return 1
        case .goldenFibonacciSpiral: return 2
        case .leftStagePerimeter: return 3
        case .equalSimultaneousGrid: return 4
        case .dualVoiceSplit: return 5
        }
    }

    var body: some View {
        let activeVoiceName = (viewModel.activeVoiceSlotID == "slotA")
            ? viewModel.slotA.displayName
            : viewModel.slotB.displayName
        let isMicLive = (viewModel.slotA.isMicEnabled || viewModel.slotB.isMicEnabled) && !viewModel.systemMicMuted

        Group {
            if viewModel.operatingMode == .fullControl && viewModel.isFullControlDocked {
                FullControlDockedTopBarView(viewModel: viewModel)
            } else {
                VStack(spacing: 8) {
                    // 1. Big Nearsighted & Sensory-Friendly Mode + App Switcher Bar
                    DualOperatingModeSwitcherBanner(viewModel: viewModel)

                    // 2. Main Interactive Program Canvas (100% Width by Default for Big Nearsighted Cards)
                    GeometryReader { geo in
                        let totalW = geo.size.width
                        let leftWidth = viewModel.isRightPanelCollapsed
                            ? totalW
                            : max(540, min(totalW - 260, floor(totalW * CGFloat(viewModel.matrixWidthRatio))))

                        HStack(spacing: 8) {
                            WindowTilingArenaPanel(viewModel: viewModel, currentGear: currentGearNumber)
                                .frame(width: leftWidth)

                            if !viewModel.isRightPanelCollapsed {
                                AgentAndTasksSidePanel(viewModel: viewModel)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    // 3. Calm, Large-Print Bottom Status & Audio Helper Bar
                    BottomStatusStrip(viewModel: viewModel)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.04, green: 0.06, blue: 0.11))
            }
        }
        .sheet(isPresented: $viewModel.isShowingVoiceSlotEditor) {
            VoiceSlotEditorSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingSettingsSheet) {
            CommandCenterSettingsSheet(viewModel: viewModel)
        }
    }
}

// MARK: - 1. Supercar Instrument Cluster & Pit-Radio Deck

struct TopVoiceAndSystemBar: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let totalCPULoad: Double
    let currentGear: Int

    var body: some View {
        HStack(spacing: 10) {
            // Left Wing: Channel 01 (Grok Bot)
            VoiceAssistantDeckCard(
                channelTag: "CH-01 // PRIMARY VOICE",
                slot: viewModel.slotA,
                isActiveSlot: viewModel.activeVoiceSlotID == "slotA",
                accentColor: Color(red: 1.0, green: 0.36, blue: 0.14),
                onActivate: {
                    viewModel.switchToVoiceSlot("slotA", toggleMicIfExclusive: false)
                },
                onToggleMic: {
                    viewModel.toggleSlotMic("slotA")
                }
            )

            // Center Instrument Cluster: Twin Arc Gauges + 5-Axis Workload Radar + Voice Swap Paddle
            CenterTelemetryCluster(
                viewModel: viewModel,
                totalCPULoad: totalCPULoad,
                currentGear: currentGear
            )

            // Right Wing: Channel 02 (Dot)
            VoiceAssistantDeckCard(
                channelTag: "CH-02 // CO-PILOT VOICE",
                slot: viewModel.slotB,
                isActiveSlot: viewModel.activeVoiceSlotID == "slotB",
                accentColor: Color(red: 0.12, green: 0.96, blue: 0.68),
                onActivate: {
                    viewModel.switchToVoiceSlot("slotB", toggleMicIfExclusive: false)
                },
                onToggleMic: {
                    viewModel.toggleSlotMic("slotB")
                }
            )

            // Far-Right ECU Switch Box (Hardware Mic Kill + Keep-Awake + Cursor Snap)
            SystemMicAndTouchGuardBox(viewModel: viewModel)
                .frame(width: 335)
        }
        .frame(height: 92)
    }
}

struct CenterTelemetryCluster: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let totalCPULoad: Double
    let currentGear: Int

    private var grokActivityWeight: Double {
        let isTarget = viewModel.activeVoiceSlotID == "slotA"
        let cpu = viewModel.agentSnapshots.first(where: { $0.platform == .grokBot })?.cpuPercent ?? 0
        return min(1.0, (isTarget ? 0.65 : 0.25) + cpu / 25.0 + (viewModel.slotA.isMicEnabled ? 0.35 : 0))
    }

    private var dotActivityWeight: Double {
        let isTarget = viewModel.activeVoiceSlotID == "slotB"
        let cpu = viewModel.agentSnapshots.first(where: { $0.platform == .dot || $0.platform == .chatGPT })?.cpuPercent ?? 0
        return min(1.0, (isTarget ? 0.65 : 0.25) + cpu / 25.0 + (viewModel.slotB.isMicEnabled ? 0.35 : 0))
    }

    private var otherAIWeight: Double {
        let cpu = viewModel.agentSnapshots
            .filter { $0.platform != .grokBot && $0.platform != .dot }
            .reduce(0.0) { $0 + $1.cpuPercent }
        return min(1.0, 0.22 + cpu / 35.0)
    }

    private var micWeight: Double {
        guard !viewModel.systemMicMuted && (viewModel.slotA.isMicEnabled || viewModel.slotB.isMicEnabled) else {
            return 0.18
        }
        return min(1.0, max(0.35, Double(viewModel.systemMicVolume)))
    }

    var body: some View {
        HStack(spacing: 8) {
            // Left Gauge: Total AI & System CPU %
            CockpitArcGaugeView(
                title: "AI CPU",
                valueText: String(format: "%.0f%%", min(99, totalCPULoad)),
                unitText: "LOAD",
                progress: min(1.0, max(0.05, totalCPULoad / 80.0)),
                accentColor: Color(red: 0.18, green: 0.85, blue: 1.0),
                redlineColor: Color(red: 1.0, green: 0.25, blue: 0.20)
            )

            // Live 5-Axis Barycentric Workload Balance Radar (GROK / DOT / AI / MIC / APPS)
            WorkloadBalanceRadarView(
                grokWeight: grokActivityWeight,
                dotWeight: dotActivityWeight,
                claudeCodexWeight: otherAIWeight,
                voiceMicWeight: micWeight,
                appsWeight: min(1.0, Double(viewModel.openWindows.count) / 10.0)
            )

            // Center Voice Swap Button + Active Layout Mode Indicator
            Button(action: {
                viewModel.pingPongSwitchVoiceAssistants()
            }) {
                VStack(spacing: 3) {
                    HStack(spacing: 5) {
                        Text("LAYOUT")
                            .font(.system(size: 8.5, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        Text("G\(currentGear)")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.80, blue: 0.15))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 14, weight: .black))
                        Text("SWAP VOICE")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.78, blue: 0.15),
                                Color(red: 1.0, green: 0.45, blue: 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(CockpitChamferShape(topLeftCut: 7, topRightCut: 7, bottomRightCut: 7, bottomLeftCut: 7))

                    Text("\(viewModel.slotA.displayName.uppercased()) ⇄ \(viewModel.slotB.displayName.uppercased())")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 0.20, green: 0.95, blue: 0.70))
                        .lineLimit(1)
                }
                .frame(width: 132, height: 78)
            }
            .buttonStyle(.plain)

            // Right Gauge: Hardware Microphone Gain %
            CockpitArcGaugeView(
                title: "MIC GAIN",
                valueText: viewModel.systemMicMuted ? "MUTE" : "\(Int(viewModel.systemMicVolume * 100))%",
                unitText: viewModel.systemMicMuted ? "OFF" : "LIVE",
                progress: viewModel.systemMicMuted ? 0.0 : Double(viewModel.systemMicVolume),
                accentColor: Color(red: 0.15, green: 0.96, blue: 0.62),
                redlineColor: Color(red: 1.0, green: 0.65, blue: 0.12)
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 92)
        .background(
            Color(red: 0.07, green: 0.09, blue: 0.14)
        )
        .clipShape(CockpitChamferShape(topLeftCut: 16, topRightCut: 16, bottomRightCut: 16, bottomLeftCut: 16))
        .overlay(
            CockpitChamferShape(topLeftCut: 16, topRightCut: 16, bottomRightCut: 16, bottomLeftCut: 16)
                .stroke(Color(red: 0.25, green: 0.82, blue: 1.0).opacity(0.45), lineWidth: 1.5)
        )
    }
}

struct VoiceAssistantDeckCard: View {
    let channelTag: String
    let slot: VoiceAssistantConfig
    let isActiveSlot: Bool
    let accentColor: Color
    let onActivate: () -> Void
    let onToggleMic: () -> Void

    var body: some View {
        let shape = CockpitChamferShape(topLeftCut: 14, topRightCut: 14, bottomRightCut: 14, bottomLeftCut: 14)

        HStack(spacing: 8) {
            // Left Racing Stripe
            Rectangle()
                .fill(accentColor)
                .frame(width: 5)
                .shadow(color: accentColor, radius: 6)

            // Main Comms Selector Button
            Button(action: onActivate) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(channelTag)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(accentColor)

                        if isActiveSlot {
                            Text("ON-AIR STAGE")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentColor)
                                .foregroundColor(.black)
                        }
                    }

                    Text(slot.displayName.uppercased())
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        SegmentedTelemetryBar(
                            fraction: slot.isMicEnabled ? 0.92 : (isActiveSlot ? 0.45 : 0.15),
                            segmentCount: 8,
                            activeColor: accentColor
                        )
                        Text(slot.targetAppName.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Right Arcade PTT / Mic Trigger
            Button(action: onToggleMic) {
                VStack(spacing: 4) {
                    Image(systemName: slot.isMicEnabled ? "waveform.badge.mic" : "mic.slash.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(slot.isMicEnabled ? .black : .white)

                    Text(slot.isMicEnabled ? "TX LIVE" : "RADIO OFF")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(slot.isMicEnabled ? .black : .white.opacity(0.9))
                }
                .frame(width: 92, height: 74)
                .background(
                    slot.isMicEnabled
                        ? Color(red: 0.12, green: 1.0, blue: 0.58)
                        : Color(red: 0.92, green: 0.18, blue: 0.24).opacity(0.32)
                )
                .clipShape(CockpitChamferShape(topLeftCut: 10, topRightCut: 10, bottomRightCut: 10, bottomLeftCut: 10))
                .overlay(
                    CockpitChamferShape(topLeftCut: 10, topRightCut: 10, bottomRightCut: 10, bottomLeftCut: 10)
                        .stroke(
                            slot.isMicEnabled ? Color.white : Color(red: 1.0, green: 0.32, blue: 0.36).opacity(0.75),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: slot.isMicEnabled ? Color(red: 0.12, green: 1.0, blue: 0.58).opacity(0.65) : .clear, radius: 8)
                .padding(.trailing, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.10, blue: 0.16))
        .clipShape(shape)
        .overlay(
            shape.stroke(isActiveSlot ? accentColor : Color.white.opacity(0.16), lineWidth: isActiveSlot ? 2.4 : 1.0)
        )
        .shadow(color: isActiveSlot ? accentColor.opacity(0.35) : .clear, radius: 8)
    }
}

struct SystemMicAndTouchGuardBox: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        let shape = CockpitChamferShape(topLeftCut: 14, topRightCut: 14, bottomRightCut: 14, bottomLeftCut: 14)

        HStack(spacing: 8) {
            // Hardware Master Kill Switch
            Button(action: {
                viewModel.toggleSystemMasterMicMute()
            }) {
                VStack(spacing: 3) {
                    Image(systemName: viewModel.systemMicMuted ? "xmark.octagon.fill" : "bolt.shield.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(viewModel.systemMicMuted ? Color(red: 1.0, green: 0.28, blue: 0.28) : Color(red: 0.15, green: 0.98, blue: 0.60))
                    Text(viewModel.systemMicMuted ? "KILL MIC" : "ARMED")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(width: 72, height: 74)
                .background(Color.black.opacity(0.45))
                .clipShape(CockpitChamferShape(topLeftCut: 8, topRightCut: 8, bottomRightCut: 8, bottomLeftCut: 8))
                .overlay(
                    CockpitChamferShape(topLeftCut: 8, topRightCut: 8, bottomRightCut: 8, bottomLeftCut: 8)
                        .stroke(viewModel.systemMicMuted ? Color.red.opacity(0.7) : Color(red: 0.15, green: 0.98, blue: 0.60).opacity(0.6), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("GAIN // \(viewModel.audioInputDeviceName.uppercased())")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(viewModel.systemMicVolume * 100))%")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 0.15, green: 0.98, blue: 0.60))
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.systemMicVolume) },
                        set: { viewModel.updateMicVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .tint(Color(red: 0.15, green: 0.98, blue: 0.60))

                // 3 Dashboard Toggle Switches
                HStack(spacing: 5) {
                    Button(action: { viewModel.isShowingVoiceSlotEditor = true }) {
                        Text("TUNE A/B")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.keepAwakeEnabled.toggle() }) {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                            Text(viewModel.keepAwakeEnabled ? "IGNITION ON" : "SLEEP OK")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                        }
                        .foregroundColor(viewModel.keepAwakeEnabled ? .black : .white.opacity(0.75))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            viewModel.keepAwakeEnabled
                                ? Color(red: 1.0, green: 0.78, blue: 0.15)
                                : Color.white.opacity(0.10)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.cursorSnapbackEnabled.toggle() }) {
                        Text(viewModel.cursorSnapbackEnabled ? "TCS: SNAP" : "TCS: OFF")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(viewModel.cursorSnapbackEnabled ? .black : .white.opacity(0.75))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(
                                viewModel.cursorSnapbackEnabled
                                    ? Color(red: 0.20, green: 0.86, blue: 1.0)
                                    : Color.white.opacity(0.10)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.10, blue: 0.16))
        .clipShape(shape)
        .overlay(
            shape.stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - 2. Multi-Cam Viewport Matrix (Center Stage + Perimeter Border)

struct WindowTilingArenaPanel: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    @ObservedObject var speechEngine = SensoryFriendlySpeechEngine.shared
    let currentGear: Int

    var body: some View {
        VStack(spacing: 8) {
            // Simple, Large-Print View Style & Audio Helper Bar
            HStack(spacing: 10) {
                Text("HOW TO SHOW APPS:")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))

                ForEach([
                    (mode: TileContentViewMode.splitVisualAndFeed, icon: "rectangle.split.2x1.fill", title: "PICTURE + WORDS"),
                    (mode: TileContentViewMode.simplifiedReader, icon: "text.bubble.fill", title: "BIG WORDS ONLY"),
                    (mode: TileContentViewMode.liveSmartZoom, icon: "photo.fill", title: "PICTURE ONLY")
                ], id: \.mode.id) { item in
                    let isSel = (viewModel.tileContentViewMode == item.mode)
                    Button(action: {
                        viewModel.tileContentViewMode = item.mode
                        viewModel.saveDashboardPreferencesAsDefaults()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 15, weight: .black))
                            Text(item.title)
                                .font(.system(size: 14, weight: .black, design: .rounded))
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(isSel ? Color(red: 0.22, green: 0.78, blue: 1.0) : Color.white.opacity(0.12))
                        .foregroundColor(isSel ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Toggle whether tapping AAC picture cards speaks aloud confirmation
                Button(action: {
                    speechEngine.speakAACConfirmations.toggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: speechEngine.speakAACConfirmations ? "speaker.wave.3.fill" : "speaker.slash.fill")
                            .font(.system(size: 16, weight: .black))
                        Text(speechEngine.speakAACConfirmations ? "VOICE FEEDBACK: ON" : "VOICE FEEDBACK: OFF")
                            .font(.system(size: 13.5, weight: .black, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(speechEngine.speakAACConfirmations ? Color(red: 0.14, green: 0.85, blue: 0.52).opacity(0.25) : Color.white.opacity(0.10))
                    .foregroundColor(speechEngine.speakAACConfirmations ? Color(red: 0.20, green: 0.96, blue: 0.62) : .white.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(speechEngine.speakAACConfirmations ? Color(red: 0.14, green: 0.85, blue: 0.52) : Color.clear, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Interactive Center Stage + Perimeter Border Canvas
            GeometryReader { arenaGeo in
                CenterStagePerimeterCanvas(
                    viewModel: viewModel,
                    canvasSize: arenaGeo.size
                )
            }
        }
        .padding(10)
        .background(Color(red: 0.06, green: 0.09, blue: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.16), lineWidth: 1.5)
        )
    }
}

struct ProgramRosterAndAdjustmentStrip: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        let openPrograms = viewModel.allSelectablePrograms.filter { $0.isCurrentlyOpen }

        HStack(spacing: 6) {
            // Label showing how many programs are displayed
            Button(action: {
                viewModel.isShowingSettingsSheet = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 10, weight: .black))
                    Text("SHOWN (\(viewModel.visibleTiledWindows.count)):")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                }
                .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.18))
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            // Scrollable row of Open Program Pills (click any program to show/hide it on the matrix!)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(openPrograms) { prog in
                        let isShown = viewModel.isProgramDisplayed(prog.id)
                        Button(action: {
                            viewModel.toggleProgramDisplayed(prog.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isShown ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 9.5, weight: .black))
                                    .foregroundColor(isShown ? Color(red: 0.15, green: 1.0, blue: 0.62) : .white.opacity(0.35))

                                if let icon = prog.appIcon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 13, height: 13)
                                }

                                Text(prog.displayName.uppercased())
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundColor(isShown ? .white : .white.opacity(0.45))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isShown ? Color(red: 0.10, green: 0.22, blue: 0.22) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isShown ? Color(red: 0.15, green: 1.0, blue: 0.62).opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 4)

            // Inline Visual Mode Selector (Split View | Live Screen | Text Feed)
            HStack(spacing: 3) {
                ForEach(TileContentViewMode.allCases) { mode in
                    let isSel = (viewModel.tileContentViewMode == mode)
                    Button(action: {
                        viewModel.tileContentViewMode = mode
                    }) {
                        Text(mode.shortLabel.uppercased())
                            .font(.system(size: 8.5, weight: .black, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(isSel ? Color(red: 0.20, green: 0.88, blue: 1.0) : Color.white.opacity(0.07))
                            .foregroundColor(isSel ? .black : .white.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Inline Stage Size Adjustment
            HStack(spacing: 4) {
                Text("STAGE \(Int(viewModel.stageScaleFactor * 100))%")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                Slider(value: $viewModel.stageScaleFactor, in: 0.42...0.78)
                    .frame(width: 68)
            }

            // Inline Text Size Zoom Buttons (A- / A+)
            HStack(spacing: 2) {
                Button(action: {
                    viewModel.feedFontScale = max(0.85, viewModel.feedFontScale - 0.10)
                }) {
                    Text("A-")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.feedFontScale = min(1.55, viewModel.feedFontScale + 0.10)
                }) {
                    Text("A+")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct CenterStagePerimeterCanvas: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let canvasSize: CGSize

    var body: some View {
        let windows = viewModel.visibleTiledWindows
        if windows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 42))
                    .foregroundColor(Color(red: 0.20, green: 0.86, blue: 1.0))
                Text("NO PROGRAMS SELECTED FOR DISPLAY")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                HStack(spacing: 10) {
                    Button(action: {
                        viewModel.selectAllPrograms()
                        viewModel.refreshAll(captureImages: true)
                    }) {
                        Text("SHOW ALL OPEN PROGRAMS")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color(red: 0.15, green: 1.0, blue: 0.62))
                            .clipShape(CockpitChamferShape(topLeftCut: 8, topRightCut: 8, bottomRightCut: 8, bottomLeftCut: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        viewModel.isShowingSettingsSheet = true
                    }) {
                        Text("OPEN SETTINGS & CHOOSE PROGRAMS")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color(red: 1.0, green: 0.78, blue: 0.18))
                            .clipShape(CockpitChamferShape(topLeftCut: 8, topRightCut: 8, bottomRightCut: 8, bottomLeftCut: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let orderedWindows: [MonitoredWindow] = {
                if let stage = viewModel.currentStageWindow {
                    return [stage] + viewModel.currentBorderWindows
                }
                return windows
            }()

            let rectCanvas = CGRect(origin: .zero, size: canvasSize)
            let layoutRects = WindowTilingEngine.shared.computeLayoutFrames(
                count: orderedWindows.count,
                canvas: rectCanvas,
                mode: viewModel.tilingMode,
                gap: 10,
                stageScale: CGFloat(viewModel.stageScaleFactor)
            )

            let totalArea = max(1.0, Double(layoutRects.reduce(0.0) { $0 + ($1.width * $1.height) }))
            let telemetryNodes: [WindowTelemetryNode] = orderedWindows.enumerated().compactMap { index, win in
                guard index < layoutRects.count else { return nil }
                let r = layoutRects[index]
                let areaPct = Double(r.width * r.height) / totalArea * 100.0
                let cpuPct = viewModel.cpuPercent(for: win)
                let voiceInfo = viewModel.voiceSlotMatch(for: win)
                return WindowTelemetryNode(
                    window: win,
                    rect: r,
                    rankIndex: index,
                    areaPercent: areaPct,
                    cpuPercent: cpuPct,
                    voiceChannelCode: voiceInfo?.channelCode,
                    voiceDisplayName: voiceInfo?.displayName,
                    isActiveVoiceTarget: voiceInfo?.isActiveTarget ?? false,
                    isMicLive: voiceInfo?.isMicLive ?? false
                )
            }

            ZStack(alignment: .topLeading) {
                ForEach(telemetryNodes, id: \.window.id) { node in
                    let isStage = (node.rankIndex == 0 && viewModel.tilingMode != .equalSimultaneousGrid)
                    InteractiveWindowTileCard(
                        viewModel: viewModel,
                        node: node,
                        isCenterStage: isStage,
                        viewMode: viewModel.tileContentViewMode,
                        fontScale: viewModel.feedFontScale,
                        onTapPromote: {
                            viewModel.promoteWindowToStage(node.window)
                        },
                        onFocusOnly: {
                            WindowTilingEngine.shared.focusWindow(node.window)
                        },
                        onExclude: {
                            viewModel.toggleProgramDisplayed(node.window.appName)
                        }
                    )
                    .frame(width: max(80, node.rect.width), height: max(60, node.rect.height))
                    .position(x: node.rect.midX, y: node.rect.midY)
                    .animation(.spring(response: 0.32, dampingFraction: 0.80), value: node.rect)
                }

                // Optional Floating Flow Lines (OFF by default so orange dotted CPU lines don't obscure windows!)
                if viewModel.showFloatingFlowLines {
                    MeaningfulGeometryOverlay(
                        nodes: telemetryNodes,
                        mode: viewModel.tilingMode,
                        canvasSize: canvasSize,
                        micVolume: viewModel.systemMicVolume
                    )
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
    }
}

struct InteractiveWindowTileCard: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    @ObservedObject var dictationEngine = UniversalVoiceDictationEngine.shared
    @ObservedObject var speechEngine = SensoryFriendlySpeechEngine.shared
    let node: WindowTelemetryNode
    let isCenterStage: Bool
    let viewMode: TileContentViewMode
    let fontScale: Double
    let onTapPromote: () -> Void
    let onFocusOnly: () -> Void
    let onExclude: () -> Void

    private var window: MonitoredWindow { node.window }

    private var appThemeColor: Color {
        if let plat = window.platform {
            return plat.accentColor
        }
        let lower = window.appName.lowercased()
        if lower.contains("chrome") || lower.contains("safari") {
            return Color(red: 0.24, green: 0.76, blue: 1.0)
        } else if lower.contains("whatsapp") {
            return Color(red: 0.16, green: 0.92, blue: 0.52)
        } else if lower.contains("signal") {
            return Color(red: 0.42, green: 0.62, blue: 1.0)
        } else if lower.contains("music") || lower.contains("spotify") {
            return Color(red: 1.0, green: 0.38, blue: 0.64)
        } else if lower.contains("settings") {
            return Color(red: 1.0, green: 0.80, blue: 0.22)
        } else if lower.contains("finder") {
            return Color(red: 0.28, green: 0.85, blue: 1.0)
        }
        return Color(red: 0.30, green: 0.82, blue: 1.0)
    }

    var body: some View {
        let accent = appThemeColor
        let tileShape = RoundedRectangle(cornerRadius: 18)
        let isDictatingThisTile = viewModel.isDictating(for: window)
        let isReadingThisTile = (speechEngine.isSpeaking && speechEngine.speakingWindowID == window.id)

        ZStack(alignment: .bottomLeading) {
            // 1. High-Clarity Program Visual + Large-Print Message/Response Feed
            GeometryReader { cardGeo in
                ZStack {
                    Color(red: 0.05, green: 0.08, blue: 0.14)

                    SimplifiedAppContentView(
                        window: window,
                        accent: accent,
                        isCenterStage: isCenterStage,
                        viewMode: viewMode,
                        fontScale: fontScale,
                        cardSize: cardGeo.size
                    )
                    .padding(.top, isCenterStage ? 58 : 48)
                    .padding(.bottom, isCenterStage ? 62 : 50)
                    .padding(.horizontal, isCenterStage ? 12 : 8)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onTapPromote()
                }
            }

            // 2. Giant Nearsighted Top Header + Bottom Non-Verbal AAC Picture-Symbol Bar
            VStack(alignment: .leading, spacing: 0) {
                // TOP BAR: Huge App Icon + Bold App Name + READ ALOUD Button + TALK Mic Button + MAKE BIG Button
                HStack(spacing: isCenterStage ? 10 : 7) {
                    Button(action: onTapPromote) {
                        HStack(spacing: 8) {
                            if isCenterStage {
                                Text("★ MAIN APP")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 1.0, green: 0.82, blue: 0.20))
                                    .foregroundColor(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                            }

                            if let icon = window.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: isCenterStage ? 32 : 24, height: isCenterStage ? 32 : 24)
                            }

                            Text(window.appName)
                                .font(.system(size: isCenterStage ? 22 : 17, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    // 1-TAP READ ALOUD BUTTON (Speaks the app's messages/responses aloud for non-verbal & nearsighted learners)
                    Button {
                        speechEngine.toggleReadAloud(for: window)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isReadingThisTile ? "stop.circle.fill" : "speaker.wave.3.fill")
                                .font(.system(size: isCenterStage ? 18 : 14, weight: .black))
                            Text(isReadingThisTile ? "STOP READING" : (isCenterStage ? "🔊 READ TO ME" : "🔊 READ"))
                                .font(.system(size: isCenterStage ? 15.5 : 13, weight: .black, design: .rounded))
                        }
                        .padding(.horizontal, isCenterStage ? 14 : 10)
                        .padding(.vertical, isCenterStage ? 9 : 7)
                        .background(
                            isReadingThisTile
                                ? Color(red: 1.0, green: 0.78, blue: 0.18)
                                : Color(red: 0.24, green: 0.78, blue: 1.0)
                        )
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 1-TAP WHISPER VOICE DICTATION BUTTON
                    Button {
                        viewModel.toggleVoiceDictation(for: window)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isDictatingThisTile ? "stop.circle.fill" : "mic.fill")
                                .font(.system(size: isCenterStage ? 18 : 14, weight: .black))
                            Text(isDictatingThisTile ? "SEND VOICE ⏎" : (isCenterStage ? "🎙️ TALK" : "🎙️ TALK"))
                                .font(.system(size: isCenterStage ? 15.5 : 13, weight: .black, design: .rounded))
                        }
                        .padding(.horizontal, isCenterStage ? 14 : 10)
                        .padding(.vertical, isCenterStage ? 9 : 7)
                        .background(
                            isDictatingThisTile
                                ? Color(red: 0.98, green: 0.24, blue: 0.30)
                                : Color(red: 0.14, green: 0.88, blue: 0.54)
                        )
                        .foregroundColor(isDictatingThisTile ? .white : .black)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // On side tiles: Big "MAKE BIG" button so user knows they can expand it
                    if !isCenterStage {
                        Button(action: onTapPromote) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 13, weight: .black))
                                Text("MAKE BIG")
                                    .font(.system(size: 12.5, weight: .black, design: .rounded))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(red: 1.0, green: 0.80, blue: 0.20))
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, isCenterStage ? 14 : 10)
                .padding(.vertical, isCenterStage ? 9 : 7)
                .background(Color(red: 0.04, green: 0.06, blue: 0.11).opacity(0.96))

                Spacer()

                // BOTTOM BAR ON EVERY TILE: Non-Verbal AAC 1-Tap Picture-Symbol Board
                AACSymbolActionStrip(
                    viewModel: viewModel,
                    window: window,
                    isCenterStage: isCenterStage
                )
            }

            // 3. Active Per-Tile Whisper Voice Dictation Overlay
            if isDictatingThisTile {
                PerTileVoiceDictationOverlay(viewModel: viewModel, window: window)
                    .padding(isCenterStage ? 12 : 6)
            }
        }
        .clipShape(tileShape)
        .overlay(
            tileShape.stroke(
                isDictatingThisTile
                    ? Color(red: 1.0, green: 0.28, blue: 0.32)
                    : (isReadingThisTile
                        ? Color(red: 1.0, green: 0.82, blue: 0.22)
                        : (isCenterStage ? Color(red: 1.0, green: 0.82, blue: 0.22) : accent.opacity(0.75))),
                lineWidth: (isDictatingThisTile || isReadingThisTile || isCenterStage) ? 3.5 : 2.0
            )
        )
        .shadow(color: .black.opacity(0.45), radius: isCenterStage ? 10 : 5)
    }
}

// MARK: - 2B. Nearsighted High-Contrast Program Visual + Giant Reader Feed

struct SimplifiedAppContentView: View {
    let window: MonitoredWindow
    let accent: Color
    let isCenterStage: Bool
    let viewMode: TileContentViewMode
    let fontScale: Double
    let cardSize: CGSize

    private var digest: WindowLiveDigest {
        window.liveDigest ?? AppContentFeedExtractor.shared.extractLiveDigest(for: window)
    }

    private var activeVisualImage: NSImage? {
        window.focusedContentImage ?? window.previewImage
    }

    private var maxVisibleLines: Int {
        switch viewMode {
        case .simplifiedReader:
            return isCenterStage ? 4 : (cardSize.height < 180 ? 1 : 2)
        case .splitVisualAndFeed:
            return isCenterStage ? 3 : (cardSize.height < 190 ? 1 : 2)
        case .liveSmartZoom:
            return 1
        }
    }

    var body: some View {
        let visibleLines = Array(digest.lines.suffix(maxVisibleLines))

        switch viewMode {
        case .liveSmartZoom:
            ZStack(alignment: .bottomLeading) {
                liveViewportView
                if let last = visibleLines.last {
                    SimplifiedDigestLineBubble(
                        line: last,
                        style: digest.style,
                        accent: accent,
                        isCenterStage: isCenterStage,
                        fontScale: fontScale
                    )
                    .padding(8)
                }
            }

        case .simplifiedReader:
            feedColumnView(lines: visibleLines)

        case .splitVisualAndFeed:
            if activeVisualImage != nil {
                if isCenterStage || cardSize.width > 500 {
                    HStack(spacing: 12) {
                        liveViewportView
                            .frame(width: max(180, cardSize.width * 0.48))

                        feedColumnView(lines: visibleLines)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 8) {
                        liveViewportView
                            .frame(height: max(70, (cardSize.height - 95) * 0.48))

                        feedColumnView(lines: visibleLines)
                            .frame(maxHeight: .infinity)
                    }
                }
            } else {
                feedColumnView(lines: visibleLines)
            }
        }
    }

    @ViewBuilder
    private var liveViewportView: some View {
        if let img = activeVisualImage, img.size.width > 4, img.size.height > 4 {
            GeometryReader { geo in
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(accent.opacity(0.65), lineWidth: 2.0)
                    )
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accent.opacity(0.18))
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                }
            }
        }
    }

    private func feedColumnView(lines: [DigestFeedLine]) -> some View {
        VStack(alignment: .leading, spacing: isCenterStage ? 8 : 6) {
            HStack(spacing: 8) {
                Text(digest.style.badgeLabel)
                    .font(.system(size: CGFloat((isCenterStage ? 12.0 : 10.5) * fontScale), weight: .black, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.32))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(digest.contextTitle)
                    .font(.system(size: CGFloat((isCenterStage ? 13.0 : 11.0) * fontScale), weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: isCenterStage ? 8 : 6) {
                ForEach(lines) { line in
                    SimplifiedDigestLineBubble(
                        line: line,
                        style: digest.style,
                        accent: accent,
                        isCenterStage: isCenterStage,
                        fontScale: fontScale
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SimplifiedDigestLineBubble: View {
    let line: DigestFeedLine
    let style: DigestPresentationStyle
    let accent: Color
    let isCenterStage: Bool
    let fontScale: Double

    var body: some View {
        let isUserOrOutgoing = !line.isIncomingOrAgent || (line.speakerOrTag == "YOU")
        let isToolLine = (line.speakerOrTag == "TOOL")

        let badgeColor: Color = {
            if isUserOrOutgoing {
                return Color(red: 1.0, green: 0.82, blue: 0.22)
            } else if isToolLine {
                return Color(red: 0.25, green: 0.85, blue: 1.0)
            } else if line.isHighlighted {
                return Color(red: 0.16, green: 0.95, blue: 0.58)
            } else {
                return accent
            }
        }()

        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(badgeColor)
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 3) {
                if let speaker = line.speakerOrTag {
                    Text(speaker)
                        .font(.system(size: CGFloat((isCenterStage ? 11.5 : 10.0) * fontScale), weight: .black, design: .rounded))
                        .foregroundColor(badgeColor)
                }

                Text(line.text)
                    .font(.system(
                        size: CGFloat((isCenterStage ? 15.5 : 12.5) * fontScale),
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundColor(.white)
                    .lineLimit(isCenterStage ? 4 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, isCenterStage ? 12 : 9)
            .padding(.vertical, isCenterStage ? 9 : 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        isUserOrOutgoing
                            ? Color(red: 0.20, green: 0.17, blue: 0.08).opacity(0.96)
                            : (line.isHighlighted
                                ? Color(red: 0.08, green: 0.20, blue: 0.22).opacity(0.97)
                                : Color(red: 0.08, green: 0.11, blue: 0.18).opacity(0.95))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        line.isHighlighted ? badgeColor : Color.white.opacity(0.18),
                        lineWidth: line.isHighlighted ? 2.0 : 1.0
                    )
            )
        }
    }
}

// MARK: - 3. Right Side Tower: ECU Engine Diagnostics & Pit Crew Agents

struct AgentAndTasksSidePanel: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    @State private var selectedTab: Int = 0 // 0 = AI Engines, 1 = ECU Tasks

    private func latestFeedSummary(for snap: AgentStatusSnapshot) -> String? {
        if let win = viewModel.openWindows.first(where: { $0.platform == snap.platform }),
           let lastLine = win.liveDigest?.lines.last?.text,
           !lastLine.isEmpty {
            return lastLine
        }
        if snap.platform == .antigravity,
           let agyDigest = AppContentFeedExtractor.shared.buildAntigravityLiveDigest(window: nil),
           let lastLine = agyDigest.lines.last?.text {
            return lastLine
        }
        return snap.activeWindowTitle ?? snap.activeSubtaskSummary
    }

    var body: some View {
        let panelShape = CockpitChamferShape(topLeftCut: 18, topRightCut: 18, bottomRightCut: 18, bottomLeftCut: 18)

        VStack(spacing: 10) {
            // Motorsport Paddle Tabs
            HStack(spacing: 8) {
                Button(action: { selectedTab = 0 }) {
                    HStack(spacing: 5) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                        Text("AI ENGINES (\(viewModel.agentSnapshots.filter { $0.state != .offline }.count) LIVE)")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        selectedTab == 0
                            ? Color(red: 1.0, green: 0.42, blue: 0.14)
                            : Color.white.opacity(0.08)
                    )
                    .foregroundColor(selectedTab == 0 ? .black : .white)
                    .clipShape(CockpitChamferShape(topLeftCut: 8, topRightCut: 8, bottomRightCut: 8, bottomLeftCut: 8))
                }
                .buttonStyle(.plain)

                Button(action: { selectedTab = 1 }) {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.path.ecg.rectangle.fill")
                        Text("ECU TASKS (\(viewModel.runningTasks.count))")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        selectedTab == 1
                            ? Color(red: 1.0, green: 0.42, blue: 0.14)
                            : Color.white.opacity(0.08)
                    )
                    .foregroundColor(selectedTab == 1 ? .black : .white)
                    .clipShape(CockpitChamferShape(topLeftCut: 8, topRightCut: 8, bottomRightCut: 8, bottomLeftCut: 8))
                }
                .buttonStyle(.plain)
            }

            if selectedTab == 0 {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(viewModel.agentSnapshots) { snap in
                            AgentPlatformRowCard(
                                snapshot: snap,
                                liveThreadSnippet: latestFeedSummary(for: snap)
                            ) {
                                viewModel.activateOrLaunchPlatform(snap)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.runningTasks) { task in
                            RunningTaskRowView(task: task) {
                                if let win = viewModel.openWindows.first(where: { $0.ownerPID == task.pid || $0.platform == task.platform }) {
                                    viewModel.promoteWindowToStage(win)
                                } else if let app = NSRunningApplication(processIdentifier: task.pid) {
                                    NSApp.yieldActivation(to: app)
                                    app.activate(options: [.activateAllWindows])
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.06, green: 0.08, blue: 0.13).opacity(0.92))
        .clipShape(panelShape)
        .overlay(
            panelShape.stroke(Color(red: 1.0, green: 0.42, blue: 0.14).opacity(0.32), lineWidth: 1.5)
        )
    }
}

struct AgentPlatformRowCard: View {
    let snapshot: AgentStatusSnapshot
    let liveThreadSnippet: String?
    let onTap: () -> Void

    var body: some View {
        let rowShape = CockpitChamferShape(topLeftCut: 9, topRightCut: 9, bottomRightCut: 9, bottomLeftCut: 9)
        let rpmFraction = snapshot.state == .offline ? 0.0 : min(1.0, max(0.15, snapshot.cpuPercent / 35.0))

        Button(action: onTap) {
            HStack(spacing: 10) {
                // Left Vertical Accent Bar
                Rectangle()
                    .fill(snapshot.state == .offline ? Color.white.opacity(0.15) : snapshot.platform.accentColor)
                    .frame(width: 4, height: 48)

                if let icon = snapshot.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 34, height: 34)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(snapshot.platform.accentColor.opacity(0.2))
                            .frame(width: 34, height: 34)
                        Image(systemName: snapshot.platform.symbolName)
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(snapshot.platform.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(snapshot.platform.rawValue.uppercased())
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(.white)

                        Text(snapshot.state == .working ? "ACTIVE" : (snapshot.state == .idle ? "ONLINE" : "OFFLINE"))
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(snapshot.state.badgeColor)
                            .foregroundColor(snapshot.state == .offline ? .white.opacity(0.7) : .black)
                    }

                    if let snippet = liveThreadSnippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red: 0.78, green: 0.92, blue: 1.0))
                            .lineLimit(1)
                    } else {
                        SegmentedTelemetryBar(
                            fraction: rpmFraction,
                            segmentCount: 14,
                            activeColor: snapshot.platform.accentColor
                        )
                    }
                }

                Spacer()

                if snapshot.state != .offline {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%04.1f%%", snapshot.cpuPercent))
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(snapshot.cpuPercent >= 5.0 ? Color(red: 0.15, green: 1.0, blue: 0.60) : .white)
                        Text(snapshot.memoryMB > 0 ? String(format: "%.0f MB", snapshot.memoryMB) : "ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                    }
                } else {
                    Text("IGNITE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.10))
                        .foregroundColor(.white.opacity(0.85))
                        .clipShape(CockpitChamferShape(topLeftCut: 5, topRightCut: 5, bottomRightCut: 5, bottomLeftCut: 5))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                snapshot.state == .offline
                    ? Color.white.opacity(0.03)
                    : Color(red: 0.10, green: 0.13, blue: 0.20)
            )
            .clipShape(rowShape)
            .overlay(
                rowShape.stroke(
                    snapshot.state == .working
                        ? Color(red: 0.15, green: 1.0, blue: 0.60)
                        : Color.white.opacity(0.09),
                    lineWidth: snapshot.state == .working ? 1.5 : 1.0
                )
            )
        }
        .buttonStyle(.plain)
    }
}

struct RunningTaskRowView: View {
    let task: RunningTaskItem
    let onTap: () -> Void

    var body: some View {
        let shape = CockpitChamferShape(topLeftCut: 7, topRightCut: 7, bottomRightCut: 7, bottomLeftCut: 7)

        Button(action: onTap) {
            HStack(spacing: 8) {
                SegmentedTelemetryBar(
                    fraction: min(1.0, max(0.12, task.cpuPercent / 40.0)),
                    segmentCount: 5,
                    activeColor: Color(red: 0.20, green: 0.86, blue: 1.0)
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(task.commandName.uppercased())
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if let plat = task.platform {
                            Text(plat.rawValue.uppercased())
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(plat.accentColor)
                                .foregroundColor(.black)
                        }
                    }

                    Text(task.fullCommand)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f%%", task.cpuPercent))
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.60))
                    Text("PID \(task.pid)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))
            .clipShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 4. Bottom Diffuser & Pit-Lane Control Strip

struct BottomStatusStrip: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Large, clear status readout
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.15, green: 0.92, blue: 0.56))
                    .frame(width: 12, height: 12)
                Text(viewModel.statusBannerMessage)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 11))

            Spacer()

            Button(action: {
                viewModel.isShowingSettingsSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .black))
                    Text("CHOOSE APPS & SETTINGS")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(red: 1.0, green: 0.80, blue: 0.20))
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.refreshAll(captureImages: true)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .black))
                    Text("REFRESH")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(red: 0.22, green: 0.78, blue: 1.0))
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 40)
    }
}
