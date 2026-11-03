import SwiftUI

struct CommandCenterSettingsSheet: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    @Environment(\.dismiss) private var dismiss

    private let gridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            topHeaderBar

            Divider()
                .background(Color.white.opacity(0.15))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section1SelectionMode
                    section2ProgramSelectionGrid
                    section3VisualsAndSliders
                }
                .padding(20)
            }
        }
        .frame(width: 980, height: 690)
        .background(Color(red: 0.04, green: 0.05, blue: 0.09))
    }

    // MARK: - Top Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 22, weight: .black))
                .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))

            VStack(alignment: .leading, spacing: 2) {
                Text("COMMAND CENTER SETTINGS & PROGRAM SELECTION")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                Text("Choose which programs are displayed in the Window Tiling Matrix, adjust sizes, and save your defaults")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.70))
            }

            Spacer()

            Button(action: {
                viewModel.resetToAutomaticDefaults()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("AUTOMATIC DEFAULTS")
                }
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.12))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.saveDashboardPreferencesAsDefaults()
                dismiss()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("SAVE DEFAULTS & CLOSE")
                }
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color(red: 0.15, green: 1.0, blue: 0.62))
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(red: 0.07, green: 0.09, blue: 0.14))
    }

    // MARK: - Section 1: Program Selection Mode

    private var section1SelectionMode: some View {
        let isAuto = (viewModel.programSelectionMode == .automatic)
        let isCustom = (viewModel.programSelectionMode == .customDefaults)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("1. PROGRAM SELECTION MODE")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 0.20, green: 0.88, blue: 1.0))

                Spacer()

                HStack(spacing: 6) {
                    Text("DEFAULT #1 CENTER STAGE:")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))

                    Picker("", selection: $viewModel.defaultStageAppName) {
                        Text("Automatic (Active Voice / AI Agent)").tag("")
                        ForEach(viewModel.allSelectablePrograms) { prog in
                            Text(prog.displayName).tag(prog.id)
                        }
                    }
                    .frame(width: 240)
                }
            }

            HStack(spacing: 12) {
                Button(action: {
                    viewModel.programSelectionMode = .automatic
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: isAuto ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isAuto ? Color(red: 0.15, green: 1.0, blue: 0.62) : .white.opacity(0.5))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("AUTOMATIC SELECTION (DEFAULT)")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                            Text("Automatically displays open windows on your Mac. Uncheck any program below if you want to hide it.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.white.opacity(0.70))
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isAuto ? Color(red: 0.10, green: 0.22, blue: 0.20) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isAuto ? Color(red: 0.15, green: 1.0, blue: 0.62) : Color.white.opacity(0.15), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.programSelectionMode = .customDefaults
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: isCustom ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isCustom ? Color(red: 1.0, green: 0.78, blue: 0.18) : .white.opacity(0.5))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("CUSTOM PROGRAM LIST (ONLY SHOW CHECKED)")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                            Text("Only displays the specific programs you check below (e.g. Signal, ChatGPT, Grok Bot, Antigravity).")
                                .font(.system(size: 10.5))
                                .foregroundColor(.white.opacity(0.70))
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isCustom ? Color(red: 0.22, green: 0.18, blue: 0.08) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isCustom ? Color(red: 1.0, green: 0.78, blue: 0.18) : Color.white.opacity(0.15), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Section 2: Choose Which Programs Are Displayed

    private var section2ProgramSelectionGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("2. CHOOSE WHICH PROGRAMS ARE DISPLAYED ON THE MATRIX")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 0.20, green: 0.88, blue: 1.0))

                Spacer()

                Button(action: {
                    viewModel.selectAIAndMessagingProgramsOnly()
                }) {
                    Text("⚡ AI + MESSAGING ONLY (SIGNAL, CHATGPT, GROK, ANTIGRAVITY)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 1.0, green: 0.78, blue: 0.18))
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.selectAllPrograms()
                }) {
                    Text("✓ SHOW ALL PROGRAMS")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.15, green: 1.0, blue: 0.62))
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(viewModel.allSelectablePrograms) { prog in
                    ProgramSelectionRowCard(
                        viewModel: viewModel,
                        prog: prog
                    )
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Section 3: Adjustable Visuals, Sizing & Flow Overlay Controls

    private var section3VisualsAndSliders: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("3. ADJUSTABLE VISUAL MODE, SIZES & OVERLAYS")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundColor(Color(red: 0.20, green: 0.88, blue: 1.0))

            HStack(spacing: 12) {
                Text("TILE VISUAL MODE:")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 190, alignment: .leading)

                ForEach(TileContentViewMode.allCases) { mode in
                    let selected = (viewModel.tileContentViewMode == mode)
                    Button(action: {
                        viewModel.tileContentViewMode = mode
                    }) {
                        Text(mode.rawValue.uppercased())
                            .font(.system(size: 10.5, weight: .black, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selected ? Color(red: 0.20, green: 0.88, blue: 1.0) : Color.white.opacity(0.08))
                            .foregroundColor(selected ? .black : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CENTER STAGE SIZE:")
                            .font(.system(size: 10.5, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text("\(Int(viewModel.stageScaleFactor * 100))%")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))
                    }
                    Slider(value: $viewModel.stageScaleFactor, in: 0.42...0.78)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("MATRIX PANEL WIDTH:")
                            .font(.system(size: 10.5, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text("\(Int(viewModel.matrixWidthRatio * 100))%")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(Color(red: 0.20, green: 0.88, blue: 1.0))
                    }
                    Slider(value: $viewModel.matrixWidthRatio, in: 0.48...0.92)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("MESSAGE & THREAD TEXT SIZE:")
                            .font(.system(size: 10.5, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text("\(Int(viewModel.feedFontScale * 100))%")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.18))
                    }
                    Slider(value: $viewModel.feedFontScale, in: 0.85...1.55)
                }
            }

            HStack(spacing: 16) {
                Toggle(isOn: $viewModel.showFloatingFlowLines) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Floating CPU & Voice Dotted Lines Over Matrix (OFF by default)")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.white)
                        Text("When ON, horizontal orange dotted lines with moving points connect the Right AI Engine panel to programs actively using CPU, and green lines show live Mic routing.")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .toggleStyle(.switch)

                Spacer()

                Stepper(
                    "Max Tiled Windows: \(viewModel.maxTiledWindows)",
                    value: $viewModel.maxTiledWindows,
                    in: 2...12
                )
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.white)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ProgramSelectionRowCard: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let prog: SelectableProgramEntry

    var body: some View {
        let isShown = viewModel.isProgramDisplayed(prog.id)
        let isDefaultStage = (viewModel.normalizedAppKey(viewModel.defaultStageAppName) == prog.id)

        HStack(spacing: 8) {
            Button(action: {
                viewModel.toggleProgramDisplayed(prog.id)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isShown ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(
                            isShown
                                ? Color(red: 0.15, green: 1.0, blue: 0.62)
                                : .white.opacity(0.35)
                        )

                    if let icon = prog.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 18))
                            .foregroundColor(isShown ? Color(red: 0.20, green: 0.88, blue: 1.0) : .white.opacity(0.4))
                            .frame(width: 24, height: 24)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(prog.displayName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isShown ? .white : .white.opacity(0.5))
                                .lineLimit(1)

                            if prog.isCurrentlyOpen {
                                Text("OPEN")
                                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color(red: 0.15, green: 1.0, blue: 0.62).opacity(0.25))
                                    .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }

                        Text(isShown ? "DISPLAYED · \(prog.categoryLabel)" : "HIDDEN · \(prog.categoryLabel)")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(isShown ? Color(red: 0.15, green: 1.0, blue: 0.62) : .white.opacity(0.35))
                    }

                    Spacer(minLength: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                if isDefaultStage {
                    viewModel.defaultStageAppName = ""
                } else {
                    viewModel.defaultStageAppName = prog.id
                    if !isShown {
                        viewModel.toggleProgramDisplayed(prog.id)
                    }
                }
            }) {
                Image(systemName: isDefaultStage ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isDefaultStage ? Color(red: 1.0, green: 0.80, blue: 0.15) : .white.opacity(0.30))
                    .padding(5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Set \(prog.displayName) as Default #1 Center Stage window")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isShown ? Color(red: 0.08, green: 0.16, blue: 0.18) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isShown ? Color(red: 0.15, green: 1.0, blue: 0.62).opacity(0.65) : Color.white.opacity(0.10),
                    lineWidth: isShown ? 1.3 : 0.8
                )
        )
    }
}
