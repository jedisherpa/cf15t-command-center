import SwiftUI
import AppKit

struct CommandCenterMainView: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        VStack(spacing: 12) {
            // 1. Top Voice Deck (Grok Bot <-> Dot + Mic Controls + CF15T Hardware Bar)
            TopVoiceAndSystemBar(viewModel: viewModel)

            // 2. Main Split Workspace: Center-Stage + Border Window Tiler (Left 68%) | Agent & Task Monitor (Right 32%)
            GeometryReader { geo in
                let leftWidth = max(620, floor((geo.size.width - 12) * 0.67))
                HStack(spacing: 12) {
                    WindowTilingArenaPanel(viewModel: viewModel)
                        .frame(width: leftWidth)

                    AgentAndTasksSidePanel(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                }
            }

            // 3. Bottom Touch Status & CF15T Quick-Control Strip
            BottomStatusStrip(viewModel: viewModel)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.08, green: 0.10, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            GeometryReader { fullGeo in
                ZStack {
                    ForEach(viewModel.sisActiveContacts) { contact in
                        let cx = contact.normalizedX * fullGeo.size.width
                        let cy = contact.normalizedY * fullGeo.size.height
                        ZStack {
                            Circle()
                                .stroke(Color(red: 0.20, green: 0.96, blue: 0.68), lineWidth: 3)
                                .frame(width: 64, height: 64)
                            Circle()
                                .fill(Color(red: 1.0, green: 0.42, blue: 0.20).opacity(0.35))
                                .frame(width: 44, height: 44)
                            Text("#\(contact.id)")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .position(x: cx, y: cy)
                    }
                }
            }
            .allowsHitTesting(false)
        )
        .sheet(isPresented: $viewModel.isShowingVoiceSlotEditor) {
            VoiceSlotEditorSheet(viewModel: viewModel)
        }
    }
}

// MARK: - 1. Top Voice & Mic Switchboard (Grok Bot <-> Dot)

struct TopVoiceAndSystemBar: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Slot A: Grok Bot
            VoiceAssistantDeckCard(
                slot: viewModel.slotA,
                isActiveSlot: viewModel.activeVoiceSlotID == "slotA",
                accentColor: Color(red: 1.0, green: 0.38, blue: 0.18),
                onActivate: {
                    viewModel.switchToVoiceSlot("slotA", toggleMicIfExclusive: false)
                },
                onToggleMic: {
                    viewModel.toggleSlotMic("slotA")
                }
            )

            // Center Ping-Pong Switch Button (Grok Bot <-> Dot)
            Button(action: {
                viewModel.pingPongSwitchVoiceAssistants()
            }) {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                        Text("SWAP")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)

                    Text("\(viewModel.slotA.displayName) ⇄ \(viewModel.slotB.displayName)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)

                    Text(viewModel.exclusiveMicHandoff ? "Auto-Mic Handoff" : "Focus Switch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.25, green: 0.90, blue: 0.68))
                }
                .padding(.horizontal, 16)
                .frame(width: 165, height: 84)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.19, green: 0.24, blue: 0.36),
                            Color(red: 0.13, green: 0.17, blue: 0.26)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            // Slot B: Dot (or Configurable Secondary Voice)
            VoiceAssistantDeckCard(
                slot: viewModel.slotB,
                isActiveSlot: viewModel.activeVoiceSlotID == "slotB",
                accentColor: Color(red: 0.20, green: 0.86, blue: 0.65),
                onActivate: {
                    viewModel.switchToVoiceSlot("slotB", toggleMicIfExclusive: false)
                },
                onToggleMic: {
                    viewModel.toggleSlotMic("slotB")
                }
            )

            // System CoreAudio Master Mic & CF15T Touch Guard Box
            SystemMicAndTouchGuardBox(viewModel: viewModel)
                .frame(width: 340)
        }
        .frame(height: 84)
    }
}

struct VoiceAssistantDeckCard: View {
    let slot: VoiceAssistantConfig
    let isActiveSlot: Bool
    let accentColor: Color
    let onActivate: () -> Void
    let onToggleMic: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Left button: Activate / Focus Assistant
            Button(action: onActivate) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(isActiveSlot ? 0.28 : 0.14))
                            .frame(width: 46, height: 46)
                        Image(systemName: slot.isMicEnabled ? "waveform.circle.fill" : "person.wave.2.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(slot.displayName)
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if isActiveSlot {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .black))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(accentColor)
                                    .foregroundColor(.black)
                                    .clipShape(Capsule())
                            }
                        }
                        Text("Tap to Focus (\(slot.targetAppName))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Right button: Big Tactile MIC ON / OFF Toggle
            Button(action: onToggleMic) {
                VStack(spacing: 4) {
                    Image(systemName: slot.isMicEnabled ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(slot.isMicEnabled ? .black : .white)
                    Text(slot.isMicEnabled ? "MIC ON" : "MUTED")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(slot.isMicEnabled ? .black : .white.opacity(0.85))
                }
                .frame(width: 96, height: 68)
                .background(
                    slot.isMicEnabled
                        ? Color(red: 0.20, green: 0.94, blue: 0.56)
                        : Color(red: 0.85, green: 0.24, blue: 0.28).opacity(0.35)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(
                            slot.isMicEnabled
                                ? Color.white.opacity(0.8)
                                : Color(red: 0.95, green: 0.35, blue: 0.38).opacity(0.6),
                            lineWidth: 1.5
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .padding(.trailing, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.11, green: 0.14, blue: 0.20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isActiveSlot ? accentColor : Color.white.opacity(0.12), lineWidth: isActiveSlot ? 2.2 : 1.0)
        )
    }
}

struct SystemMicAndTouchGuardBox: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        HStack(spacing: 10) {
            // Master CoreAudio Hardware Mute Button
            Button(action: {
                viewModel.toggleSystemMasterMicMute()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.systemMicMuted ? "mic.slash.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(viewModel.systemMicMuted ? Color(red: 1.0, green: 0.36, blue: 0.38) : Color(red: 0.25, green: 0.92, blue: 0.60))
                    Text(viewModel.systemMicMuted ? "HW MUTE" : "HW LIVE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                }
                .frame(width: 78, height: 68)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(viewModel.audioInputDeviceName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(viewModel.systemMicVolume * 100))%")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(red: 0.25, green: 0.92, blue: 0.60))
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.systemMicVolume) },
                        set: { viewModel.updateMicVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .tint(Color(red: 0.25, green: 0.92, blue: 0.60))

                HStack(spacing: 8) {
                    Button(action: { viewModel.isShowingVoiceSlotEditor = true }) {
                        Label("Edit A/B Slots", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.cursorSnapbackEnabled.toggle() }) {
                        Label(
                            viewModel.cursorSnapbackEnabled ? "Snapback ON" : "Snapback OFF",
                            systemImage: viewModel.cursorSnapbackEnabled ? "cursorarrow.motionlines" : "cursorarrow"
                        )
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(viewModel.cursorSnapbackEnabled ? .black : .white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            viewModel.cursorSnapbackEnabled
                                ? Color(red: 0.35, green: 0.78, blue: 1.0)
                                : Color.white.opacity(0.10)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.11, green: 0.14, blue: 0.20))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 2. Center Stage + Perimeter Border Window Tiling Arena

struct WindowTilingArenaPanel: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        VStack(spacing: 10) {
            // Arena Header & Layout Controls
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "uiwindow.split.2x1")
                            .foregroundColor(Color(red: 0.35, green: 0.78, blue: 1.0))
                        Text("CENTER STAGE + BORDER WINDOW MATRIX")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Text("Press any border window to enlarge it Center Stage while keeping the rest around the border")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                // Layout mode buttons
                ForEach(TilingLayoutMode.allCases) { mode in
                    Button(action: {
                        viewModel.tilingMode = mode
                        if viewModel.autoTileRealWindowsOnTap {
                            viewModel.applyRealScreenTilingNow()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 12, weight: .bold))
                            Text(mode.shortLabel)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(viewModel.tilingMode == mode ? .black : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            viewModel.tilingMode == mode
                                ? Color(red: 0.35, green: 0.78, blue: 1.0)
                                : Color.white.opacity(0.08)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                // Physical macOS Tiling Trigger Button
                Button(action: {
                    viewModel.applyRealScreenTilingNow()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 12, weight: .bold))
                        Text("Tile Screen Now")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.20, green: 0.90, blue: 0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.restoreOriginalWindowPositions()
                }) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(7)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Restore Original Window Sizes")
            }

            // Interactive Center Stage + Perimeter Border Canvas
            GeometryReader { arenaGeo in
                CenterStagePerimeterCanvas(
                    viewModel: viewModel,
                    canvasSize: arenaGeo.size
                )
            }
        }
        .padding(12)
        .background(Color(red: 0.09, green: 0.11, blue: 0.16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct CenterStagePerimeterCanvas: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let canvasSize: CGSize

    var body: some View {
        let windows = viewModel.visibleTiledWindows
        if windows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "macwindow.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.35))
                Text("No External Application Windows Open")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                Text("Open Grok Bot, Claude, Codex, Chrome, or any macOS app — or tap Refresh.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                Button(action: {
                    viewModel.excludedWindowIDs.removeAll()
                    viewModel.refreshAll(captureImages: true)
                }) {
                    Text("Reset Filter & Scan Windows")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.35, green: 0.78, blue: 1.0))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                gap: 10
            )

            ZStack(alignment: .topLeading) {
                ForEach(Array(orderedWindows.enumerated()), id: \.element.id) { index, win in
                    if index < layoutRects.count {
                        let rect = layoutRects[index]
                        let isStage = (index == 0 && viewModel.tilingMode != .equalSimultaneousGrid)
                        InteractiveWindowTileCard(
                            window: win,
                            isCenterStage: isStage,
                            tileIndex: index,
                            onTapPromote: {
                                viewModel.promoteWindowToStage(win)
                            },
                            onFocusOnly: {
                                WindowTilingEngine.shared.focusWindow(win)
                            },
                            onExclude: {
                                viewModel.toggleWindowInclusion(win)
                            }
                        )
                        .frame(width: max(80, rect.width), height: max(60, rect.height))
                        .position(x: rect.midX, y: rect.midY)
                        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: rect)
                    }
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
    }
}

struct InteractiveWindowTileCard: View {
    let window: MonitoredWindow
    let isCenterStage: Bool
    let tileIndex: Int
    let onTapPromote: () -> Void
    let onFocusOnly: () -> Void
    let onExclude: () -> Void

    private var appThemeColor: Color {
        if let plat = window.platform {
            return plat.accentColor
        }
        let lower = window.appName.lowercased()
        if lower.contains("chrome") || lower.contains("safari") {
            return Color(red: 0.25, green: 0.62, blue: 1.0)
        } else if lower.contains("whatsapp") {
            return Color(red: 0.18, green: 0.85, blue: 0.46)
        } else if lower.contains("signal") {
            return Color(red: 0.35, green: 0.48, blue: 0.98)
        } else if lower.contains("music") || lower.contains("spotify") {
            return Color(red: 0.96, green: 0.32, blue: 0.55)
        } else if lower.contains("settings") {
            return Color(red: 0.95, green: 0.72, blue: 0.22)
        } else if lower.contains("finder") {
            return Color(red: 0.28, green: 0.78, blue: 0.98)
        } else if lower.contains("preview") || lower.contains("textedit") {
            return Color(red: 0.65, green: 0.52, blue: 0.96)
        }
        return Color(red: 0.35, green: 0.78, blue: 1.0)
    }

    var body: some View {
        let accent = appThemeColor

        Button(action: onTapPromote) {
            ZStack(alignment: .bottomLeading) {
                // Background Live Snapshot or Distinct Color-Coded App Card
                GeometryReader { cardGeo in
                    if let preview = window.previewImage,
                       preview.size.width > 4,
                       preview.size.height > 4,
                       cardGeo.size.width > 10,
                       cardGeo.size.height > 10 {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cardGeo.size.width, height: cardGeo.size.height)
                            .clipped()
                            .overlay(Color.black.opacity(isCenterStage ? 0.08 : 0.26))
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    accent.opacity(isCenterStage ? 0.34 : 0.20),
                                    Color(red: 0.07, green: 0.09, blue: 0.14)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )

                            VStack(spacing: isCenterStage ? 12 : 6) {
                                if let icon = window.appIcon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: isCenterStage ? 84 : 44, height: isCenterStage ? 84 : 44)
                                        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
                                }
                                Text(window.appName)
                                    .font(.system(size: isCenterStage ? 26 : 14, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                if isCenterStage {
                                    Text("ACTIVE STAGE WINDOW — TAP ANY BORDER TILE TO SWAP")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(red: 0.25, green: 0.96, blue: 0.68))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Color.black.opacity(0.45))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.top, 18)
                        }
                    }
                }

                // Top Header Overlay (App Icon, Name, Stage Badge, Quick Actions)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        if let icon = window.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: isCenterStage ? 26 : 20, height: isCenterStage ? 26 : 20)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(window.appName)
                                    .font(.system(size: isCenterStage ? 14 : 12, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                if isCenterStage {
                                    Text("STAGE (EXPANDED)")
                                        .font(.system(size: 9, weight: .black))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(red: 0.20, green: 0.92, blue: 0.60))
                                        .foregroundColor(.black)
                                        .clipShape(Capsule())
                                } else {
                                    Text("TAP TO EXPAND")
                                        .font(.system(size: 8, weight: .black))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.18))
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                }
                            }

                            Text(window.displayTitle)
                                .font(.system(size: isCenterStage ? 12 : 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.80))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        if isCenterStage {
                            Button(action: onFocusOnly) {
                                Label("Bring to Front", systemImage: "arrow.up.forward.app.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(accent)
                                    .foregroundColor(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: onExclude) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.75))
                                .padding(6)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Hide window from tiling grid")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.72))

                    Spacer()

                    // Bottom Metadata Pill
                    HStack {
                        if let plat = window.platform {
                            HStack(spacing: 4) {
                                Image(systemName: plat.symbolName)
                                    .font(.system(size: 10, weight: .bold))
                                Text(plat.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(plat.accentColor.opacity(0.9))
                            .foregroundColor(.black)
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Text("\(Int(window.bounds.width))×\(Int(window.bounds.height))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65))
                            .foregroundColor(.white.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: isCenterStage ? 14 : 11))
            .overlay(
                RoundedRectangle(cornerRadius: isCenterStage ? 14 : 11)
                    .stroke(
                        isCenterStage
                            ? Color(red: 0.20, green: 0.92, blue: 0.60)
                            : accent.opacity(0.55),
                        lineWidth: isCenterStage ? 3.0 : 1.4
                    )
            )
            .shadow(color: Color.black.opacity(0.35), radius: isCenterStage ? 10 : 4, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3. Right Side Panel: Multi-Platform AI Agent Monitor & Running Tasks

struct AgentAndTasksSidePanel: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    @State private var selectedTab: Int = 0 // 0 = All AI Agents, 1 = Running Tasks

    var body: some View {
        VStack(spacing: 10) {
            // Segmented Touch Header
            HStack(spacing: 8) {
                Button(action: { selectedTab = 0 }) {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu.fill")
                        Text("AI Agent Platforms (\(viewModel.agentSnapshots.filter { $0.state != .offline }.count) Live)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedTab == 0 ? Color(red: 0.35, green: 0.78, blue: 1.0) : Color.white.opacity(0.08))
                    .foregroundColor(selectedTab == 0 ? .black : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button(action: { selectedTab = 1 }) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                        Text("Running Tasks (\(viewModel.runningTasks.count))")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedTab == 1 ? Color(red: 0.35, green: 0.78, blue: 1.0) : Color.white.opacity(0.08))
                    .foregroundColor(selectedTab == 1 ? .black : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            if selectedTab == 0 {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.agentSnapshots) { snap in
                            AgentPlatformRowCard(snapshot: snap) {
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
        .background(Color(red: 0.09, green: 0.11, blue: 0.16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct AgentPlatformRowCard: View {
    let snapshot: AgentStatusSnapshot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                if let icon = snapshot.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 36, height: 36)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(snapshot.platform.accentColor.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: snapshot.platform.symbolName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(snapshot.platform.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(snapshot.platform.rawValue)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text(snapshot.state.rawValue)
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(snapshot.state.badgeColor)
                            .foregroundColor(snapshot.state == .offline ? .white.opacity(0.75) : .black)
                            .clipShape(Capsule())
                    }

                    Text(snapshot.activeSubtaskSummary ?? "Idle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer()

                if snapshot.state != .offline {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f%% CPU", snapshot.cpuPercent))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(snapshot.cpuPercent >= 5.0 ? Color(red: 0.20, green: 0.94, blue: 0.56) : .white.opacity(0.85))
                        if snapshot.memoryMB > 0 {
                            Text(String(format: "%.0f MB", snapshot.memoryMB))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                } else {
                    Text("Launch")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.09))
                        .foregroundColor(.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(snapshot.state == .offline ? Color.white.opacity(0.04) : Color(red: 0.13, green: 0.16, blue: 0.23))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        snapshot.state == .working
                            ? Color(red: 0.20, green: 0.94, blue: 0.56).opacity(0.8)
                            : Color.white.opacity(0.08),
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
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .fill(task.cpuPercent >= 5.0 ? Color(red: 0.20, green: 0.94, blue: 0.56) : Color(red: 0.35, green: 0.78, blue: 1.0))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(task.commandName)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if let plat = task.platform {
                            Text(plat.rawValue)
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(plat.accentColor)
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                        }
                    }

                    Text(task.fullCommand)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f%%", task.cpuPercent))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("PID \(task.pid)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 4. Bottom Touch Control & Status Strip

struct BottomStatusStrip: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    var body: some View {
        HStack(spacing: 10) {
            // Live SiS HID Touch Controller Hardware Badge
            Button(action: {
                viewModel.sisRemapToCF15TEnabled.toggle()
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            viewModel.sisIsTouching
                                ? Color(red: 1.0, green: 0.42, blue: 0.20)
                                : (viewModel.sisHardwareConnected
                                    ? Color(red: 0.20, green: 0.92, blue: 0.60)
                                    : Color.white.opacity(0.35))
                        )
                        .frame(width: 9, height: 9)
                    Text(
                        viewModel.sisIsTouching
                            ? String(format: "SiS TOUCH (%.0f%%, %.0f%%)", viewModel.sisNormalizedPoint.x * 100, viewModel.sisNormalizedPoint.y * 100)
                            : (viewModel.sisHardwareConnected ? "SiS 0x0457:0x0819 (\(viewModel.sisRemapToCF15TEnabled ? "CF15T Mapped" : "Raw"))" : "SiS Touch Offline")
                    )
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            // Live Status Pill
            HStack(spacing: 8) {
                Text(viewModel.statusBannerMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 9))

            Spacer()

            // Toggle Auto-Tile Real macOS Windows on Tap
            Toggle("Physically Tile macOS Windows on Tap", isOn: $viewModel.autoTileRealWindowsOnTap)
                .toggleStyle(.switch)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)

            // Target Display Picker for Real Window Tiling
            Picker("Tile On:", selection: $viewModel.targetDisplayMode) {
                ForEach(TargetDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .frame(width: 220)
            .font(.system(size: 12, weight: .semibold))

            if !viewModel.isAccessibilityGranted {
                Button(action: {
                    viewModel.requestAccessibilityPermission()
                }) {
                    Label("Grant Window Tiling Access", systemImage: "lock.open.display")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.98, green: 0.72, blue: 0.20))
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if !viewModel.excludedWindowIDs.isEmpty {
                Button(action: {
                    viewModel.excludedWindowIDs.removeAll()
                }) {
                    Text("Unhide (\(viewModel.excludedWindowIDs.count))")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                viewModel.snapPanelToCF15T()
            }) {
                Label("Move Panel to CF15T", systemImage: "display.2")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.refreshAll(captureImages: true)
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 38)
    }
}
