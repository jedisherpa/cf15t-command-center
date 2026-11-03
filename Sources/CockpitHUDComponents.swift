import SwiftUI

// MARK: - Mathematical Constants

enum MathConstants {
    static let phi: Double = 1.6180339887498949          // Golden Ratio φ = (1 + √5) / 2
    static let invPhi: Double = 0.6180339887498949       // Conjugate 1/φ = φ - 1 ≈ 61.8%
    static let goldenAngleRad: Double = 2.399963229728653 // 2π(1 - 1/φ) ≈ 137.507764°
    static let goldenSpiralB: Double = 0.30634896253     // (2 ln φ) / π
}

// MARK: - 1. Chamfered Supercar HUD Polygon Shape

struct CockpitChamferShape: Shape {
    var topLeftCut: CGFloat = 14
    var topRightCut: CGFloat = 14
    var bottomRightCut: CGFloat = 14
    var bottomLeftCut: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let tl = min(topLeftCut, min(w, h) * 0.4)
        let tr = min(topRightCut, min(w, h) * 0.4)
        let br = min(bottomRightCut, min(w, h) * 0.4)
        let bl = min(bottomLeftCut, min(w, h) * 0.4)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tr))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addLine(to: CGPoint(x: rect.maxX - br, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bl))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.closeSubpath()
        return path
    }
}

// MARK: - 2. Top Shift-Light & Real System Telemetry Strip

struct ShiftLightRevStrip: View {
    let totalCPULoad: Double      // 0..100+
    let isAnyMicLive: Bool
    let activeVoiceName: String
    let layoutExplanation: String
    let isTouchingScreen: Bool

    private let ledCount = 24

    var body: some View {
        let normalizedLoad = min(1.0, max(0.08, totalCPULoad / 65.0))
        let activeLEDs = Int(round(normalizedLoad * Double(ledCount)))

        HStack(spacing: 8) {
            // Left: Clear Explanation of Current Geometric Tiling Rule
            HStack(spacing: 6) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.18))
                Text(layoutExplanation)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(CockpitChamferShape(topLeftCut: 5, topRightCut: 5, bottomRightCut: 5, bottomLeftCut: 5))

            // Center: 24-Segment CPU Load & Voice Activity Strip
            HStack(spacing: 3.5) {
                ForEach(0..<ledCount, id: \.self) { idx in
                    let isOn = idx < activeLEDs || isTouchingScreen
                    let ledColor = shiftColor(for: idx, total: ledCount, isMicLive: isAnyMicLive)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(isOn ? ledColor : ledColor.opacity(0.13))
                        .frame(maxWidth: .infinity)
                        .frame(height: 10)
                        .shadow(color: isOn ? ledColor.opacity(0.85) : .clear, radius: 5, x: 0, y: 0)
                }
            }

            // Right: Clear Voice Routing & CPU Readout
            HStack(spacing: 6) {
                Circle()
                    .fill(isAnyMicLive ? Color(red: 0.15, green: 1.0, blue: 0.55) : Color.white.opacity(0.35))
                    .frame(width: 7, height: 7)
                Text(
                    isAnyMicLive
                        ? "🎙️ MIC LIVE → \(activeVoiceName.uppercased())"
                        : String(format: "🔇 MIC MUTED · TARGET: %@ · CPU %.1f%%", activeVoiceName.uppercased(), totalCPULoad)
                )
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(isAnyMicLive ? Color(red: 0.15, green: 1.0, blue: 0.55) : Color(red: 0.25, green: 0.82, blue: 1.0))
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(CockpitChamferShape(topLeftCut: 5, topRightCut: 5, bottomRightCut: 5, bottomLeftCut: 5))
        }
        .frame(height: 18)
    }

    private func shiftColor(for index: Int, total: Int, isMicLive: Bool) -> Color {
        let ratio = Double(index) / Double(max(1, total - 1))
        if ratio < 0.45 {
            return Color(red: 0.12, green: 0.96, blue: 0.52)
        } else if ratio < 0.75 {
            return Color(red: 1.0, green: 0.76, blue: 0.10)
        } else if ratio < 0.90 {
            return Color(red: 1.0, green: 0.22, blue: 0.20)
        } else {
            return isMicLive
                ? Color(red: 0.20, green: 0.85, blue: 1.0)
                : Color(red: 0.85, green: 0.25, blue: 1.0)
        }
    }
}

// MARK: - 3. Clean Proportional 240° Arc Gauge (CPU % and Mic Gain %)

struct CockpitArcGaugeView: View {
    let title: String
    let valueText: String
    let unitText: String
    let progress: Double // 0.0 .. 1.0
    let accentColor: Color
    let redlineColor: Color

    var body: some View {
        let clamped = min(1.0, max(0.0, progress))

        ZStack {
            // Clean 10% Radial Scale Ticks around the 240° sweep
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outerR = Double(min(size.width, size.height) * 0.46)
                for i in 0...10 {
                    let frac = Double(i) / 10.0
                    let deg = 146.0 + frac * 245.0
                    let rad = deg * Double.pi / 180.0
                    let innerOffset = (i % 5 == 0) ? 5.5 : 3.0
                    let p1 = CGPoint(
                        x: Double(center.x) + (outerR - innerOffset) * cos(rad),
                        y: Double(center.y) + (outerR - innerOffset) * sin(rad)
                    )
                    let p2 = CGPoint(
                        x: Double(center.x) + outerR * cos(rad),
                        y: Double(center.y) + outerR * sin(rad)
                    )
                    var tick = Path()
                    tick.move(to: p1)
                    tick.addLine(to: p2)
                    context.stroke(
                        tick,
                        with: .color(frac <= clamped ? accentColor.opacity(0.8) : Color.white.opacity(0.22)),
                        lineWidth: (i % 5 == 0) ? 1.6 : 1.0
                    )
                }
            }

            // Background Track Arc (240° sweep)
            Circle()
                .trim(from: 0.0, to: 0.68)
                .stroke(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 6.5, lineCap: .round, dash: [4, 3])
                )
                .rotationEffect(.degrees(146))

            // Active Neon Sweep Arc
            Circle()
                .trim(from: 0.0, to: CGFloat(clamped * 0.68))
                .stroke(
                    AngularGradient(
                        colors: [accentColor, accentColor, redlineColor],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(250)
                    ),
                    style: StrokeStyle(lineWidth: 7.0, lineCap: .round)
                )
                .rotationEffect(.degrees(146))
                .shadow(color: accentColor.opacity(0.75), radius: 5, x: 0, y: 0)

            // Center Digital Readout
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                Text(valueText)
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                Text(unitText)
                    .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(accentColor)
            }
            .offset(y: 2)
        }
        .frame(width: 78, height: 78)
    }
}

// MARK: - 4. Barycentric 5-Axis System Balance Radar (Shows Where Compute & Voice Are Focused)

struct WorkloadBalanceRadarView: View {
    let grokWeight: Double    // 0..1 (Grok Bot activity / focus)
    let dotWeight: Double     // 0..1 (Dot / ChatGPT activity / focus)
    let claudeCodexWeight: Double // 0..1 (Claude / Codex / Antigravity CPU)
    let voiceMicWeight: Double    // 0..1 (Live Microphone level)
    let appsWeight: Double        // 0..1 (Browser / Other apps)

    private let labels = ["GROK", "DOT", "AI", "MIC", "APPS"]

    var body: some View {
        let weights = [
            min(1.0, max(0.18, grokWeight)),
            min(1.0, max(0.18, dotWeight)),
            min(1.0, max(0.18, claudeCodexWeight)),
            min(1.0, max(0.18, voiceMicWeight)),
            min(1.0, max(0.18, appsWeight))
        ]

        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.34

                // Outer reference pentagon & axes
                var outerPoly = Path()
                for i in 0..<5 {
                    let angle = -Double.pi / 2.0 + Double(i) * (2.0 * Double.pi / 5.0)
                    let vertex = CGPoint(
                        x: center.x + CGFloat(cos(angle)) * radius,
                        y: center.y + CGFloat(sin(angle)) * radius
                    )
                    if i == 0 {
                        outerPoly.move(to: vertex)
                    } else {
                        outerPoly.addLine(to: vertex)
                    }

                    var spoke = Path()
                    spoke.move(to: center)
                    spoke.addLine(to: vertex)
                    context.stroke(spoke, with: .color(Color.white.opacity(0.15)), lineWidth: 1)
                }
                outerPoly.closeSubpath()
                context.stroke(outerPoly, with: .color(Color.white.opacity(0.25)), lineWidth: 1)

                // Active workload polygon + Barycenter (Center of Mass)
                var activePoly = Path()
                var sumX: CGFloat = 0
                var sumY: CGFloat = 0
                var totalW: CGFloat = 0

                for i in 0..<5 {
                    let angle = -Double.pi / 2.0 + Double(i) * (2.0 * Double.pi / 5.0)
                    let w = CGFloat(weights[i])
                    let pt = CGPoint(
                        x: center.x + CGFloat(cos(angle)) * radius * w,
                        y: center.y + CGFloat(sin(angle)) * radius * w
                    )
                    if i == 0 {
                        activePoly.move(to: pt)
                    } else {
                        activePoly.addLine(to: pt)
                    }
                    sumX += pt.x * w
                    sumY += pt.y * w
                    totalW += w
                }
                activePoly.closeSubpath()

                context.fill(activePoly, with: .color(Color(red: 0.15, green: 0.96, blue: 0.65).opacity(0.25)))
                context.stroke(activePoly, with: .color(Color(red: 0.15, green: 0.96, blue: 0.65)), lineWidth: 1.6)

                // Barycenter (Center-of-Mass) Dot showing where system focus is pulled
                if totalW > 0 {
                    let centroid = CGPoint(x: sumX / totalW, y: sumY / totalW)
                    let dotRect = CGRect(x: centroid.x - 3.5, y: centroid.y - 3.5, width: 7, height: 7)
                    context.fill(Path(ellipseIn: dotRect), with: .color(Color(red: 1.0, green: 0.78, blue: 0.18)))
                }
            }

            // Vertex Labels around the Pentagon
            Text("GROK")
                .font(.system(size: 6.5, weight: .black, design: .monospaced))
                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.18))
                .offset(x: 0, y: -32)
            Text("DOT")
                .font(.system(size: 6.5, weight: .black, design: .monospaced))
                .foregroundColor(Color(red: 0.15, green: 0.98, blue: 0.66))
                .offset(x: 29, y: -10)
            Text("AI")
                .font(.system(size: 6.5, weight: .black, design: .monospaced))
                .foregroundColor(Color(red: 0.25, green: 0.85, blue: 1.0))
                .offset(x: 20, y: 26)
            Text("MIC")
                .font(.system(size: 6.5, weight: .black, design: .monospaced))
                .foregroundColor(voiceMicWeight > 0.25 ? Color(red: 0.15, green: 1.0, blue: 0.55) : .white.opacity(0.5))
                .offset(x: -20, y: 26)
            Text("APPS")
                .font(.system(size: 6.5, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))
                .offset(x: -28, y: -10)
        }
        .frame(width: 76, height: 74)
        .allowsHitTesting(false)
    }
}

// MARK: - 5. Meaningful Geometric & Causal Telemetry Overlay (No Fake Window-to-Window Dots!)

struct WindowTelemetryNode {
    let window: MonitoredWindow
    let rect: CGRect
    let rankIndex: Int
    let areaPercent: Double
    let cpuPercent: Double
    let voiceChannelCode: String?  // "CH-01" or "CH-02"
    let voiceDisplayName: String?  // "Grok Bot" or "Dot"
    let isActiveVoiceTarget: Bool
    let isMicLive: Bool
}

struct MeaningfulGeometryOverlay: View {
    let nodes: [WindowTelemetryNode]
    let mode: TilingLayoutMode
    let canvasSize: CGSize
    let micVolume: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulsePhase = CGFloat(t.truncatingRemainder(dividingBy: 1.4) / 1.4)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    // 1. In Golden φ-Spiral mode, draw the Fibonacci Spiral Curve & Golden Section Dividers
                    //    so it's 100% clear how the Golden Ratio (1.618) is sizing windows #1 -> #2 -> #3 -> #4
                    if mode == .goldenFibonacciSpiral && nodes.count >= 2 {
                        drawGoldenSpiralBlueprint(context: &context, rects: nodes.map(\.rect))
                    }

                    // 2. Real Voice Routing Conduit (Left Voice Deck -> Active Voice Target Window: Grok Bot or Dot)
                    if let voiceNode = nodes.first(where: { $0.isActiveVoiceTarget }) {
                        let startPt = CGPoint(x: 0, y: voiceNode.rect.midY)
                        let endPt = CGPoint(x: voiceNode.rect.minX + 12, y: voiceNode.rect.midY)
                        var conduit = Path()
                        conduit.move(to: startPt)
                        conduit.addLine(to: endPt)

                        let conduitColor = voiceNode.isMicLive
                            ? Color(red: 0.15, green: 1.0, blue: 0.58)
                            : Color(red: 1.0, green: 0.78, blue: 0.18).opacity(0.55)

                        context.stroke(
                            conduit,
                            with: .color(conduitColor),
                            style: StrokeStyle(
                                lineWidth: voiceNode.isMicLive ? 3.0 : 1.5,
                                dash: voiceNode.isMicLive ? [] : [6, 5]
                            )
                        )

                        // ONLY animate audio pulses when the Microphone is actually LIVE!
                        if voiceNode.isMicLive {
                            for k in 0..<3 {
                                let frac = (pulsePhase + CGFloat(k) / 3.0).truncatingRemainder(dividingBy: 1.0)
                                let px = startPt.x + (endPt.x - startPt.x) * frac
                                let py = startPt.y + (endPt.y - startPt.y) * frac
                                let radius: CGFloat = 4.0 + CGFloat(micVolume) * 3.0
                                let dotRect = CGRect(x: px - radius, y: py - radius, width: radius * 2, height: radius * 2)
                                context.fill(Path(ellipseIn: dotRect), with: .color(Color(red: 0.15, green: 1.0, blue: 0.58)))
                            }
                        }
                    }

                    // 3. Real Active CPU Compute Stream (Right AI Engine Deck -> Windows actively burning >= 1.5% CPU)
                    for node in nodes where node.cpuPercent >= 1.5 {
                        let startPt = CGPoint(x: size.width, y: node.rect.midY)
                        let endPt = CGPoint(x: node.rect.maxX - 12, y: node.rect.midY)
                        var computeLine = Path()
                        computeLine.move(to: startPt)
                        computeLine.addLine(to: endPt)

                        let lineColor = Color(red: 1.0, green: 0.52, blue: 0.16)
                        context.stroke(
                            computeLine,
                            with: .color(lineColor.opacity(0.65)),
                            style: StrokeStyle(lineWidth: 2.0, dash: [5, 4])
                        )

                        // Pulse speed scales with actual CPU %
                        let cpuSpeed = min(3.0, max(0.5, node.cpuPercent / 15.0))
                        let cpuPhase = CGFloat((t * cpuSpeed).truncatingRemainder(dividingBy: 1.0))
                        let px = startPt.x + (endPt.x - startPt.x) * cpuPhase
                        let py = startPt.y + (endPt.y - startPt.y) * cpuPhase
                        let dotRect = CGRect(x: px - 4, y: py - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: dotRect), with: .color(lineColor))
                    }
                }

                // Clear, Self-Explanatory Callout Label on Active Voice Conduit
                if let voiceNode = nodes.first(where: { $0.isActiveVoiceTarget }) {
                    let voiceName = (voiceNode.voiceDisplayName ?? voiceNode.window.appName).uppercased()
                    HStack(spacing: 5) {
                        Image(systemName: voiceNode.isMicLive ? "waveform.badge.mic" : "mic.slash.fill")
                            .font(.system(size: 10, weight: .black))
                        Text(
                            voiceNode.isMicLive
                                ? "LIVE MIC AUDIO ──▶ \(voiceName)"
                                : "VOICE ROUTED TO \(voiceName) (MIC MUTED)"
                        )
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.88))
                    .foregroundColor(
                        voiceNode.isMicLive
                            ? Color(red: 0.15, green: 1.0, blue: 0.58)
                            : Color(red: 1.0, green: 0.78, blue: 0.18)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                voiceNode.isMicLive
                                    ? Color(red: 0.15, green: 1.0, blue: 0.58)
                                    : Color(red: 1.0, green: 0.78, blue: 0.18).opacity(0.6),
                                lineWidth: 1.2
                            )
                    )
                    .position(
                        x: max(115, voiceNode.rect.minX * 0.5),
                        y: max(24, min(canvasSize.height - 24, voiceNode.rect.midY - 18))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawGoldenSpiralBlueprint(context: inout GraphicsContext, rects: [CGRect]) {
        var spiralPath = Path()
        for (i, r) in rects.enumerated() {
            let phase = i % 4
            let startPt: CGPoint
            let endPt: CGPoint
            let ctrlPt: CGPoint

            switch phase {
            case 0: // Left chamber: bottom-left -> top-right
                startPt = CGPoint(x: r.minX, y: r.maxY)
                endPt = CGPoint(x: r.maxX, y: r.minY)
                ctrlPt = CGPoint(x: r.minX, y: r.minY)
            case 1: // Top chamber: top-left -> bottom-right
                startPt = CGPoint(x: r.minX, y: r.minY)
                endPt = CGPoint(x: r.maxX, y: r.maxY)
                ctrlPt = CGPoint(x: r.maxX, y: r.minY)
            case 2: // Right chamber: top-right -> bottom-left
                startPt = CGPoint(x: r.maxX, y: r.minY)
                endPt = CGPoint(x: r.minX, y: r.maxY)
                ctrlPt = CGPoint(x: r.maxX, y: r.maxY)
            default: // Bottom chamber: bottom-right -> top-left
                startPt = CGPoint(x: r.maxX, y: r.maxY)
                endPt = CGPoint(x: r.minX, y: r.minY)
                ctrlPt = CGPoint(x: r.minX, y: r.maxY)
            }

            if i == 0 {
                spiralPath.move(to: startPt)
            } else {
                spiralPath.addLine(to: startPt)
            }
            spiralPath.addQuadCurve(to: endPt, control: ctrlPt)
        }

        context.stroke(
            spiralPath,
            with: .color(Color(red: 1.0, green: 0.80, blue: 0.16).opacity(0.70)),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [8, 5])
        )
    }
}

// MARK: - 6. Segmented Telemetry RPM Bar

struct SegmentedTelemetryBar: View {
    let fraction: Double // 0.0 .. 1.0
    let segmentCount: Int
    let activeColor: Color

    var body: some View {
        let litCount = max(1, Int(ceil(min(1.0, max(0.0, fraction)) * Double(segmentCount))))

        HStack(spacing: 2.5) {
            ForEach(0..<segmentCount, id: \.self) { idx in
                let isLit = idx < litCount && fraction > 0.001
                let segColor: Color = {
                    if idx >= Int(Double(segmentCount) * 0.8) {
                        return Color(red: 1.0, green: 0.26, blue: 0.24)
                    } else if idx >= Int(Double(segmentCount) * 0.6) {
                        return Color(red: 1.0, green: 0.78, blue: 0.15)
                    }
                    return activeColor
                }()

                Rectangle()
                    .fill(isLit ? segColor : Color.white.opacity(0.10))
                    .frame(width: 5, height: 10)
            }
        }
    }
}

// MARK: - 7. Coordinate Grid + Golden Section Background

struct CockpitCarbonBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.07),
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.03, green: 0.04, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                let gridColor = Color(red: 0.15, green: 0.75, blue: 1.0).opacity(0.04)
                let step: CGFloat = 48

                var x: CGFloat = 0
                while x <= size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(p, with: .color(gridColor), lineWidth: 1)
                    x += step
                }

                var y: CGFloat = 0
                while y <= size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(p, with: .color(gridColor), lineWidth: 1)
                    y += step
                }
            }
        }
    }
}

// MARK: - 8. HUD Corner Target Brackets

struct HUDCornerBrackets: View {
    let color: Color
    let lineWidth: CGFloat
    let length: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let L = min(length, min(w, h) * 0.25)

            Path { p in
                p.move(to: CGPoint(x: 0, y: L))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: L, y: 0))

                p.move(to: CGPoint(x: w - L, y: 0))
                p.addLine(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: L))

                p.move(to: CGPoint(x: w, y: h - L))
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w - L, y: h))

                p.move(to: CGPoint(x: L, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: h - L))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 9. Multi-Touch CF15T Reticle & Distance Overlay

struct GeometricTouchSimplexOverlay: View {
    let contacts: [SiSTouchContact]

    var body: some View {
        GeometryReader { fullGeo in
            let points: [(contact: SiSTouchContact, pt: CGPoint)] = contacts.map { c in
                (c, CGPoint(x: c.normalizedX * fullGeo.size.width, y: c.normalizedY * fullGeo.size.height))
            }

            ZStack {
                // Multi-finger distance measurement when 2+ fingers touch the CF15T
                if points.count >= 2 {
                    Canvas { context, _ in
                        for i in 0..<points.count {
                            for j in (i + 1)..<points.count {
                                let p1 = points[i].pt
                                let p2 = points[j].pt
                                var chord = Path()
                                chord.move(to: p1)
                                chord.addLine(to: p2)
                                context.stroke(
                                    chord,
                                    with: .color(Color(red: 0.15, green: 1.0, blue: 0.65).opacity(0.85)),
                                    lineWidth: 2.0
                                )
                            }
                        }
                    }
                }

                ForEach(points, id: \.contact.id) { item in
                    let c = item.contact
                    let pt = item.pt
                    let pxX = Int(round(c.normalizedX * 1920))
                    let pxY = Int(round(c.normalizedY * 1080))

                    ZStack {
                        HUDCornerBrackets(
                            color: Color(red: 0.15, green: 1.0, blue: 0.62),
                            lineWidth: 2.5,
                            length: 18
                        )
                        .frame(width: 78, height: 78)

                        Circle()
                            .stroke(Color(red: 1.0, green: 0.42, blue: 0.15), lineWidth: 2.0)
                            .frame(width: 48, height: 48)

                        Circle()
                            .fill(Color(red: 0.15, green: 1.0, blue: 0.62).opacity(0.30))
                            .frame(width: 22, height: 22)

                        Text("TOUCH (\(pxX), \(pxY) px)")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.88))
                            .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))
                            .offset(y: 50)
                    }
                    .position(x: pt.x, y: pt.y)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
