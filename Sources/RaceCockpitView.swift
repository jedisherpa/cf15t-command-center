import SwiftUI
import AppKit

// MARK: - Spotlight · Race Cockpit
//
// The main Command Center look:
// - Shift lights across the top show how busy the app on the big screen is (can be turned off)
// - A rotary knob switches ORCHESTRATE ⟷ FULL CONTROL
// - One big yellow-framed panel shows the app that's on the big screen: live picture, "Right now",
//   any question it's asking (giant YES / NO), and what happened before
// - A steering-wheel action row: TALK on the left grip, picture buttons on the hub, STOP on the right grip
// - A timing tower lists the other apps, each with its own mic
//
// Adapts to the 15.6" CF15T (16:9) and to a 12.3" wide bar screen (about half as tall).

// MARK: - Palette & Type

enum RacePalette {
    static let bg = Color(red: 0.03, green: 0.03, blue: 0.04)
    static let carbonBase = Color(red: 0.075, green: 0.075, blue: 0.086)
    static let yellow = Color(red: 1.0, green: 0.83, blue: 0.0)
    static let green = Color(red: 0.0, green: 0.90, blue: 0.46)
    static let darkGreen = Color(red: 0.0, green: 0.78, blue: 0.33)
    static let red = Color(red: 1.0, green: 0.16, blue: 0.16)
    static let raceRed = Color(red: 0.88, green: 0.02, blue: 0.0)
    static let orange = Color(red: 1.0, green: 0.54, blue: 0.0)
    static let blue = Color(red: 0.16, green: 0.47, blue: 1.0)
    static let muted = Color(red: 0.55, green: 0.55, blue: 0.60)
    static let rowBg = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let lcdBg = Color(red: 0.043, green: 0.075, blue: 0.043)
    static let ring = Color(red: 0.27, green: 0.27, blue: 0.30)
    static let edge = Color(red: 0.20, green: 0.20, blue: 0.23)
    static let unlitLED = Color(red: 0.11, green: 0.11, blue: 0.12)

    static let knurl: Gradient = {
        var stops: [Gradient.Stop] = []
        let segments = 60
        for i in 0..<segments {
            let c = (i % 2 == 0) ? Color(white: 0.17) : Color(white: 0.28)
            let a = CGFloat(i) / CGFloat(segments)
            let b = CGFloat(i + 1) / CGFloat(segments)
            stops.append(Gradient.Stop(color: c, location: a))
            stops.append(Gradient.Stop(color: c, location: b))
        }
        return Gradient(stops: stops)
    }()

    static let hazard: Gradient = {
        var stops: [Gradient.Stop] = []
        let segments = 24
        for i in 0..<segments {
            let c = (i % 2 == 0) ? RacePalette.yellow : Color(white: 0.07)
            let a = CGFloat(i) / CGFloat(segments)
            let b = CGFloat(i + 1) / CGFloat(segments)
            stops.append(Gradient.Stop(color: c, location: a))
            stops.append(Gradient.Stop(color: c, location: b))
        }
        return Gradient(stops: stops)
    }()
}

enum RaceType {
    static func font(_ size: CGFloat, _ weight: Font.Weight = .heavy, italic: Bool = true) -> Font {
        let base: Font = Font.system(size: size, weight: weight).width(.condensed)
        return italic ? base.italic() : base
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Sizing (15.6" standard vs 12.3" wide bar)

struct RaceMetrics {
    let size: CGSize
    let isBar: Bool
    let k: CGFloat
    let textScale: CGFloat

    init(size: CGSize, fontScale: Double) {
        self.size = size
        let aspect: CGFloat = size.width / max(1, size.height)
        isBar = aspect >= 2.05
        let refHeight: CGFloat = isBar ? 700 : 1040
        let raw: CGFloat = min(size.width / 1920, size.height / refHeight)
        k = max(0.5, min(1.3, raw))
        textScale = CGFloat(max(0.8, min(1.3, fontScale / 1.48)))
    }

    func s(_ v: CGFloat) -> CGFloat { v * k }
    func t(_ v: CGFloat) -> CGFloat { v * k * textScale }

    var towerWidth: CGFloat { isBar ? s(470) : s(540) }
    var liveScreenWidth: CGFloat { isBar ? s(470) : s(600) }
    var wheelHeight: CGFloat { isBar ? s(116) : s(168) }
    var gripWidth: CGFloat { isBar ? s(190) : s(250) }
    var hubOrb: CGFloat { isBar ? s(74) : s(104) }
    var gripOrb: CGFloat { isBar ? s(88) : s(126) }
    var topBarHeight: CGFloat { isBar ? s(80) : s(96) }
    var towerMaxRows: Int { isBar ? 4 : 5 }
    var towerRowHeight: CGFloat { isBar ? s(112) : s(150) }
}

// MARK: - Per-app status (same words & colours everywhere)

enum RaceAppStatus: Equatable {
    case working
    case needsYou
    case ready

    var label: String {
        switch self {
        case .working: return "◐ WORKING"
        case .needsYou: return "❗ NEEDS YOU"
        case .ready: return "● READY"
        }
    }

    var color: Color {
        switch self {
        case .working: return Color(red: 1.0, green: 0.82, blue: 0.25)
        case .needsYou: return Color(red: 1.0, green: 0.48, blue: 0.24)
        case .ready: return Color(red: 0.18, green: 0.83, blue: 0.48)
        }
    }

    var textColor: Color {
        switch self {
        case .working, .needsYou: return Color(red: 0.10, green: 0.10, blue: 0.10)
        case .ready: return Color(red: 0.04, green: 0.14, blue: 0.09)
        }
    }
}

struct RaceAppInfo {
    let window: MonitoredWindow
    let digest: WindowLiveDigest
    let cpu: Double
    let status: RaceAppStatus
    let question: String?
    let statusLine: String

    @MainActor
    static func make(_ window: MonitoredWindow, viewModel: CommandCenterViewModel) -> RaceAppInfo {
        let digest: WindowLiveDigest = window.liveDigest ?? AppContentFeedExtractor.shared.extractLiveDigest(for: window)
        let cpu: Double = viewModel.cpuPercent(for: window)
        let question: String? = pendingQuestion(in: digest)

        let status: RaceAppStatus
        if cpu >= 6.0 {
            status = .working
        } else if question != nil {
            status = .needsYou
        } else {
            status = .ready
        }

        let topic: String = digest.contextTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasTopic: Bool = !topic.isEmpty && topic.lowercased() != window.appName.lowercased()
        let line: String
        switch status {
        case .working:
            if hasTopic {
                line = topic.lowercased().hasPrefix("working") ? topic : "Working on: \(topic)"
            } else {
                line = "Working…"
            }
        case .needsYou:
            line = "Asking you a question"
        case .ready:
            line = hasTopic ? topic : "Waiting for you"
        }

        return RaceAppInfo(window: window, digest: digest, cpu: cpu, status: status, question: question, statusLine: line)
    }

    /// If the newest line is from the app and contains a question, returns that question sentence.
    static func pendingQuestion(in digest: WindowLiveDigest) -> String? {
        guard let last = digest.lines.last, last.isIncomingOrAgent, last.text.contains("?") else { return nil }
        let sentences = splitSentences(last.text)
        let q: String = sentences.last(where: { $0.contains("?") }) ?? last.text
        return clip(q, 150)
    }

    static func splitSentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" || ch == "\n" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(trimmed) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    static func clip(_ s: String, _ n: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > n ? String(trimmed.prefix(n - 1)) + "…" : trimmed
    }

    static func appColor(for window: MonitoredWindow) -> Color {
        if let plat = window.platform {
            return plat.accentColor
        }
        let palette: [Color] = [
            Color(red: 0.23, green: 0.46, blue: 0.94),
            Color(red: 0.06, green: 0.64, blue: 0.50),
            Color(red: 0.85, green: 0.47, blue: 0.34),
            Color(red: 0.49, green: 0.36, blue: 1.0),
            Color(red: 0.91, green: 0.36, blue: 0.55),
            Color(red: 0.95, green: 0.65, blue: 0.15)
        ]
        let seed: Int = window.appName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[seed % palette.count]
    }
}

// MARK: - Root View

struct RaceCockpitView: View {
    @ObservedObject var viewModel: CommandCenterViewModel

    private var shownWindows: [MonitoredWindow] {
        viewModel.openWindows.filter {
            !viewModel.excludedWindowIDs.contains($0.id) && viewModel.isProgramDisplayed($0.appName)
        }
    }

    private var stageWindow: MonitoredWindow? {
        let pool = shownWindows
        if let id = viewModel.stageWindowID, let match = pool.first(where: { $0.id == id }) {
            return match
        }
        return viewModel.currentStageWindow ?? pool.first
    }

    var body: some View {
        GeometryReader { geo in
            let m = RaceMetrics(size: geo.size, fontScale: viewModel.feedFontScale)
            let stage: MonitoredWindow? = stageWindow
            let info: RaceAppInfo? = stage.map { RaceAppInfo.make($0, viewModel: viewModel) }
            let others: [MonitoredWindow] = shownWindows.filter { $0.id != stage?.id }
            let dictating: MonitoredWindow? = viewModel.openWindows.first(where: { viewModel.isDictating(for: $0) })

            ZStack {
                RacePalette.bg

                VStack(spacing: m.s(12)) {
                    if !m.isBar {
                        RaceShiftLightStrip(viewModel: viewModel, info: info, m: m, inline: false)
                    }

                    RaceTopBar(viewModel: viewModel, info: info, m: m)

                    HStack(spacing: m.s(18)) {
                        RaceFocusPanel(viewModel: viewModel, info: info, m: m)
                        RaceTimingTower(viewModel: viewModel, others: others, m: m)
                            .frame(width: m.towerWidth)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, m.s(24))
                .padding(.vertical, m.s(14))

                if let win = dictating {
                    Color.black.opacity(0.55)
                    PerTileVoiceDictationOverlay(viewModel: viewModel, window: win)
                        .frame(maxWidth: min(780, geo.size.width * 0.62))
                        .frame(maxHeight: geo.size.height * 0.82)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Carbon Fibre Background

struct RaceCarbon: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(RacePalette.carbonBase))
            let step: CGFloat = 14
            var rising = Path()
            var falling = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                rising.move(to: CGPoint(x: x, y: size.height))
                rising.addLine(to: CGPoint(x: x + size.height, y: 0))
                falling.move(to: CGPoint(x: x, y: 0))
                falling.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += step
            }
            ctx.stroke(rising, with: .color(Color.white.opacity(0.035)), lineWidth: 7)
            ctx.stroke(falling, with: .color(Color.white.opacity(0.035)), lineWidth: 7)
        }
    }
}

// MARK: - Shift Lights

struct RaceShiftLightStrip: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let info: RaceAppInfo?
    let m: RaceMetrics
    let inline: Bool

    private func ledColor(_ i: Int) -> Color {
        if i < 5 { return RacePalette.green }
        if i < 10 { return RacePalette.yellow }
        return RacePalette.red
    }

    var body: some View {
        if viewModel.showShiftLights {
            let cpu: Double = info?.cpu ?? 0
            let fraction: Double = min(1.0, cpu / 40.0)
            let lit: Int = Int((fraction * 15.0).rounded())
            let pct: Int = Int((fraction * 100.0).rounded())
            let ledW: CGFloat = inline ? m.s(22) : m.s(70)
            let ledH: CGFloat = inline ? m.s(20) : m.s(28)
            let appName: String = info?.window.appName.uppercased() ?? "NO APP"
            let leftLabel: String = cpu < 1.0 ? "\(appName) IS RESTING" : "\(appName) IS BUSY"

            Button(action: { viewModel.showShiftLights = false }) {
                HStack(spacing: inline ? m.s(5) : m.s(9)) {
                    if !inline {
                        Text(leftLabel)
                            .font(RaceType.font(m.s(20), .heavy))
                            .foregroundColor(RacePalette.muted)
                            .lineLimit(1)
                            .padding(.trailing, m.s(10))
                    }
                    ForEach(0..<15, id: \.self) { i in
                        let on: Bool = i < lit
                        Capsule()
                            .fill(on ? ledColor(i) : RacePalette.unlitLED)
                            .frame(width: ledW, height: ledH)
                            .overlay(Capsule().stroke(on ? ledColor(i) : RacePalette.edge, lineWidth: m.s(2)))
                            .shadow(color: on ? ledColor(i) : .clear, radius: m.s(7))
                    }
                    Text("◐ \(pct)%")
                        .font(RaceType.font(m.s(20), .heavy))
                        .foregroundColor(RacePalette.yellow)
                        .padding(.leading, m.s(8))
                }
                .frame(maxWidth: .infinity)
                .frame(height: inline ? m.s(44) : m.s(42))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Tap to hide the busy lights")
        } else {
            Button(action: { viewModel.showShiftLights = true }) {
                Text("💡 Show busy lights")
                    .font(RaceType.font(m.s(17), .bold, italic: false))
                    .foregroundColor(RacePalette.muted)
                    .padding(.horizontal, m.s(14))
                    .padding(.vertical, m.s(4))
                    .background(Capsule().fill(RacePalette.rowBg))
                    .overlay(Capsule().stroke(RacePalette.edge, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: inline ? .infinity : nil)
        }
    }
}

// MARK: - Top Bar

struct RaceTopBar: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let info: RaceAppInfo?
    let m: RaceMetrics

    var body: some View {
        let multipleScreens: Bool = DisplayTargetManager.shared.externalScreens.count > 1

        HStack(spacing: m.s(14)) {
            // Top-left: switch to the Classic (tile grid) view
            Button(action: { viewModel.toggleClassicLayout() }) {
                RacePillLabel(icon: "🗂️", title: "Classic view", subtitle: "Tap to switch", m: m)
                    .background(RaceCarbon().clipShape(Capsule()))
                    .overlay(Capsule().stroke(RacePalette.edge, lineWidth: m.s(2)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            RaceModeKnob(viewModel: viewModel, m: m)

            if m.isBar {
                RaceShiftLightStrip(viewModel: viewModel, info: info, m: m, inline: true)
            } else {
                Spacer(minLength: 0)
            }

            if multipleScreens {
                Button(action: { viewModel.moveCommandCenterToNextScreen() }) {
                    RacePillLabel(icon: "📺", title: "Move screen", subtitle: viewModel.commandCenterScreenName, m: m)
                        .background(RaceCarbon().clipShape(Capsule()))
                        .overlay(Capsule().stroke(RacePalette.edge, lineWidth: m.s(2)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            RaceRoundTextButton(label: "A−", d: m.s(76), fg: .white, ring: RacePalette.edge, m: m) {
                viewModel.feedFontScale = max(1.18, viewModel.feedFontScale - 0.12)
                viewModel.saveDashboardPreferencesAsDefaults()
            }
            RaceRoundTextButton(label: "A+", d: m.s(76), fg: RacePalette.yellow, ring: RacePalette.yellow, m: m) {
                viewModel.feedFontScale = min(1.92, viewModel.feedFontScale + 0.12)
                viewModel.saveDashboardPreferencesAsDefaults()
            }

            Button(action: { viewModel.isShowingSettingsSheet = true }) {
                RacePillLabel(icon: "⚙️", title: "SETTINGS", subtitle: m.isBar ? "Apps & screen" : "Pick which apps show", m: m, dark: true)
                    .background(Capsule().fill(RacePalette.yellow))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(height: m.topBarHeight)
    }
}

struct RacePillLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    let m: RaceMetrics
    var dark: Bool = false

    var body: some View {
        HStack(spacing: m.s(12)) {
            Text(icon)
                .font(.system(size: m.s(28)))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(RaceType.font(m.s(28), .heavy))
                    .lineLimit(1)
                Text(subtitle)
                    .font(RaceType.font(m.s(18), .semibold, italic: false))
                    .opacity(0.75)
                    .lineLimit(1)
            }
        }
        .foregroundColor(dark ? .black : .white)
        .padding(.horizontal, m.s(24))
        .frame(height: m.isBar ? m.s(70) : m.s(82))
    }
}

struct RaceRoundTextButton: View {
    let label: String
    let d: CGFloat
    let fg: Color
    let ring: Color
    let m: RaceMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(RaceType.font(d * 0.38, .black, italic: false))
                .foregroundColor(fg)
                .frame(width: d, height: d)
                .background(Circle().fill(RacePalette.rowBg))
                .overlay(Circle().stroke(ring, lineWidth: m.s(3)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mode Knob (ORCHESTRATE ⟷ FULL CONTROL)

struct RaceModeKnob: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let m: RaceMetrics

    var body: some View {
        let isFull: Bool = viewModel.operatingMode == .fullControl

        HStack(spacing: m.s(18)) {
            Button(action: { viewModel.setOperatingMode(.orchestrate) }) {
                knobLabel(title: "ORCHESTRATE", subtitle: "Switch apps on laptop", on: !isFull, alignment: .trailing)
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.setOperatingMode(isFull ? .orchestrate : .fullControl) }) {
                RaceKnobDial(angle: isFull ? 45 : -45, d: m.isBar ? m.s(62) : m.s(76))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.setOperatingMode(.fullControl) }) {
                knobLabel(title: "FULL CONTROL", subtitle: "Lid closed · run from here", on: isFull, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, m.s(24))
        .frame(height: m.isBar ? m.s(76) : m.s(90))
        .background(RaceCarbon().clipShape(Capsule()))
        .overlay(Capsule().stroke(RacePalette.edge, lineWidth: m.s(2)))
    }

    private func knobLabel(title: String, subtitle: String, on: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(title)
                .font(RaceType.font(m.s(26), .heavy))
            if !m.isBar {
                Text(subtitle)
                    .font(RaceType.font(m.s(17), .semibold, italic: false))
            }
        }
        .foregroundColor(on ? RacePalette.yellow : .white)
        .opacity(on ? 1.0 : 0.45)
        .contentShape(Rectangle())
    }
}

struct RaceKnobDial: View {
    let angle: Double
    let d: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(gradient: RacePalette.knurl, center: .center))
                .frame(width: d * 1.2, height: d * 1.2)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.36), Color(white: 0.10)],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 1,
                        endRadius: d * 0.62
                    )
                )
                .frame(width: d, height: d)
            Capsule()
                .fill(RacePalette.yellow)
                .frame(width: d * 0.1, height: d * 0.38)
                .offset(y: -d * 0.22)
                .rotationEffect(.degrees(angle))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: angle)
    }
}

// MARK: - Spotlight Panel (the app on the big screen)

struct RaceFocusPanel: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let info: RaceAppInfo?
    let m: RaceMetrics

    @State private var showWholeWindow: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: m.s(30))

        VStack(spacing: m.s(16)) {
            if let info = info {
                RaceFocusHeader(viewModel: viewModel, info: info, m: m)

                HStack(alignment: .top, spacing: m.s(20)) {
                    RaceLiveScreen(info: info, m: m, showWholeWindow: $showWholeWindow)
                        .frame(width: m.liveScreenWidth)
                    RaceRightNowColumn(viewModel: viewModel, info: info, m: m)
                }
                .frame(maxHeight: .infinity)

                RaceSteeringWheel(viewModel: viewModel, info: info, m: m)
                    .frame(height: m.wheelHeight)
            } else {
                RaceEmptySpotlight(viewModel: viewModel, m: m)
            }
        }
        .padding(m.s(20))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RaceCarbon().clipShape(shape))
        .overlay(shape.stroke(RacePalette.yellow, lineWidth: m.s(5)))
    }
}

struct RaceEmptySpotlight: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let m: RaceMetrics

    var body: some View {
        VStack(spacing: m.s(18)) {
            Spacer()
            Text("🏁")
                .font(.system(size: m.s(90)))
            Text("No apps to show yet")
                .font(RaceType.font(m.s(48), .heavy))
                .foregroundColor(.white)
            Text("Open an app on the laptop, or tap SETTINGS to pick which apps show here.")
                .font(RaceType.font(m.s(26), .semibold, italic: false))
                .foregroundColor(RacePalette.muted)
                .multilineTextAlignment(.center)
            Button(action: { viewModel.isShowingSettingsSheet = true }) {
                Text("⚙️ SETTINGS")
                    .font(RaceType.font(m.s(30), .heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, m.s(34))
                    .padding(.vertical, m.s(16))
                    .background(Capsule().fill(RacePalette.yellow))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct RaceAppIcon: View {
    let window: MonitoredWindow
    let size: CGFloat
    var ring: Color? = nil
    var ringWidth: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(RaceAppInfo.appColor(for: window))
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.78, height: size * 0.78)
            } else {
                Text(String(window.appName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(ring ?? .clear, lineWidth: ringWidth))
    }
}

struct RaceStatusPill: View {
    let status: RaceAppStatus
    let fontSize: CGFloat

    var body: some View {
        Text(status.label)
            .font(RaceType.font(fontSize, .heavy, italic: false))
            .foregroundColor(status.textColor)
            .padding(.horizontal, fontSize * 0.65)
            .padding(.vertical, fontSize * 0.15)
            .background(Capsule().fill(status.color))
            .lineLimit(1)
            .fixedSize()
    }
}

struct RaceFocusHeader: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let info: RaceAppInfo
    let m: RaceMetrics

    var body: some View {
        let whereLabel: String = viewModel.operatingMode == .fullControl ? "IN CONTROL NOW" : "ON THE LAPTOP SCREEN NOW"
        let iconSize: CGFloat = m.isBar ? m.s(70) : m.s(88)

        HStack(spacing: m.s(20)) {
            RaceAppIcon(window: info.window, size: iconSize, ring: RacePalette.yellow, ringWidth: m.s(4))
                .padding(m.s(4))

            VStack(alignment: .leading, spacing: 0) {
                Text(whereLabel)
                    .font(RaceType.font(m.s(22), .heavy))
                    .foregroundColor(RacePalette.yellow)
                    .tracking(m.s(2))
                Text(info.window.appName.uppercased())
                    .font(RaceType.font(m.isBar ? m.s(54) : m.s(66), .black))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            Spacer(minLength: m.s(10))

            RaceStatusLCD(info: info, m: m)
        }
    }
}

struct RaceStatusLCD: View {
    let info: RaceAppInfo
    let m: RaceMetrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: m.s(16))

        VStack(alignment: .leading, spacing: m.s(2)) {
            Text("STATUS")
                .font(RaceType.mono(m.s(17), .bold))
                .foregroundColor(Color(red: 0.60, green: 0.54, blue: 0.23))
                .tracking(m.s(3))
            Text(info.status.label)
                .font(RaceType.mono(m.isBar ? m.s(28) : m.s(34), .heavy))
                .foregroundColor(info.status.color)
            Text(info.statusLine)
                .font(RaceType.font(m.s(22), .semibold, italic: false))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, m.s(22))
        .padding(.vertical, m.s(10))
        .frame(maxWidth: m.s(560), alignment: .leading)
        .background(shape.fill(RacePalette.lcdBg))
        .overlay(shape.stroke(Color(red: 0.17, green: 0.23, blue: 0.17), lineWidth: m.s(3)))
        .shadow(color: RacePalette.yellow.opacity(0.10), radius: m.s(10))
    }
}

// MARK: - Live Screen

struct RaceLiveScreen: View {
    let info: RaceAppInfo
    let m: RaceMetrics
    @Binding var showWholeWindow: Bool

    var body: some View {
        let win: MonitoredWindow = info.window
        let img: NSImage? = showWholeWindow
            ? (win.previewImage ?? win.focusedContentImage)
            : (win.focusedContentImage ?? win.previewImage)
        let outer = RoundedRectangle(cornerRadius: m.s(24))
        let inner = RoundedRectangle(cornerRadius: m.s(18))

        VStack(spacing: m.s(8)) {
            Button(action: { showWholeWindow.toggle() }) {
                ZStack(alignment: .topLeading) {
                    inner.fill(Color.black)

                    if let img = img, img.size.width > 4, img.size.height > 4 {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(inner)
                    } else {
                        RaceAppIcon(window: win, size: m.s(110))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    HStack(spacing: m.s(8)) {
                        Text("●")
                            .foregroundColor(RacePalette.red)
                        Text(showWholeWindow ? "LIVE · whole window" : "LIVE · close-up")
                            .foregroundColor(.white)
                    }
                    .font(RaceType.font(m.s(20), .heavy, italic: false))
                    .padding(.horizontal, m.s(16))
                    .padding(.vertical, m.s(6))
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .padding(m.s(12))
                }
                .padding(m.s(6))
                .background(
                    outer.fill(
                        LinearGradient(
                            colors: [Color(white: 0.29), Color(white: 0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !m.isBar {
                Text(showWholeWindow ? "👆 Tap the picture for a close-up" : "👆 Tap the picture to see the whole window")
                    .font(RaceType.font(m.s(20), .semibold, italic: false))
                    .foregroundColor(RacePalette.muted)
            }
        }
    }
}

// MARK: - Right Now · Question · Before This

struct RaceRightNowColumn: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let info: RaceAppInfo
    let m: RaceMetrics

    private var rightNowText: String {
        let appName = info.window.appName
        guard let latest = info.digest.lines.last else {
            return "\(appName) is open and ready."
        }
        if !latest.isIncomingOrAgent {
            return "You asked: \"\(RaceAppInfo.clip(latest.text, 200))\""
        }
        if let q = info.question {
            // Don't repeat the question — it gets its own big card below
            let sentences = RaceAppInfo.splitSentences(latest.text)
            let rest = sentences.filter { !$0.contains("?") }.joined(separator: " ")
            let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == q {
                return "\(appName) has a question for you."
            }
            return RaceAppInfo.clip(trimmed, 240)
        }
        return RaceAppInfo.clip(latest.text, 260)
    }

    var body: some View {
        let lines: [DigestFeedLine] = info.digest.lines
        let earlier: [DigestFeedLine] = Array(lines.dropLast().suffix(m.isBar ? 1 : 2))
        let showHistory: Bool = !earlier.isEmpty && (!m.isBar || info.question == nil)

        VStack(alignment: .leading, spacing: m.s(14)) {
            RaceSectionLabel(text: "RIGHT NOW", m: m)

            Text(rightNowText)
                .font(RaceType.font(m.isBar ? m.t(34) : m.t(44), .heavy))
                .foregroundColor(.white)
                .lineLimit(m.isBar ? 3 : 4)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            if let q = info.question {
                RaceRadioQuestion(viewModel: viewModel, info: info, question: q, m: m)
            }

            if showHistory {
                RaceSectionLabel(text: "BEFORE THIS", m: m)
                ForEach(earlier) { line in
                    RaceHistoryRow(line: line, appName: info.window.appName, m: m)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RaceSectionLabel: View {
    let text: String
    let m: RaceMetrics

    var body: some View {
        Text(text)
            .font(RaceType.font(m.s(22), .heavy))
            .tracking(m.s(2.5))
            .foregroundColor(RacePalette.muted)
    }
}

struct RaceRadioQuestion: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let info: RaceAppInfo
    let question: String
    let m: RaceMetrics

    var body: some View {
        let isChat: Bool = info.digest.style == .messagingChat
        let yesCard = AACVisualSymbolCard(
            id: "race_yes",
            iconName: "checkmark.circle.fill",
            emoji: "✅",
            shortTitle: "YES",
            spokenConfirmation: "Sent: yes",
            backgroundColor: RacePalette.darkGreen,
            foregroundColor: .black,
            action: .sendPrompt(isChat ? "Yes 👍" : "Yes, go ahead.", pressReturn: true)
        )
        let noCard = AACVisualSymbolCard(
            id: "race_no",
            iconName: "xmark.circle.fill",
            emoji: "❌",
            shortTitle: "NO",
            spokenConfirmation: "Sent: no",
            backgroundColor: RacePalette.red,
            foregroundColor: .black,
            action: .sendPrompt(isChat ? "No, thank you." : "No, don't do that.", pressReturn: true)
        )
        let orb: CGFloat = m.isBar ? m.s(92) : m.s(116)
        let shape = RoundedRectangle(cornerRadius: m.s(24))

        HStack(spacing: m.s(14)) {
            VStack(alignment: .leading, spacing: m.s(4)) {
                Text("📻 RADIO · \(info.window.appName.uppercased()) IS ASKING YOU")
                    .font(RaceType.font(m.s(23), .heavy))
                    .foregroundColor(Color(red: 1.0, green: 0.60, blue: 0.16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\"\(question)\"")
                    .font(RaceType.font(m.isBar ? m.t(28) : m.t(36), .heavy))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { viewModel.executeAACSymbolCard(yesCard, for: info.window) }) {
                RaceOrb(glyph: "✅", inside: "YES", diameter: orb, fill: RacePalette.darkGreen, fg: Color(red: 0.01, green: 0.17, blue: 0.07))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.executeAACSymbolCard(noCard, for: info.window) }) {
                RaceOrb(glyph: "❌", inside: "NO", diameter: orb, fill: RacePalette.red, fg: Color(red: 0.17, green: 0.02, blue: 0.02))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, m.s(20))
        .padding(.vertical, m.s(14))
        .background(
            shape.fill(
                LinearGradient(
                    colors: [RacePalette.orange.opacity(0.18), RacePalette.orange.opacity(0.04)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        )
        .overlay(shape.stroke(RacePalette.orange, lineWidth: m.s(3)))
    }
}

struct RaceHistoryRow: View {
    let line: DigestFeedLine
    let appName: String
    let m: RaceMetrics

    var body: some View {
        let isYou: Bool = !line.isIncomingOrAgent
        let who: String = isYou ? "You said" : (line.speakerOrTag?.capitalized ?? appName)
        let glyph: String = isYou ? "🗣️" : "💬"

        HStack(spacing: m.s(14)) {
            Rectangle()
                .fill(RacePalette.edge)
                .frame(width: m.s(6))
            Text(glyph)
                .font(.system(size: m.t(24)))
            Text("\(who): \(RaceAppInfo.clip(line.text, 120))")
                .font(RaceType.font(m.t(25), .semibold, italic: false))
                .foregroundColor(Color(white: 0.80))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.trailing, m.s(16))
        .padding(.vertical, m.s(9))
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: m.s(10)).fill(Color(white: 0.09)))
        .clipShape(RoundedRectangle(cornerRadius: m.s(10)))
    }
}

// MARK: - Round Wheel Buttons

struct RaceOrb: View {
    let glyph: String
    let inside: String?
    let diameter: CGFloat
    let fill: Color
    let fg: Color

    var body: some View {
        VStack(spacing: diameter * 0.02) {
            Text(glyph)
                .font(.system(size: diameter * (inside == nil ? 0.40 : 0.32)))
            if let inside = inside {
                Text(inside)
                    .font(RaceType.font(diameter * 0.20, .black, italic: false))
                    .foregroundColor(fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: diameter, height: diameter)
        .background(Circle().fill(fill))
        .overlay(
            Circle().fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.25), Color.clear, Color.black.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
        )
        .overlay(Circle().stroke(Color(white: 0.05), lineWidth: diameter * 0.05))
        .padding(diameter * 0.035)
        .overlay(Circle().stroke(RacePalette.ring, lineWidth: diameter * 0.03))
    }
}

// MARK: - Steering Wheel Action Row

struct RaceSteeringWheel: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    @ObservedObject var speechEngine = SensoryFriendlySpeechEngine.shared
    let info: RaceAppInfo
    let m: RaceMetrics

    private func shortLabel(_ card: AACVisualSymbolCard) -> String {
        switch card.id {
        case "ai_yes": return "DO IT"
        case "ai_explain": return "EXPLAIN"
        case "ai_fix": return "FIX IT"
        case "ai_steps": return "NEXT"
        case "ai_stop": return "STOP"
        case "msg_yes": return "YES"
        case "msg_no": return "NO"
        case "msg_omw": return "ON MY WAY"
        case "msg_wait": return "WAIT"
        case "msg_thanks": return "THANKS"
        case "nav_up": return "UP"
        case "nav_down": return "DOWN"
        case "nav_zoom_in": return "BIGGER"
        case "nav_back": return "BACK"
        default: return card.shortTitle
        }
    }

    var body: some View {
        let win: MonitoredWindow = info.window
        let cards: [AACVisualSymbolCard] = AACVisualSymbolCard.cards(for: win)
        let redIDs: Set<String> = ["ai_stop", "msg_no", "nav_back"]
        let redCard: AACVisualSymbolCard? = cards.first(where: { redIDs.contains($0.id) })
        let hubCards: [AACVisualSymbolCard] = Array(cards.filter { $0.id != redCard?.id }.prefix(4))
        let isRec: Bool = viewModel.isDictating(for: win)
        let isReading: Bool = speechEngine.isSpeaking && speechEngine.speakingWindowID == win.id

        HStack(spacing: 0) {
            // Left grip: TALK (local Whisper dictation into this app)
            RaceGrip(isLeft: true, m: m) {
                Button(action: { viewModel.toggleVoiceDictation(for: win) }) {
                    RaceOrb(
                        glyph: isRec ? "📤" : "🎤",
                        inside: isRec ? "SEND" : "TALK",
                        diameter: m.gripOrb,
                        fill: isRec ? RacePalette.red : RacePalette.green,
                        fg: isRec ? .white : Color(red: 0.01, green: 0.17, blue: 0.07)
                    )
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Hub: READ IT + picture buttons for this app
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                RaceHubButton(
                    glyph: isReading ? "⏹️" : "🔊",
                    label: isReading ? "STOP READING" : "READ IT",
                    fill: RacePalette.blue,
                    m: m
                ) {
                    speechEngine.toggleReadAloud(for: win)
                }
                ForEach(hubCards) { card in
                    Spacer(minLength: 0)
                    RaceHubButton(glyph: card.emoji, label: shortLabel(card), fill: card.backgroundColor, m: m) {
                        viewModel.executeAACSymbolCard(card, for: win)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RaceCarbon())
            .overlay(alignment: .top) { Rectangle().fill(RacePalette.edge).frame(height: m.s(3)) }
            .overlay(alignment: .bottom) { Rectangle().fill(RacePalette.edge).frame(height: m.s(3)) }

            // Right grip: STOP (or NO / BACK) inside a hazard ring
            RaceGrip(isLeft: false, m: m) {
                if let red = redCard {
                    Button(action: { viewModel.executeAACSymbolCard(red, for: win) }) {
                        ZStack {
                            Circle()
                                .fill(AngularGradient(gradient: RacePalette.hazard, center: .center))
                                .frame(width: m.gripOrb * 1.22, height: m.gripOrb * 1.22)
                            RaceOrb(
                                glyph: red.emoji,
                                inside: shortLabel(red),
                                diameter: m.gripOrb * 0.92,
                                fill: RacePalette.red,
                                fg: Color(red: 0.17, green: 0.02, blue: 0.02)
                            )
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct RaceGrip<Content: View>: View {
    let isLeft: Bool
    let m: RaceMetrics
    @ViewBuilder let content: () -> Content

    var body: some View {
        let big: CGFloat = m.s(90)
        let small: CGFloat = m.s(24)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: isLeft ? big : small,
            bottomLeadingRadius: isLeft ? big : small,
            bottomTrailingRadius: isLeft ? small : big,
            topTrailingRadius: isLeft ? small : big
        )

        content()
            .frame(width: m.gripWidth)
            .frame(maxHeight: .infinity)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [Color(white: 0.13), Color(white: 0.07), Color(white: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
    }
}

struct RaceHubButton: View {
    let glyph: String
    let label: String
    let fill: Color
    let m: RaceMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: m.s(6)) {
                RaceOrb(glyph: glyph, inside: nil, diameter: m.hubOrb, fill: fill, fg: .black)
                Text(label)
                    .font(RaceType.font(m.isBar ? m.s(19) : m.s(23), .heavy))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timing Tower (other apps)

struct RaceTimingTower: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let others: [MonitoredWindow]
    let m: RaceMetrics

    var body: some View {
        let header = UnevenRoundedRectangle(
            topLeadingRadius: m.s(14),
            bottomLeadingRadius: m.s(4),
            bottomTrailingRadius: m.s(4),
            topTrailingRadius: m.s(14)
        )

        VStack(spacing: m.s(8)) {
            HStack {
                Text("OTHER APPS")
                    .font(RaceType.font(m.s(26), .black))
                Spacer(minLength: m.s(8))
                Text("tap one to put it on the big screen")
                    .font(RaceType.font(m.s(17), .semibold, italic: false))
                    .opacity(0.9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(.white)
            .padding(.horizontal, m.s(18))
            .padding(.vertical, m.s(10))
            .background(header.fill(RacePalette.raceRed))

            if others.isEmpty {
                VStack(spacing: m.s(10)) {
                    Spacer()
                    Text("No other apps open")
                        .font(RaceType.font(m.s(28), .heavy))
                        .foregroundColor(RacePalette.muted)
                    Button(action: { viewModel.isShowingSettingsSheet = true }) {
                        Text("⚙️ Pick apps")
                            .font(RaceType.font(m.s(24), .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, m.s(22))
                            .padding(.vertical, m.s(10))
                            .background(Capsule().fill(RacePalette.yellow))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: m.s(8)).fill(RacePalette.rowBg))
            } else if others.count <= m.towerMaxRows {
                ForEach(Array(others.enumerated()), id: \.element.id) { idx, win in
                    RaceTowerRow(viewModel: viewModel, window: win, position: idx + 2, m: m)
                        .frame(maxHeight: m.s(210))
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: m.s(8)) {
                        ForEach(Array(others.enumerated()), id: \.element.id) { idx, win in
                            RaceTowerRow(viewModel: viewModel, window: win, position: idx + 2, m: m)
                                .frame(height: m.towerRowHeight)
                        }
                    }
                }
            }
        }
    }
}

struct RaceTowerRow: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let window: MonitoredWindow
    let position: Int
    let m: RaceMetrics

    var body: some View {
        let info: RaceAppInfo = RaceAppInfo.make(window, viewModel: viewModel)
        let needsYou: Bool = info.status == .needsYou
        let isRec: Bool = viewModel.isDictating(for: window)
        let posWidth: CGFloat = m.isBar ? m.s(54) : m.s(70)
        let iconSize: CGFloat = m.isBar ? m.s(56) : m.s(70)
        let micSize: CGFloat = m.isBar ? m.s(64) : m.s(76)
        let shape = RoundedRectangle(cornerRadius: m.s(8))

        HStack(spacing: m.s(14)) {
            Button(action: { viewModel.promoteWindowToStage(window) }) {
                HStack(spacing: m.s(14)) {
                    Text("\(position)")
                        .font(RaceType.font(m.s(34), .black))
                        .foregroundColor(Color(white: 0.07))
                        .frame(width: posWidth)
                        .frame(maxHeight: .infinity)
                        .background(needsYou ? RacePalette.orange : Color(white: 0.96))

                    Rectangle()
                        .fill(RaceAppInfo.appColor(for: window))
                        .frame(width: m.s(10))

                    RaceAppIcon(window: window, size: iconSize)

                    VStack(alignment: .leading, spacing: m.s(4)) {
                        Text(window.appName)
                            .font(RaceType.font(m.isBar ? m.s(28) : m.s(34), .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        HStack(spacing: m.s(8)) {
                            RaceStatusPill(status: info.status, fontSize: m.s(18))
                            if !m.isBar {
                                Text(info.statusLine)
                                    .font(RaceType.font(m.s(21), .semibold, italic: false))
                                    .foregroundColor(Color(white: 0.72))
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.toggleVoiceDictation(for: window) }) {
                Text(isRec ? "📤" : "🎤")
                    .font(.system(size: micSize * 0.42))
                    .frame(width: micSize, height: micSize)
                    .background(Circle().fill(isRec ? RacePalette.red.opacity(0.35) : Color(red: 0.06, green: 0.16, blue: 0.11)))
                    .overlay(Circle().stroke(isRec ? RacePalette.red : RacePalette.green, lineWidth: m.s(3)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, m.s(14))
        .background(shape.fill(RacePalette.rowBg))
        .clipShape(shape)
        .overlay(shape.stroke(needsYou ? RacePalette.orange : Color(white: 0.13), lineWidth: m.s(2)))
    }
}
