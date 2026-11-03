import SwiftUI

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

// MARK: - 2. F1 / GT3 Top Shift-Light LED Rev Strip

struct ShiftLightRevStrip: View {
    let totalCPULoad: Double      // 0..100+
    let isAnyMicLive: Bool
    let isTouchingScreen: Bool

    private let ledCount = 22

    var body: some View {
        let normalizedLoad = min(1.0, max(0.18, totalCPULoad / 65.0))
        let activeLEDs = Int(round(normalizedLoad * Double(ledCount)))

        HStack(spacing: 6) {
            // Left Pit-Lane Tag
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(Color(red: 1.0, green: 0.38, blue: 0.12))
                Text("CF15T GT-TELEMETRY // M4-ECU")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(CockpitChamferShape(topLeftCut: 6, topRightCut: 6, bottomRightCut: 6, bottomLeftCut: 6))

            // 22-Segment F1 Shift Light Array
            HStack(spacing: 4) {
                ForEach(0..<ledCount, id: \.self) { idx in
                    let isOn = idx < activeLEDs || isTouchingScreen
                    let ledColor = shiftColor(for: idx, total: ledCount, isMicLive: isAnyMicLive)

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(isOn ? ledColor : ledColor.opacity(0.14))
                        .frame(maxWidth: .infinity)
                        .frame(height: 10)
                        .shadow(color: isOn ? ledColor.opacity(0.85) : .clear, radius: 5, x: 0, y: 0)
                }
            }

            // Right RPM / Radio Tag
            HStack(spacing: 6) {
                Circle()
                    .fill(isAnyMicLive ? Color(red: 0.15, green: 1.0, blue: 0.55) : Color(red: 0.25, green: 0.82, blue: 1.0))
                    .frame(width: 7, height: 7)
                Text(isAnyMicLive ? "PIT RADIO: TX LIVE" : String(format: "LOAD: %04.0f RPM", min(9999, totalCPULoad * 115 + 850)))
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(isAnyMicLive ? Color(red: 0.15, green: 1.0, blue: 0.55) : Color(red: 0.25, green: 0.82, blue: 1.0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(CockpitChamferShape(topLeftCut: 6, topRightCut: 6, bottomRightCut: 6, bottomLeftCut: 6))
        }
        .frame(height: 18)
    }

    private func shiftColor(for index: Int, total: Int, isMicLive: Bool) -> Color {
        let ratio = Double(index) / Double(max(1, total - 1))
        if ratio < 0.45 {
            return Color(red: 0.12, green: 0.96, blue: 0.52) // Racing Green
        } else if ratio < 0.75 {
            return Color(red: 1.0, green: 0.76, blue: 0.10)  // Shift Amber
        } else if ratio < 0.90 {
            return Color(red: 1.0, green: 0.22, blue: 0.20)  // Redline Crimson
        } else {
            return isMicLive
                ? Color(red: 0.20, green: 0.85, blue: 1.0)   // F1 Pit Limiter Cyan-Blue
                : Color(red: 0.85, green: 0.25, blue: 1.0)   // Overboost Violet
        }
    }
}

// MARK: - 3. Sweeping 240-Degree Supercar Tachometer / Boost Gauge

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
            // Outer Bezel Ring
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 2)

            // Background Track Arc (150 deg to 390 deg = 240 deg sweep)
            Circle()
                .trim(from: 0.0, to: 0.68)
                .stroke(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [4, 3])
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
                    style: StrokeStyle(lineWidth: 7.5, lineCap: .round)
                )
                .rotationEffect(.degrees(146))
                .shadow(color: accentColor.opacity(0.75), radius: 5, x: 0, y: 0)

            // Center Digital Readout
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Text(valueText)
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                Text(unitText)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(accentColor)
            }
            .offset(y: 3)
        }
        .frame(width: 76, height: 76)
    }
}

// MARK: - 4. Segmented Telemetry RPM Bar (For Agent & Task Rows)

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

// MARK: - 5. Carbon-Fiber + Telemetry Grid Background

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

            // Subtle Horizon Perspective Grid
            Canvas { context, size in
                let gridColor = Color(red: 0.15, green: 0.75, blue: 1.0).opacity(0.045)
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

// MARK: - 6. HUD Corner Target Brackets

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
                // Top-left
                p.move(to: CGPoint(x: 0, y: L))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: L, y: 0))

                // Top-right
                p.move(to: CGPoint(x: w - L, y: 0))
                p.addLine(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: L))

                // Bottom-right
                p.move(to: CGPoint(x: w, y: h - L))
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w - L, y: h))

                // Bottom-left
                p.move(to: CGPoint(x: L, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: h - L))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
        }
        .allowsHitTesting(false)
    }
}
