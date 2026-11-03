import SwiftUI

// MARK: - Mathematical Constants

enum MathConstants {
    static let phi: Double = 1.6180339887498949          // Golden Ratio φ = (1 + √5) / 2
    static let invPhi: Double = 0.6180339887498949       // Conjugate 1/φ = φ - 1
    static let goldenAngleRad: Double = 2.399963229728653 // 2π(1 - 1/φ) ≈ 137.507764°
    static let goldenSpiralB: Double = 0.30634896253     // (2 ln φ) / π
}

// MARK: - 1. Chamfered Supercar / Polytope HUD Polygon Shape

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

// MARK: - 2. Top Shift-Light & Differential Geometry Invariant Strip

struct ShiftLightRevStrip: View {
    let totalCPULoad: Double      // 0..100+
    let isAnyMicLive: Bool
    let isTouchingScreen: Bool

    private let ledCount = 24

    var body: some View {
        let normalizedLoad = min(1.0, max(0.18, totalCPULoad / 65.0))
        let activeLEDs = Int(round(normalizedLoad * Double(ledCount)))
        // Gaussian curvature proxy K and metric determinant √|g|
        let curvatureK = -1.0 - (totalCPULoad / 100.0) * 0.618
        let metricDet = 4.0 / pow(max(0.15, 1.0 - normalizedLoad * 0.45), 2)

        HStack(spacing: 6) {
            // Left Differential Geometry Invariant Tag
            HStack(spacing: 6) {
                Image(systemName: "function")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.18))
                Text(String(format: "φ=%.5f // K=%.3f // √|g|=%.2f", MathConstants.phi, curvatureK, metricDet))
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(CockpitChamferShape(topLeftCut: 5, topRightCut: 5, bottomRightCut: 5, bottomLeftCut: 5))

            // 24-Segment F1 Harmonic Shift Light Array
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

            // Right Symplectic / Radio Invariant Tag
            HStack(spacing: 6) {
                Circle()
                    .fill(isAnyMicLive ? Color(red: 0.15, green: 1.0, blue: 0.55) : Color(red: 0.25, green: 0.82, blue: 1.0))
                    .frame(width: 7, height: 7)
                Text(isAnyMicLive ? "HOPF FIBRATION: TX LOCKED" : String(format: "ω = %04.0f RAD/S", min(9999, totalCPULoad * 115 + 850)))
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(isAnyMicLive ? Color(red: 0.15, green: 1.0, blue: 0.55) : Color(red: 0.25, green: 0.82, blue: 1.0))
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

// MARK: - 3. Sweeping 240° Tachometer with Inner Rhodonea Rose Curve r(θ) = cos(kθ)

struct CockpitArcGaugeView: View {
    let title: String
    let valueText: String
    let unitText: String
    let progress: Double // 0.0 .. 1.0
    let accentColor: Color
    let redlineColor: Color
    var harmonicK: Double = 3.0 // Rhodonea petal parameter k = p/q

    var body: some View {
        let clamped = min(1.0, max(0.0, progress))

        ZStack {
            // Inner Rhodonea Rose Curve r(θ) = R cos(kθ) + Phyllotaxis Golden Ticks
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.36
                let k = harmonicK + round(clamped * 2.0)

                var rosePath = Path()
                let steps = 120
                for i in 0...steps {
                    let theta = Double(i) / Double(steps) * (2.0 * Double.pi)
                    let r = Double(radius) * cos(k * theta)
                    let x = Double(center.x) + r * cos(theta)
                    let y = Double(center.y) + r * sin(theta)
                    if i == 0 {
                        rosePath.move(to: CGPoint(x: x, y: y))
                    } else {
                        rosePath.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(rosePath, with: .color(accentColor.opacity(0.24)), lineWidth: 1.0)

                // Golden-angle ticks on unit circle
                let outerR = Double(min(size.width, size.height) * 0.47)
                for n in 0..<13 {
                    let angle = Double(n) * MathConstants.goldenAngleRad
                    let p1 = CGPoint(
                        x: Double(center.x) + (outerR - 3.0) * cos(angle),
                        y: Double(center.y) + (outerR - 3.0) * sin(angle)
                    )
                    let p2 = CGPoint(
                        x: Double(center.x) + outerR * cos(angle),
                        y: Double(center.y) + outerR * sin(angle)
                    )
                    var tick = Path()
                    tick.move(to: p1)
                    tick.addLine(to: p2)
                    context.stroke(tick, with: .color(Color.white.opacity(0.22)), lineWidth: 1)
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
                    .foregroundColor(.white.opacity(0.6))
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

// MARK: - 4. Stereographic Clifford Torus / Hopf Fibration S³ -> ℝ² Phase-Space Orb

struct CliffordHopfAttractorOrb: View {
    let cpuLoad: Double
    let isMicLive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let speed = 0.65 + min(2.5, cpuLoad / 35.0)
            let phase = t * speed

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let scale = min(size.width, size.height) * 0.27

                // Draw 4 interlocking Hopf fibers on the Clifford Torus in S³ projected stereographically to ℝ²
                let fiberCount = 4
                let pWinding = 2.0
                let qWinding = isMicLive ? 5.0 : 3.0

                for f in 0..<fiberCount {
                    let fiberOffset = Double(f) * (Double.pi / Double(fiberCount))
                    var path = Path()
                    let samples = 90

                    for s in 0...samples {
                        let u = (Double(s) / Double(samples)) * 2.0 * Double.pi
                        let theta = pWinding * u + phase
                        let phi = qWinding * u + fiberOffset - phase * 0.618

                        // Point on Clifford Torus in S³ ⊂ ℝ⁴: (cos θ, sin θ, cos φ, sin φ) / √2
                        let invSqrt2 = 0.70710678118
                        let x1 = invSqrt2 * cos(theta)
                        let x2 = invSqrt2 * sin(theta)
                        let x3 = invSqrt2 * cos(phi)
                        let x4 = invSqrt2 * sin(phi)

                        // 3D rotation in (x1, x2, x3, x4) before stereographic projection from pole (0,0,0,1.35)
                        let denom = max(0.32, 1.35 - x4)
                        let px = x1 / denom
                        let py = x2 / denom
                        let pz = x3 / denom

                        // Isometric projection onto 2D instrument plane
                        let rotA = phase * 0.4
                        let rx = px * cos(rotA) - pz * sin(rotA)
                        let ry = py * 0.85 + (px * sin(rotA) + pz * cos(rotA)) * 0.35

                        let pt = CGPoint(
                            x: center.x + CGFloat(rx) * scale,
                            y: center.y + CGFloat(ry) * scale
                        )
                        if s == 0 {
                            path.move(to: pt)
                        } else {
                            path.addLine(to: pt)
                        }
                    }

                    let fiberColor: Color = (f % 2 == 0)
                        ? Color(red: 0.15, green: 0.96, blue: 0.68).opacity(0.65)
                        : Color(red: 1.0, green: 0.52, blue: 0.18).opacity(0.55)
                    context.stroke(path, with: .color(fiberColor), lineWidth: 1.3)
                }
            }
        }
        .frame(width: 68, height: 68)
        .allowsHitTesting(false)
    }
}

// MARK: - 5. Poincaré Hyperbolic Geodesic Web & Golden Spiral Overlay

struct HyperbolicGeodesicWebOverlay: View {
    let layoutRects: [CGRect]
    let mode: TilingLayoutMode
    let canvasSize: CGSize

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulsePhase = CGFloat(t.truncatingRemainder(dividingBy: 2.0) / 2.0)

            Canvas { context, size in
                guard layoutRects.count >= 2 else { return }
                let diskCenter = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
                let diskRadius = hypot(size.width, size.height) * 0.52

                // 1. Faint Poincaré Conformal Disk concentric horocycles & hyperbolic metric circles
                for ring in 1...4 {
                    let tanhR = CGFloat(tanh(Double(ring) * 0.45))
                    let r = diskRadius * tanhR * 0.72
                    let circleRect = CGRect(x: diskCenter.x - r, y: diskCenter.y - r, width: r * 2, height: r * 2)
                    context.stroke(
                        Path(ellipseIn: circleRect),
                        with: .color(Color(red: 0.20, green: 0.85, blue: 1.0).opacity(0.08)),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                    )
                }

                // 2. If Golden φ-Spiral mode is active, draw the exact Logarithmic Golden Spiral r(θ) = a·φ^(2θ/π)
                //    and quarter-circle osculating Fibonacci arcs across the chambers!
                if mode == .goldenFibonacciSpiral {
                    drawGoldenSpiralCurve(context: &context, rects: layoutRects, size: size)
                }

                // 3. Draw Poincaré Hyperbolic Geodesic Arcs from Center Stage (c₀) to every Perimeter Window (cₖ)
                let c0 = CGPoint(x: layoutRects[0].midX, y: layoutRects[0].midY)
                for idx in 1..<layoutRects.count {
                    let ck = CGPoint(x: layoutRects[idx].midX, y: layoutRects[idx].midY)
                    let geoPath = hyperbolicGeodesicQuadPath(from: c0, to: ck, diskCenter: diskCenter)

                    context.stroke(
                        geoPath,
                        with: .color(Color(red: 0.15, green: 0.98, blue: 0.66).opacity(0.55)),
                        style: StrokeStyle(lineWidth: 1.8, dash: [7, 5])
                    )

                    // Animated parallel-transport energy packet along geodesic ck -> c0
                    let packetPt = quadBezierPoint(from: ck, to: c0, diskCenter: diskCenter, t: pulsePhase)
                    let dotRect = CGRect(x: packetPt.x - 4, y: packetPt.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: dotRect), with: .color(Color(red: 1.0, green: 0.78, blue: 0.18)))

                    // Draw Simplicial Delaunay perimeter chord to next perimeter node
                    if idx + 1 < layoutRects.count {
                        let cNext = CGPoint(x: layoutRects[idx + 1].midX, y: layoutRects[idx + 1].midY)
                        var chord = Path()
                        chord.move(to: ck)
                        chord.addLine(to: cNext)
                        context.stroke(
                            chord,
                            with: .color(Color(red: 1.0, green: 0.45, blue: 0.18).opacity(0.30)),
                            style: StrokeStyle(lineWidth: 1.0, dash: [3, 4])
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Approximates the orthogonal Poincaré hyperbolic geodesic between p1 and p2
    /// by bending toward the conformal origin (diskCenter) proportional to chord length.
    private func hyperbolicGeodesicQuadPath(from p1: CGPoint, to p2: CGPoint, diskCenter: CGPoint) -> Path {
        let mid = CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
        // Bend control point inward toward diskCenter (hyperbolic negative curvature K = -1)
        let ctrl = CGPoint(
            x: mid.x + (diskCenter.x - mid.x) * 0.34,
            y: mid.y + (diskCenter.y - mid.y) * 0.34
        )
        var path = Path()
        path.move(to: p1)
        path.addQuadCurve(to: p2, control: ctrl)
        return path
    }

    private func quadBezierPoint(from p1: CGPoint, to p2: CGPoint, diskCenter: CGPoint, t: CGFloat) -> CGPoint {
        let mid = CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
        let ctrl = CGPoint(
            x: mid.x + (diskCenter.x - mid.x) * 0.34,
            y: mid.y + (diskCenter.y - mid.y) * 0.34
        )
        let u = 1.0 - t
        let x = u * u * p1.x + 2 * u * t * ctrl.x + t * t * p2.x
        let y = u * u * p1.y + 2 * u * t * ctrl.y + t * t * p2.y
        return CGPoint(x: x, y: y)
    }

    private func drawGoldenSpiralCurve(context: inout GraphicsContext, rects: [CGRect], size: CGSize) {
        var spiralPath = Path()
        for (i, r) in rects.enumerated() {
            let phase = i % 4
            let startPt: CGPoint
            let endPt: CGPoint
            let ctrlPt: CGPoint

            switch phase {
            case 0: // Left chamber: sweep bottom-left -> top-right
                startPt = CGPoint(x: r.minX, y: r.maxY)
                endPt = CGPoint(x: r.maxX, y: r.minY)
                ctrlPt = CGPoint(x: r.minX, y: r.minY)
            case 1: // Top chamber: sweep top-left -> bottom-right
                startPt = CGPoint(x: r.minX, y: r.minY)
                endPt = CGPoint(x: r.maxX, y: r.maxY)
                ctrlPt = CGPoint(x: r.maxX, y: r.minY)
            case 2: // Right chamber: sweep top-right -> bottom-left
                startPt = CGPoint(x: r.maxX, y: r.minY)
                endPt = CGPoint(x: r.minX, y: r.maxY)
                ctrlPt = CGPoint(x: r.maxX, y: r.maxY)
            default: // Bottom chamber: sweep bottom-right -> top-left
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
            with: .color(Color(red: 1.0, green: 0.80, blue: 0.16).opacity(0.82)),
            style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
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

// MARK: - 7. Projective Manifold + Golden Ratio Grid Background

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

            // Coordinate Lattice & Golden Ratio Crosshairs
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

                // Golden section lines x = W/φ and y = H/φ
                let phiX = size.width * CGFloat(MathConstants.invPhi)
                let phiY = size.height * CGFloat(MathConstants.invPhi)
                var goldPath = Path()
                goldPath.move(to: CGPoint(x: phiX, y: 0))
                goldPath.addLine(to: CGPoint(x: phiX, y: size.height))
                goldPath.move(to: CGPoint(x: 0, y: phiY))
                goldPath.addLine(to: CGPoint(x: size.width, y: phiY))
                context.stroke(
                    goldPath,
                    with: .color(Color(red: 1.0, green: 0.78, blue: 0.18).opacity(0.08)),
                    style: StrokeStyle(lineWidth: 1, dash: [8, 6])
                )
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

// MARK: - 9. Multi-Touch Gielis Superformula & Voronoi Simplex Overlay

struct GeometricTouchSimplexOverlay: View {
    let contacts: [SiSTouchContact]

    var body: some View {
        GeometryReader { fullGeo in
            let points: [(contact: SiSTouchContact, pt: CGPoint)] = contacts.map { c in
                (c, CGPoint(x: c.normalizedX * fullGeo.size.width, y: c.normalizedY * fullGeo.size.height))
            }

            ZStack {
                // Draw Simplicial Chords & Voronoi Perpendicular Bisectors when 2+ fingers touch
                if points.count >= 2 {
                    Canvas { context, size in
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

                                // Voronoi perpendicular bisector segment
                                let mid = CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
                                let dx = p2.x - p1.x
                                let dy = p2.y - p1.y
                                let nx = -dy * 0.35
                                let ny = dx * 0.35
                                var bisector = Path()
                                bisector.move(to: CGPoint(x: mid.x - nx, y: mid.y - ny))
                                bisector.addLine(to: CGPoint(x: mid.x + nx, y: mid.y + ny))
                                context.stroke(
                                    bisector,
                                    with: .color(Color(red: 1.0, green: 0.78, blue: 0.18).opacity(0.75)),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                                )
                            }
                        }
                    }
                }

                // Individual Superformula / Astroid Touch Reticle at each finger
                ForEach(points, id: \.contact.id) { item in
                    let c = item.contact
                    let pt = item.pt
                    // Complex plane coordinates z = x + iy in [-1, 1]²
                    let zx = (c.normalizedX - 0.5) * 2.0
                    let zy = (0.5 - c.normalizedY) * 2.0
                    let rNorm = hypot(zx, zy)
                    let thetaRad = atan2(zy, zx)

                    ZStack {
                        HUDCornerBrackets(
                            color: Color(red: 0.15, green: 1.0, blue: 0.62),
                            lineWidth: 2.5,
                            length: 18
                        )
                        .frame(width: 82, height: 82)

                        // Astroid / Superellipse Star
                        Canvas { ctx, sz in
                            let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                            let R = Double(min(sz.width, sz.height) * 0.44)
                            var star = Path()
                            for k in 0...80 {
                                let a = Double(k) / 80.0 * 2.0 * Double.pi
                                // 6-fold symmetric superformula
                                let r = R * (0.78 + 0.22 * cos(6.0 * a))
                                let px = Double(center.x) + r * cos(a)
                                let py = Double(center.y) + r * sin(a)
                                if k == 0 {
                                    star.move(to: CGPoint(x: px, y: py))
                                } else {
                                    star.addLine(to: CGPoint(x: px, y: py))
                                }
                            }
                            ctx.stroke(star, with: .color(Color(red: 1.0, green: 0.42, blue: 0.15)), lineWidth: 2.0)
                        }
                        .frame(width: 64, height: 64)

                        Circle()
                            .fill(Color(red: 0.15, green: 1.0, blue: 0.62).opacity(0.28))
                            .frame(width: 26, height: 26)

                        Text(String(format: "z=%.2f%+.2fi | r=%.2f ∠%.2f rad", zx, zy, rNorm, thetaRad))
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.black.opacity(0.88))
                            .foregroundColor(Color(red: 0.15, green: 1.0, blue: 0.62))
                            .offset(y: 52)
                    }
                    .position(x: pt.x, y: pt.y)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
