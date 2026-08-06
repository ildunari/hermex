import SwiftUI

// ThinkingOrbView is a SwiftUI/Canvas port of the "thinking orbs" dotted
// 3D spinners by Jakub Antalik — https://github.com/Jakubantalik/thinking-orbs
// (MIT License). The math (deterministic hash, tilted-orbit particles, the
// scan-meridian globe, and the constellation web) is ported faithfully from
// src/engine/{core,orbits,lattice,web}.ts using the size-20 inline presets
// from src/presets.ts. See Resources/ThirdPartyNotices/NOTICE.txt.

enum ThinkingOrbState {
    case working
    case searching
    case connecting

    /// Maps a tool name to the orb state that best matches the activity.
    /// Search-like tools scan, terminal/edit tools work, network/session
    /// tools connect. Defaults to `.working`.
    static func forTool(name: String?) -> ThinkingOrbState {
        let name = name?.lowercased() ?? ""

        let searching = ["search", "read", "grep", "list", "web", "find", "glob", "fetch", "view"]
        if searching.contains(where: { name.contains($0) }) {
            return .searching
        }

        let connecting = ["network", "server", "session", "connect", "http", "request", "api"]
        if connecting.contains(where: { name.contains($0) }) {
            return .connecting
        }

        return .working
    }
}

/// An animated, monochrome dotted-3D orb used in reasoning/tool activity
/// headers while work is in flight. Renders with `TimelineView(.animation)`
/// plus `Canvas`; honors Reduce Motion by drawing a single static frame.
struct ThinkingOrbView: View {
    let state: ThinkingOrbState
    var size: CGFloat = 20
    var color: Color = .secondary
    var paused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fixed timestamp used for the static Reduce Motion frame.
    private static let staticTime: Double = 1.7

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, canvasSize in
                    Self.draw(
                        context: context,
                        size: min(canvasSize.width, canvasSize.height),
                        state: state,
                        time: Self.staticTime,
                        color: color
                    )
                }
            } else {
                TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
                    Canvas { context, canvasSize in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 86_400)
                        Self.draw(
                            context: context,
                            size: min(canvasSize.width, canvasSize.height),
                            state: state,
                            time: t,
                            color: color
                        )
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Shared geometry primitives (port of engine/core.ts)

    /// A projected dot ready to paint. `opacity` folds the original ink
    /// value ("white") and alpha into a single tint opacity: on paper,
    /// ink 0 (darkest) is equivalent to full-opacity tint, so
    /// `opacity = alpha * (1 - white)` preserves the depth language in a
    /// single accent color on both light and dark surfaces.
    private struct Dot {
        var x: Double
        var y: Double
        var z: Double
        var r: Double
        var opacity: Double
    }

    private struct Line {
        var x1: Double
        var y1: Double
        var x2: Double
        var y2: Double
        var opacity: Double
        var width: Double
    }

    /// Deterministic hash in [0, 1). Port of `hashD`.
    private static func hashD(_ a: Double, _ b: Double) -> Double {
        let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return h - h.rounded(.down)
    }

    private static func frac(_ x: Double) -> Double {
        x - x.rounded(.down)
    }

    private static func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double {
        a + (b - a) * f
    }

    /// Value noise on a 2D lattice. Port of `vnoise`.
    private static func vnoise(_ x: Double, _ y: Double) -> Double {
        let xi = x.rounded(.down)
        let yi = y.rounded(.down)
        var fx = x - xi
        var fy = y - yi
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        let a = hashD(xi, yi)
        let b = hashD(xi + 1, yi)
        let c = hashD(xi, yi + 1)
        let d = hashD(xi + 1, yi + 1)
        return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
    }

    /// Stable directions on a unit sphere (Fibonacci lattice). Port of `fibDir`.
    private static func fibDir(_ i: Int, _ n: Int) -> (Double, Double, Double) {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let y = 1 - (2 * (Double(i) + 0.5)) / Double(n)
        let rad = (1 - y * y).squareRoot()
        let a = Double(i) * golden
        return (rad * cos(a), y, rad * sin(a))
    }

    /// Shortest signed angular distance, wrapped to (-π, π]. Port of `angleDelta`.
    private static func angleDelta(_ a: Double, _ b: Double) -> Double {
        atan2(sin(a - b), cos(a - b))
    }

    /// Shared spin + tilt + orthographic projection. Port of `makeProj`.
    private static func makeProj(
        yaw: Double,
        tilt: Double,
        cx: Double,
        cy: Double,
        scale: Double
    ) -> (Double, Double, Double) -> (Double, Double, Double) {
        let st = sin(tilt)
        let ct = cos(tilt)
        let sy = sin(yaw)
        let cyw = cos(yaw)
        return { x, y, z in
            let x1 = x * cyw + z * sy
            let z1 = -x * sy + z * cyw
            let y1 = y * ct - z1 * st
            let z2 = y * st + z1 * ct
            return (cx + x1 * scale, cy - y1 * scale, z2)
        }
    }

    /// Dot radii were tuned for a 300pt frame; sub-linear scaling keeps
    /// small spinners legible. Port of `radiusScale`.
    private static func radiusScale(size: Double, pow exponent: Double) -> Double {
        Foundation.pow(size / 300, exponent)
    }

    /// Painter: z-sort far→near, tinted matte dots. Port of `paint`.
    private static func paint(
        context: GraphicsContext,
        dots: [Dot],
        color: Color,
        rMin: Double = 0.3
    ) {
        for dot in dots.sorted(by: { $0.z < $1.z }) {
            guard dot.opacity >= 0.02 else { continue }
            let r = max(rMin, dot.r)
            let rect = CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(color.opacity(min(1, dot.opacity)))
            )
        }
    }

    /// Stroke pass for edge-based modes; runs before `paint` so nodes sit
    /// on top. Port of `paintLines`.
    private static func paintLines(context: GraphicsContext, lines: [Line], color: Color) {
        for line in lines {
            guard line.opacity >= 0.02 else { continue }
            var path = Path()
            path.move(to: CGPoint(x: line.x1, y: line.y1))
            path.addLine(to: CGPoint(x: line.x2, y: line.y2))
            context.stroke(
                path,
                with: .color(color.opacity(min(1, line.opacity))),
                lineWidth: line.width
            )
        }
    }

    private static func draw(
        context: GraphicsContext,
        size: Double,
        state: ThinkingOrbState,
        time: Double,
        color: Color
    ) {
        switch state {
        case .working:
            drawOrbits(context: context, size: size, time: time, color: color)
        case .searching:
            drawGlobe(context: context, size: size, time: time, color: color)
        case .connecting:
            drawWeb(context: context, size: size, time: time, color: color)
        }
    }

    // MARK: - Working: tilted orbits (port of engine/orbits.ts, size-20 preset)

    private static func drawOrbits(
        context: GraphicsContext,
        size: Double,
        time: Double,
        color: Color
    ) {
        // Size-20 preset: speed 3.9, count ×0.238, radius ×2.4.
        let t = time * 3.9
        let orbitN = 3        // round(12 × 0.238)
        let ghostN = 10       // round(40 × 0.238)
        let particles = 3     // flat option, not count-scaled
        let ghostR = 0.9 * 2.4
        let ghostA = 0.5
        let partR = 1.2 * 2.4
        let partRDepth = 1.6 * 2.4

        let cx = size / 2
        let cy = size / 2
        let bigR = (size / 2) * 0.82
        let pt = makeProj(yaw: t * 0.12, tilt: 0.3, cx: cx, cy: cy, scale: 1)
        let rs = radiusScale(size: size, pow: 0.6)

        var dots: [Dot] = []
        dots.reserveCapacity(orbitN * (ghostN + particles))

        for orb in 0..<orbitN {
            let h1 = hashD(Double(orb), 1.7)
            let h2 = hashD(Double(orb), 5.2)
            let h3 = hashD(Double(orb), 8.9)
            let ro = bigR * (0.45 + 0.52 * h1)
            let th = h1 * 2 * .pi
            let phi = acos(2 * h2 - 1)
            // Orbit plane basis (u, v ⟂ normal n).
            let nx = sin(phi) * cos(th)
            let ny = cos(phi)
            let nz = sin(phi) * sin(th)
            var ux = -ny
            var uy = nx
            let uz = 0.0
            let ul = max(1e-6, (ux * ux + uy * uy).squareRoot())
            ux /= ul
            uy /= ul
            let vx = ny * uz - nz * uy
            let vy = nz * ux - nx * uz
            let vz = nx * uy - ny * ux
            let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)

            // Ghost path.
            for k in 0..<ghostN {
                let a = (Double(k) / Double(ghostN)) * 2 * .pi
                let (px, py, z) = pt(
                    (ux * cos(a) + vx * sin(a)) * ro,
                    (uy * cos(a) + vy * sin(a)) * ro,
                    (uz * cos(a) + vz * sin(a)) * ro
                )
                let depth = (z / ro + 1) / 2
                dots.append(Dot(
                    x: px,
                    y: py,
                    z: z,
                    r: ghostR * rs,
                    opacity: ghostA * (0.4 + 0.6 * depth) * (1 - 0.72)
                ))
            }

            // The particles doing the work.
            for m in 0..<particles {
                let a = t * speed + (Double(m) / Double(particles)) * 2 * .pi + h2 * 6
                let (px, py, z) = pt(
                    (ux * cos(a) + vx * sin(a)) * ro,
                    (uy * cos(a) + vy * sin(a)) * ro,
                    (uz * cos(a) + vz * sin(a)) * ro
                )
                let depth = (z / ro + 1) / 2
                dots.append(Dot(
                    x: px,
                    y: py,
                    z: z,
                    r: (partR + partRDepth * depth) * rs,
                    opacity: 1 - (0.3 - 0.22 * depth)
                ))
            }
        }

        paint(context: context, dots: dots, color: color)
    }

    // MARK: - Searching: scan-meridian globe (port of engine/lattice.ts drawGlobe, size-20 preset)

    private static func drawGlobe(
        context: GraphicsContext,
        size: Double,
        time: Double,
        color: Color
    ) {
        // Size-20 preset: speed 2.665, count ×0.105 (√-split across the
        // lat/lon pair), radius ×1.75, scanMul 4.335, dimBase 0.45.
        let t = time * 2.665
        let latRings = 6      // round(17 × √0.105)
        let lonDensity = 14.0 // round(44 × √0.105)
        let rBase = 0.6 * 1.75
        let rDepth = 1.7 * 1.75
        let rBoost = 1.0 * 1.75
        let inkFar = 0.62
        let inkSpan = 0.54
        let scanMul = 4.335
        let dimBase = 0.45

        let spin = 0.5
        let cx = size / 2
        let cy = size / 2
        let radius = (size / 2) * 0.82
        let tilt = 0.4 + 0.06 * sin(t * 0.35)
        let pt = makeProj(yaw: t * spin, tilt: tilt, cx: cx, cy: cy, scale: radius)
        // The scan sweeps relative to the spin; scanMul scales that rate.
        let scan = t * (spin + (1.7 - spin) * scanMul)
        let rs = radiusScale(size: size, pow: 0.6)

        var dots: [Dot] = []
        dots.reserveCapacity((latRings + 1) * Int(lonDensity))

        for li in 0...latRings {
            let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * .pi
            let cosLat = cos(lat)
            let sinLat = sin(lat)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lj in 0..<lonCount {
                let lon = (Double(lj) / Double(lonCount)) * 2 * .pi
                let (px, py, z) = pt(cosLat * cos(lon), sinLat, cosLat * sin(lon))
                let depth = (z + 1) / 2
                // The scan: a moving meridian read as a size ripple.
                let d = angleDelta(lon + t * spin, scan)
                let boost = exp(-(d * d) / 0.18) * max(0, z)
                let white = inkFar - inkSpan * depth
                let alpha = dimBase + (1 - dimBase) * min(1, boost)
                dots.append(Dot(
                    x: px,
                    y: py,
                    z: z,
                    r: (rBase + rDepth * depth + rBoost * boost) * rs,
                    opacity: alpha * (1 - white)
                ))
            }
        }

        paint(context: context, dots: dots, color: color)
    }

    // MARK: - Connecting: constellation web (port of engine/web.ts, size-20 preset)

    private static func drawWeb(
        context: GraphicsContext,
        size: Double,
        time: Double,
        color: Color
    ) {
        // Size-20 preset: speed 6.63, count ×0.25, radius ×1.52.
        let t = time * 6.63
        let nodeN = 8         // round(30 × 0.25)
        let signals = 1       // round(5 × 0.25)
        let thr = 0.72
        let nodeR = 1.4 * 1.52
        let nodeRDepth = 1.8 * 1.52
        let lineW = 0.8

        let cx = size / 2
        let cy = size / 2
        let bigR = (size / 2) * 0.8
        // The projector carries the radius as its scale, so node vectors stay
        // unit-length and distances below are in unit-sphere space.
        let pt = makeProj(yaw: t * 0.12, tilt: 0.32, cx: cx, cy: cy, scale: bigR)
        let rs = radiusScale(size: size, pow: 0.6)

        // Nodes: fib lattice + slow noise wander, renormalized to the surface.
        var nodes: [(Double, Double, Double)] = []
        nodes.reserveCapacity(nodeN)
        for i in 0..<nodeN {
            let d = fibDir(i, nodeN)
            let x = d.0 + 0.3 * (vnoise(Double(i) * 0.31 + 9, t * 0.24) - 0.5) * 2
            let y = d.1 + 0.3 * (vnoise(Double(i) * 0.53 + 27, t * 0.21) - 0.5) * 2
            let z = d.2 + 0.3 * (vnoise(Double(i) * 0.77 + 55, t * 0.27) - 0.5) * 2
            let l = (x * x + y * y + z * z).squareRoot()
            nodes.append((x / l, y / l, z / l))
        }

        var lines: [Line] = []
        var dots: [Dot] = []
        dots.reserveCapacity(nodeN + signals)

        // Edges between close neighbours, alpha by proximity + depth.
        for i in 0..<nodeN {
            for j in (i + 1)..<nodeN {
                let dx = nodes[i].0 - nodes[j].0
                let dy = nodes[i].1 - nodes[j].1
                let dz = nodes[i].2 - nodes[j].2
                let dist = (dx * dx + dy * dy + dz * dz).squareRoot()
                guard dist < thr else { continue }
                let (x1, y1, z1) = pt(nodes[i].0, nodes[i].1, nodes[i].2)
                let (x2, y2, z2) = pt(nodes[j].0, nodes[j].1, nodes[j].2)
                let depth = ((z1 + z2) / 2 + 1) / 2
                lines.append(Line(
                    x1: x1,
                    y1: y1,
                    x2: x2,
                    y2: y2,
                    opacity: (1 - dist / thr) * (0.3 + 0.55 * depth) * (1 - 0.42),
                    width: max(0.6, lineW * rs)
                ))
            }
        }

        for i in 0..<nodeN {
            let (px, py, z) = pt(nodes[i].0, nodes[i].1, nodes[i].2)
            let depth = (z + 1) / 2
            let pulse = 1 + 0.25 * sin(t * 1.4 + Double(i) * 2.7)
            dots.append(Dot(
                x: px,
                y: py,
                z: z,
                r: (nodeR + nodeRDepth * depth) * pulse * rs,
                opacity: 1 - (0.55 - 0.45 * depth)
            ))
        }

        // Signals: bright packets running between paired nodes.
        for s in 0..<signals {
            let phase = t * 0.55 + Double(s) * 7.31
            let seg = phase.rounded(.down)
            let a = Int(hashD(seg, Double(s) * 3.1 + 1.7) * Double(nodeN))
            let b = Int(hashD(seg, Double(s) * 5.7 + 4.2) * Double(nodeN))
            guard a != b, a < nodeN, b < nodeN else { continue }
            let f = frac(phase)
            let x = lerp(nodes[a].0, nodes[b].0, f)
            let y = lerp(nodes[a].1, nodes[b].1, f)
            let z = lerp(nodes[a].2, nodes[b].2, f)
            let l = max(1e-6, (x * x + y * y + z * z).squareRoot())
            let (px, py, zr) = pt(x / l, y / l, z / l)
            let depth = (zr + 1) / 2
            dots.append(Dot(
                x: px,
                y: py,
                z: zr,
                r: (nodeR * 1.5 + nodeRDepth * depth) * rs,
                opacity: (0.5 + 0.5 * depth) * (1 - 0.05)
            ))
        }

        paintLines(context: context, lines: lines, color: color)
        paint(context: context, dots: dots, color: color)
    }
}

#Preview("Thinking orb states") {
    HStack(spacing: 24) {
        VStack(spacing: 8) {
            ThinkingOrbView(state: .working, size: 22)
            Text("working").font(.caption2)
        }
        VStack(spacing: 8) {
            ThinkingOrbView(state: .searching, size: 22)
            Text("searching").font(.caption2)
        }
        VStack(spacing: 8) {
            ThinkingOrbView(state: .connecting, size: 22)
            Text("connecting").font(.caption2)
        }
    }
    .padding()
}
