import SwiftUI

/// Smoothed audio level for the orb, kept separate so 40+ updates a second don't redraw every view.
final class LevelMeter: ObservableObject {
    @Published private(set) var level: Float = 0

    func update(_ value: Float) {
        let next = value > level ? level * 0.4 + value * 0.6 : level * 0.82 + value * 0.18
        if abs(next - level) > 0.008 { level = next }
    }
}

/// The animated HUD orb: a glowing core with rotating arc segments, coloured by state.
struct OrbView: View {
    var phase: Assistant.Phase
    var level: Float

    private var tint: Color {
        switch phase {
        case .listening: return Color(red: 0.25, green: 0.85, blue: 1.0)
        case .thinking: return Color(red: 1.0, green: 0.72, blue: 0.25)
        case .speaking: return Color(red: 0.35, green: 0.95, blue: 0.95)
        case .error: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .paused: return Color.gray
        default: return Color(red: 0.3, green: 0.6, blue: 0.85)
        }
    }

    private var active: Bool {
        switch phase {
        case .listening, .thinking, .speaking: return true
        default: return false
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = self.phase, level = self.level, color = tint, isActive = active
            Canvas { ctx, size in
                OrbView.render(&ctx, size: size, t: t, phase: phase, level: level, color: color, active: isActive)
            }
        }
    }

    nonisolated static func render(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                                   phase: Assistant.Phase, level: Float, color: Color, active: Bool) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2

        var energy = CGFloat(level)
        if phase == .speaking { energy = max(energy, 0.3 + 0.25 * CGFloat(abs(sin(t * 7.5)))) }
        if phase == .thinking { energy = 0.25 + 0.1 * CGFloat(sin(t * 3)) }
        if !active { energy = 0.08 + 0.04 * CGFloat(sin(t * 1.2)) }

        func circle(_ r: CGFloat) -> CGRect {
            CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }

        // Outer glow
        let glowR = radius * (0.55 + 0.35 * energy)
        ctx.fill(Path(ellipseIn: circle(glowR)),
                 with: .radialGradient(Gradient(colors: [color.opacity(active ? 0.45 : 0.25), color.opacity(0)]),
                                       center: center, startRadius: 0, endRadius: glowR))

        // Core
        let coreR = radius * (0.2 + 0.14 * energy)
        ctx.fill(Path(ellipseIn: circle(coreR)),
                 with: .radialGradient(Gradient(colors: [.white.opacity(0.95), color.opacity(0.9), color.opacity(0.15)]),
                                       center: center, startRadius: 0, endRadius: coreR))

        // Rings
        let speedBase: Double = phase == .thinking ? 2.6 : (active ? 0.9 : 0.25)
        for i in 0..<3 {
            let ringR = radius * (0.5 + CGFloat(i) * 0.16)
            ctx.stroke(Path(ellipseIn: circle(ringR)),
                       with: .color(color.opacity(0.14)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 5]))

            let direction: Double = i % 2 == 0 ? 1 : -1.35
            let startRad = t * speedBase * direction + Double(i) * 2.1
            for segment in 0..<2 {
                let from = startRad + Double(segment) * .pi
                let sweep = (50 + Double(i) * 22 + Double(energy) * 40) * .pi / 180
                var arc = Path()
                arc.addArc(center: center, radius: ringR,
                           startAngle: .radians(from), endAngle: .radians(from + sweep), clockwise: false)
                ctx.stroke(arc,
                           with: .color(color.opacity(active ? 0.9 - Double(i) * 0.2 : 0.4)),
                           style: StrokeStyle(lineWidth: 2.6 - CGFloat(i) * 0.6, lineCap: .round))
            }
        }

        // Tick marks around the edge
        let ticks = 48
        let tickR = radius * 0.97
        for k in 0..<ticks {
            let a = Double(k) / Double(ticks) * 2 * .pi + t * 0.15
            let len: CGFloat = k % 4 == 0 ? 6 : 3
            var tick = Path()
            tick.move(to: CGPoint(x: center.x + cos(a) * tickR, y: center.y + sin(a) * tickR))
            tick.addLine(to: CGPoint(x: center.x + cos(a) * (tickR - len), y: center.y + sin(a) * (tickR - len)))
            ctx.stroke(tick, with: .color(color.opacity(0.35)), lineWidth: 1)
        }
    }
}
