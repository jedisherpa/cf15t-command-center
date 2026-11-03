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
                    // 0. Top System Telemetry & Geometric Layout Rule Strip
                    ShiftLightRevStrip(
                        totalCPULoad: totalSystemCPULoad,
                        isAnyMicLive: isMicLive,
                        activeVoiceName: activeVoiceName,
                        layoutExplanation: viewModel.tilingMode.geometryExplanation,
                        isTouchingScreen: viewModel.sisIsTouching
                    )

                    // 0.5. Dual Operating Mode Switcher: ORCHESTRATE (Main Screen) vs. FULL CONTROL (Laptop Closed / Travel)
                    DualOperatingModeSwitcherBanner(viewModel: viewModel)

                    // 1. Voice Switchboard (Grok Bot <-> Dot) + Twin Gauges + 5-Axis Workload Balance Radar
                    // Shown in ORCHESTRATE mode; collapsed in FULL CONTROL mode so interactive program stations fill 100% of the screen
                    if viewModel.operatingMode == .orchestrate {
                        TopVoiceAndSystemBar(
                            viewModel: viewModel,
                            totalCPULoad: totalSystemCPULoad,
                            currentGear: currentGearNumber
                        )
                    }

                    // 2. Main Adjustable Split Cockpit: Window Tiling Matrix (Left) | Draggable Handle | AI Engines & Tasks (Right)
                    GeometryReader { geo in
                        let totalW = geo.size.width
                        let leftWidth = viewModel.isRightPanelCollapsed
                            ? totalW
                            : max(540, min(totalW - 260, floor(totalW * CGFloat(viewModel.matrixWidthRatio))))

                        HStack(spacing: 6) {
                            WindowTilingArenaPanel(viewModel: viewModel, currentGear: currentGearNumber)
                                .frame(width: leftWidth)

                            if !viewModel.isRightPanelCollapsed {
                                // Draggable Split Divider Handle
                                ZStack {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white.opacity(0.10))
                                        .frame(width: 6)
                                    VStack(spacing: 3) {
                                        ForEach(0..<4, id: \.self) { _ in
                                            Circle()
                                                .fill(Color(red: 0.20, green: 0.88, blue: 1.0))
                                                .frame(width: 3.5, height: 3.5)
                                        }
                                    }
                                }
                                .frame(width: 8)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 2)
                                        .onChanged { value in
                                            let newX = max(540, min(totalW - 260, value.location.x + leftWidth))
                                            viewModel.matrixWidthRatio = Double(newX / max(1, totalW))
                                        }
                                )
                                .help("Drag left or right to resize the Window Tiling Matrix vs AI Engines panel")

                                AgentAndTasksSidePanel(viewModel: viewModel)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    // 3. Bottom Control & Status Strip
                    BottomStatusStrip(viewModel: viewModel)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(CockpitCarbonBackground())
                .overlay(
                    GeometricTouchSimplexOverlay(contacts: viewModel.sisActiveContacts)
                )
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
    let currentGear: Int

    var body: some View {
        let panelShape = CockpitChamferShape(topLeftCut: 18, topRightCut: 18, bottomRightCut: 18, bottomLeftCut: 18)

        VStack(spacing: 10) {
            // Sequential Gearbox Bar & Nitro Tile Trigger
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("G\(currentGear)")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(red: 1.0, green: 0.38, blue: 0.14))
                        .foregroundColor(.black)
                        .clipShape(CockpitChamferShape(topLeftCut: 5, topRightCut: 5, bottomRightCut: 5, bottomLeftCut: 5))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("WINDOW TILING MATRIX // \(viewModel.tilingMode.shortLabel.uppercased())")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                        Text(viewModel.tilingMode.geometryExplanation.uppercased())
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.20, green: 0.86, blue: 1.0))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 5 Geometric Layout Mode Paddles
                ForEach(Array(TilingLayoutMode.allCases.enumerated()), id: \.element.id) { idx, mode in
                    let isSelected = (viewModel.tilingMode == mode)
                    Button(action: {
                        viewModel.tilingMode = mode
                        if viewModel.autoTileRealWindowsOnTap {
                            viewModel.applyRealScreenTilingNow(promptIfUntrusted: false)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("G\(idx + 1)")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(isSelected ? .black : Color(red: 1.0, green: 0.78, blue: 0.15))
                            Text(mode.shortLabel.uppercased())
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(isSelected ? .black : .white)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            isSelected
                                ? Color(red: 0.20, green: 0.88, blue: 1.0)
                                : Color.white.opacity(0.08)
                        )
                        .clipShape(CockpitChamferShape(topLeftCut: 6, topRightCut: 6, bottomRightCut: 6, bottomLeftCut: 6))
                    }
                    .buttonStyle(.plain)
                }

                // Physical macOS Screen Tile Trigger
                Button(action: {
                    viewModel.applyRealScreenTilingNow(promptIfUntrusted: true)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.3.group.fill")
                            .font(.system(size: 11, weight: .black))
                        Text("TILE MAC")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 1.0, blue: 0.58),
                                Color(red: 0.10, green: 0.82, blue: 0.95)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(CockpitChamferShape(topLeftCut: 6, topRightCut: 6, bottomRightCut: 6, bottomLeftCut: 6))
                }
                .buttonStyle(.plain)

                // Prominent SETTINGS & CHOOSE PROGRAMS Button
                Button(action: {
                    viewModel.isShowingSettingsSheet = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape.2.fill")
                            .font(.system(size: 11, weight: .black))
                        Text("SETTINGS & PROGRAMS")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color(red: 1.0, green: 0.78, blue: 0.15))
                    .clipShape(CockpitChamferShape(topLeftCut: 6, topRightCut: 6, bottomRightCut: 6, bottomLeftCut: 6))
                    .shadow(color: Color(red: 1.0, green: 0.78, blue: 0.15).opacity(0.45), radius: 5)
                }
                .buttonStyle(.plain)

                // Collapse / Expand Right Panel Button
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        viewModel.isRightPanelCollapsed.toggle()
                    }
                }) {
                    Image(systemName: viewModel.isRightPanelCollapsed ? "sidebar.right" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.white)
                        .padding(7)
                        .background(Color.white.opacity(0.10))
                        .clipShape(CockpitChamferShape(topLeftCut: 5, topRightCut: 5, bottomRightCut: 5, bottomLeftCut: 5))
                }
                .buttonStyle(.plain)
                .help(viewModel.isRightPanelCollapsed ? "Show Right AI Engines Panel" : "Expand Window Matrix to 100% Width")
            }

            // Live Program Roster & Inline Adjustability Strip (Clearly shows what programs are on the matrix + view/size controls)
            ProgramRosterAndAdjustmentStrip(viewModel: viewModel)

            // Interactive Center Stage + Perimeter Border Canvas
            GeometryReader { arenaGeo in
                CenterStagePerimeterCanvas(
                    viewModel: viewModel,
                    canvasSize: arenaGeo.size
                )
            }
        }
        .padding(12)
        .background(Color(red: 0.06, green: 0.08, blue: 0.13).opacity(0.92))
        .clipShape(panelShape)
        .overlay(
            panelShape.stroke(Color(red: 0.20, green: 0.82, blue: 1.0).opacity(0.28), lineWidth: 1.5)
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
            return Color(red: 0.20, green: 0.72, blue: 1.0)
        } else if lower.contains("whatsapp") {
            return Color(red: 0.15, green: 0.95, blue: 0.52)
        } else if lower.contains("signal") {
            return Color(red: 0.38, green: 0.54, blue: 1.0)
        } else if lower.contains("music") || lower.contains("spotify") {
            return Color(red: 1.0, green: 0.28, blue: 0.58)
        } else if lower.contains("settings") {
            return Color(red: 1.0, green: 0.78, blue: 0.18)
        } else if lower.contains("finder") {
            return Color(red: 0.25, green: 0.85, blue: 1.0)
        }
        return Color(red: 0.28, green: 0.82, blue: 1.0)
    }

    var body: some View {
        let accent = appThemeColor
        let cut: CGFloat = isCenterStage ? 18 : 11
        let tileShape = CockpitChamferShape(topLeftCut: cut, topRightCut: cut, bottomRightCut: cut, bottomLeftCut: cut)
        let isDictatingThisTile = viewModel.isDictating(for: window)
        let isFullControl = (viewModel.operatingMode == .fullControl)
        let roleBadge = isCenterStage
            ? String(format: "★ #1 STAGE · %.0f%%", node.areaPercent)
            : String(format: "#%d · %.0f%%", node.rankIndex + 1, node.areaPercent)

        ZStack(alignment: .bottomLeading) {
            // High-Clarity Program Visual (Split Live Cropped Screen + Feed, Live Screen Only, or Reader Feed)
            GeometryReader { cardGeo in
                ZStack {
                    Color(red: 0.04, green: 0.06, blue: 0.10)

                    SimplifiedAppContentView(
                        window: window,
                        accent: accent,
                        isCenterStage: isCenterStage,
                        viewMode: viewMode,
                        fontScale: fontScale,
                        cardSize: cardGeo.size
                    )
                    .padding(.top, isCenterStage ? 34 : 28)
                    .padding(.bottom, isFullControl ? (isCenterStage ? 38 : 34) : (isCenterStage ? 26 : 22))
                    .padding(.horizontal, isCenterStage ? 8 : 5)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onTapPromote()
                }
            }

            // HUD Corner Brackets inside Center Stage
            if isCenterStage {
                HUDCornerBrackets(
                    color: isDictatingThisTile
                        ? Color(red: 1.0, green: 0.25, blue: 0.32)
                        : Color(red: 0.15, green: 1.0, blue: 0.62),
                    lineWidth: 3.0,
                    length: 28
                )
                .padding(6)
                .allowsHitTesting(false)
            }

            // Top & Bottom Telemetry + Universal Voice Dictation Overlay Bars
            VStack(alignment: .leading, spacing: 0) {
                // Top Bar: Rank + Program Name + Universal Whisper Mic Button + Voice Status + Boost Button
                HStack(spacing: 6) {
                    Button(action: onTapPromote) {
                        HStack(spacing: 5) {
                            Text(roleBadge)
                                .font(.system(size: isCenterStage ? 10 : 8, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(isCenterStage ? Color(red: 0.15, green: 1.0, blue: 0.62) : accent)
                                .foregroundColor(.black)
                                .lineLimit(1)

                            if let icon = window.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: isCenterStage ? 16 : 13, height: isCenterStage ? 16 : 13)
                            }

                            Text(window.appName.uppercased())
                                .font(.system(size: isCenterStage ? 13 : 10, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 2)

                    // UNIVERSAL WHISPER MICROPHONE BUTTON ON EVERY TILE (Works in both ORCHESTRATE & FULL CONTROL)
                    Button {
                        viewModel.toggleVoiceDictation(for: window)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isDictatingThisTile ? "stop.circle.fill" : "mic.fill")
                                .font(.system(size: isCenterStage ? 11 : 9.5, weight: .black))
                            Text(isDictatingThisTile ? "SEND VOICE ⏎" : (isCenterStage ? "🎙️ WHISPER DICTATE" : "🎙️ DICTATE"))
                                .font(.system(size: isCenterStage ? 9.5 : 8, weight: .black, design: .monospaced))
                        }
                        .padding(.horizontal, isCenterStage ? 10 : 7)
                        .padding(.vertical, isCenterStage ? 4.5 : 3)
                        .background(
                            isDictatingThisTile
                                ? Color(red: 1.0, green: 0.22, blue: 0.30)
                                : Color(red: 0.15, green: 0.96, blue: 0.62)
                        )
                        .foregroundColor(isDictatingThisTile ? .white : .black)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .shadow(
                            color: (isDictatingThisTile ? Color.red : Color(red: 0.15, green: 0.96, blue: 0.62)).opacity(0.45),
                            radius: 5
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Dictate next instruction with local Whisper into \(window.appName)'s open prompt")

                    // Voice Channel Badge if this window is Grok Bot (CH-01) or Dot / ChatGPT (CH-02)
                    if let voiceCode = node.voiceChannelCode {
                        HStack(spacing: 3) {
                            Image(systemName: node.isMicLive ? "mic.fill" : "waveform")
                                .font(.system(size: 8, weight: .black))
                            Text(
                                node.isMicLive
                                    ? "\(voiceCode) MIC LIVE"
                                    : (node.isActiveVoiceTarget ? "\(voiceCode) VOICE TARGET" : voiceCode)
                            )
                            .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            node.isMicLive
                                ? Color(red: 0.15, green: 1.0, blue: 0.58)
                                : (node.isActiveVoiceTarget ? Color(red: 1.0, green: 0.78, blue: 0.18) : Color.white.opacity(0.18))
                        )
                        .foregroundColor(node.isMicLive || node.isActiveVoiceTarget ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if isCenterStage && !isFullControl {
                        Button(action: onFocusOnly) {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                Text("BRING TO FRONT")
                            }
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 1.0, green: 0.78, blue: 0.15))
                            .foregroundColor(.black)
                            .clipShape(CockpitChamferShape(topLeftCut: 5, topRightCut: 5, bottomRightCut: 5, bottomLeftCut: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onExclude) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(5)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Hide \(window.appName) from Matrix")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.90))

                Spacer()

                // Bottom Bar:
                // - In FULL CONTROL mode: Interactive Whisper Voice + Prompt Deck + Scroll Up/Down + Peek App
                // - In ORCHESTRATE mode: Window Title / AI Platform + Real CPU % + Real Window Dimensions
                if isFullControl {
                    FullControlTileBottomDeck(
                        viewModel: viewModel,
                        window: window,
                        isCenterStage: isCenterStage
                    )
                } else {
                    HStack(spacing: 6) {
                        if let plat = window.platform {
                            Text("AI // \(plat.rawValue.uppercased())")
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(plat.accentColor)
                                .foregroundColor(.black)
                        }

                        Text(window.displayTitle)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)

                        Spacer()

                        if node.cpuPercent >= 0.4 {
                            Text(String(format: "⚡ %.1f%% CPU", node.cpuPercent))
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    node.cpuPercent >= 10.0
                                        ? Color(red: 1.0, green: 0.45, blue: 0.15)
                                        : Color.black.opacity(0.78)
                                )
                                .foregroundColor(
                                    node.cpuPercent >= 10.0
                                        ? .black
                                        : Color(red: 0.15, green: 1.0, blue: 0.62)
                                )
                        }

                        Text("\(Int(window.bounds.width))×\(Int(window.bounds.height))")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.72))
                            .foregroundColor(Color(red: 0.25, green: 0.88, blue: 1.0))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.82))
                }
            }

            // Active Per-Tile Whisper Voice Dictation HUD Overlay
            if isDictatingThisTile {
                PerTileVoiceDictationOverlay(viewModel: viewModel, window: window)
                    .padding(isCenterStage ? 10 : 4)
            }
        }
        .clipShape(tileShape)
        .overlay(
            tileShape.stroke(
                isDictatingThisTile
                    ? Color(red: 1.0, green: 0.22, blue: 0.30)
                    : (node.isMicLive
                        ? Color(red: 0.15, green: 1.0, blue: 0.58)
                        : (isCenterStage ? Color(red: 0.15, green: 1.0, blue: 0.62) : accent.opacity(0.65))),
                lineWidth: (isDictatingThisTile || isCenterStage || node.isMicLive) ? 3.0 : 1.4
            )
        )
        .shadow(
            color: isDictatingThisTile
                ? Color(red: 1.0, green: 0.22, blue: 0.30).opacity(0.55)
                : (isCenterStage ? Color(red: 0.15, green: 1.0, blue: 0.62).opacity(0.35) : .black.opacity(0.4)),
            radius: (isDictatingThisTile || isCenterStage) ? 12 : 4
        )
    }
}

// MARK: - 2B. High-Clarity Program Visual (100% Bright Active-Crop Live Screen + Large-Text Feed Drawer)

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
            return isCenterStage ? 6 : (cardSize.height < 140 ? 2 : 4)
        case .splitVisualAndFeed:
            return isCenterStage ? 4 : (cardSize.height < 155 ? 2 : 3)
        case .liveSmartZoom:
            return 1
        }
    }

    var body: some View {
        let visibleLines = Array(digest.lines.suffix(maxVisibleLines))

        switch viewMode {
        case .liveSmartZoom:
            // 100% Bright Smart-Cropped Live Window View + Bottom Latest Line Banner
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
                    .padding(6)
                }
            }

        case .simplifiedReader:
            // 100% High-Contrast Large-Text Reader Feed
            feedColumnView(lines: visibleLines)

        case .splitVisualAndFeed:
            // Default Hybrid View:
            // - In Center Stage (or wide cards): Left 56% = 100% Bright Zoomed Live Screen | Right 44% = High-Contrast Live Feed
            // - In Border Tiles: Top 55% = 100% Bright Zoomed Live Screen | Bottom 45% = High-Contrast Latest Messages/Thread
            if activeVisualImage != nil {
                if isCenterStage || cardSize.width > 460 {
                    HStack(spacing: 8) {
                        liveViewportView
                            .frame(width: max(160, cardSize.width * 0.55))

                        feedColumnView(lines: visibleLines)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 5) {
                        liveViewportView
                            .frame(height: max(54, (cardSize.height - 50) * 0.54))

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
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(accent.opacity(0.55), lineWidth: 1.2)
                    )
                    .overlay(alignment: .topLeading) {
                        Text("LIVE VIEW")
                            .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.78))
                            .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(4)
                    }
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(accent.opacity(0.15))
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 44, height: 44)
                }
            }
        }
    }

    private func feedColumnView(lines: [DigestFeedLine]) -> some View {
        VStack(alignment: .leading, spacing: isCenterStage ? 5 : 3) {
            HStack(spacing: 5) {
                Text(digest.statusBadge)
                    .font(.system(size: CGFloat((isCenterStage ? 9.0 : 7.5) * fontScale), weight: .black, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(accent.opacity(0.28))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Text(digest.contextTitle)
                    .font(.system(size: CGFloat((isCenterStage ? 10.0 : 8.5) * fontScale), weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: isCenterStage ? 4.5 : 3) {
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
                return Color(red: 1.0, green: 0.78, blue: 0.18)
            } else if isToolLine {
                return Color(red: 0.20, green: 0.88, blue: 1.0)
            } else if line.isHighlighted {
                return Color(red: 0.15, green: 1.0, blue: 0.62)
            } else {
                return accent
            }
        }()

        HStack(alignment: .top, spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(badgeColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let speaker = line.speakerOrTag {
                        Text(speaker)
                            .font(.system(size: CGFloat((isCenterStage ? 8.5 : 7.5) * fontScale), weight: .black, design: .monospaced))
                            .foregroundColor(badgeColor)
                    }

                    if line.isHighlighted {
                        Circle()
                            .fill(Color(red: 0.15, green: 1.0, blue: 0.62))
                            .frame(width: 5, height: 5)
                    }
                }

                Text(line.text)
                    .font(.system(
                        size: CGFloat((isCenterStage ? 11.5 : 9.5) * fontScale),
                        weight: line.isHighlighted ? .bold : .medium,
                        design: style == .aiAgentThread ? .monospaced : .default
                    ))
                    .foregroundColor(line.isHighlighted ? .white : .white.opacity(0.92))
                    .lineLimit(isCenterStage ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, isCenterStage ? 7 : 5)
            .padding(.vertical, isCenterStage ? 4.5 : 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isUserOrOutgoing
                            ? Color(red: 0.18, green: 0.15, blue: 0.08).opacity(0.94)
                            : (line.isHighlighted
                                ? Color(red: 0.07, green: 0.17, blue: 0.19).opacity(0.95)
                                : Color.black.opacity(0.84))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        line.isHighlighted ? badgeColor.opacity(0.85) : Color.white.opacity(0.12),
                        lineWidth: line.isHighlighted ? 1.2 : 0.7
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
        let stripShape = CockpitChamferShape(topLeftCut: 8, topRightCut: 8, bottomRightCut: 8, bottomLeftCut: 8)

        HStack(spacing: 10) {
            // Live SiS HID Steering / Touch Telemetry Pill
            Button(action: {
                viewModel.sisRemapToCF15TEnabled.toggle()
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            viewModel.sisIsTouching
                                ? Color(red: 1.0, green: 0.38, blue: 0.14)
                                : (viewModel.sisHardwareConnected
                                    ? Color(red: 0.15, green: 1.0, blue: 0.60)
                                    : Color.white.opacity(0.35))
                        )
                        .frame(width: 8, height: 8)
                    Text(
                        viewModel.sisIsTouching
                            ? String(format: "TOUCH LOCK [X:%02.0f Y:%02.0f]", viewModel.sisNormalizedPoint.x * 100, viewModel.sisNormalizedPoint.y * 100)
                            : (viewModel.sisHardwareConnected ? "SiS-0x0457 // \(viewModel.sisRemapToCF15TEnabled ? "LOCKED TO CF15T" : "RAW")" : "SiS OFFLINE")
                    )
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .clipShape(stripShape)
            }
            .buttonStyle(.plain)

            // Live Telemetry Status Readout
            HStack(spacing: 6) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.15))
                Text(viewModel.statusBannerMessage.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.05))
            .clipShape(stripShape)

            Spacer()

            Toggle("AUTO-SHIFT WINDOWS", isOn: $viewModel.autoTileRealWindowsOnTap)
                .toggleStyle(.switch)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white)

            Picker("", selection: $viewModel.targetDisplayMode) {
                ForEach(TargetDisplayMode.allCases) { mode in
                    Text(mode.rawValue.uppercased()).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 175)
            .font(.system(size: 10, weight: .bold, design: .monospaced))

            if !viewModel.isAccessibilityGranted {
                Button(action: {
                    viewModel.requestAccessibilityPermission()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                        Text("UNLOCK AX TILING")
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(red: 1.0, green: 0.75, blue: 0.15))
                    .foregroundColor(.black)
                    .clipShape(stripShape)
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                viewModel.isShowingSettingsSheet = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape.2.fill")
                    Text("SETTINGS")
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(red: 1.0, green: 0.78, blue: 0.15))
                .foregroundColor(.black)
                .clipShape(stripShape)
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.snapPanelToCF15T()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "display")
                    Text("LOCK TO CF15T")
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.10))
                .foregroundColor(.white)
                .clipShape(stripShape)
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.refreshAll(captureImages: true)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal.fill")
                    Text("SCAN")
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(red: 0.20, green: 0.86, blue: 1.0).opacity(0.25))
                .foregroundColor(Color(red: 0.20, green: 0.86, blue: 1.0))
                .clipShape(stripShape)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 34)
    }
}
