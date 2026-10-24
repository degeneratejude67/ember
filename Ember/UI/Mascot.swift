import SwiftUI

/// Ember's moods. Home picks one from the time of day and whether today's block is done.
enum Mood: String, CaseIterable, Identifiable {
    case calm, focused, cheer, sleepy, sad, shocked, worried

    var id: String { rawValue }
}

/// The flame's colours. A lit flame deepens as the streak grows; ash means today's block
/// is not done yet.
enum FlameTier: Int, CaseIterable, Identifiable {
    case ash, spark, glow, blaze, hot, blue, plasma

    var id: Int { rawValue }

    static func forStreak(_ days: Int, lit: Bool) -> FlameTier {
        guard lit, days > 0 else { return .ash }
        switch days {
        case ..<3: return .spark
        case ..<7: return .glow
        case ..<14: return .blaze
        case ..<30: return .hot
        case ..<100: return .blue
        default: return .plasma
        }
    }

    /// Streak length at which this tier starts.
    var startsAt: Int { [0, 1, 3, 7, 14, 30, 100][rawValue] }

    var outer: [Color] {
        switch self {
        case .ash: return [rgb(0x6B6F7A), rgb(0x8A8F99)]
        case .spark: return [rgb(0xFF8A1F), rgb(0xFFB347)]
        case .glow: return [rgb(0xFF6018), rgb(0xFFA430)]
        case .blaze: return [rgb(0xFF4D1A), rgb(0xFF8A2A)]
        case .hot: return [rgb(0xE8341C), rgb(0xFF6A2A)]
        case .blue: return [rgb(0x2F7BFF), rgb(0x5CC8FF)]
        case .plasma: return [rgb(0x8B3DFF), rgb(0xD46BFF)]
        }
    }

    var core: [Color] {
        switch self {
        case .ash: return [rgb(0xA9AEB8), rgb(0xC9CDD4)]
        case .spark: return [rgb(0xFFE08A), rgb(0xFFF6D5)]
        case .glow: return [rgb(0xFFD652), rgb(0xFFF3BE)]
        case .blaze: return [rgb(0xFFC93C), rgb(0xFFEBA8)]
        case .hot: return [rgb(0xFFB03A), rgb(0xFFE29A)]
        case .blue: return [rgb(0xBFE9FF), rgb(0xF2FBFF)]
        case .plasma: return [rgb(0xF4D9FF), rgb(0xFFFFFF)]
        }
    }

    var glow: Color { outer[1] }
}

private func rgb(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

/// The flame outline: the same Bezier segments as tools/make_icon.py, with the tips moved a
/// little by `t` (seconds) so it flickers.
struct FlameShape: Shape {
    var t: Double = 0
    var flicker: Double = 1

    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        let a = flicker
        let tipX = 0.56 + 0.025 * a * sin(t * 2.3)
        let tipY = 0.00 + 0.015 * a * sin(t * 3.1 + 0.7)
        let tongueX = 0.22 + 0.03 * a * sin(t * 2.9 + 1.3)
        let tongueY = 0.24 + 0.03 * a * sin(t * 3.7 + 2.1)
        let sway = 0.012 * a * sin(t * 1.7)
        var path = Path()
        path.move(to: p(0.50, 1.00))
        path.addCurve(to: p(0.09 - sway, 0.66), control1: p(0.25, 1.00), control2: p(0.09 - sway, 0.86))
        path.addCurve(to: p(tongueX, tongueY), control1: p(0.09 - sway, 0.48), control2: p(0.16, 0.36))
        path.addCurve(to: p(0.36, 0.42), control1: p(tongueX + 0.05, tongueY + 0.08), control2: p(0.31, 0.40))
        path.addCurve(to: p(tipX, tipY), control1: p(0.40, 0.22), control2: p(tipX - 0.06, tipY + 0.10))
        path.addCurve(to: p(0.91 + sway, 0.70), control1: p(tipX + 0.14, tipY + 0.22), control2: p(0.93 + sway, 0.42))
        path.addCurve(to: p(0.50, 1.00), control1: p(0.92 + sway, 0.90), control2: p(0.75, 1.00))
        path.closeSubpath()
        return path
    }
}

/// The bright inner flame that carries the face.
struct FlameCoreShape: Shape {
    var t: Double = 0
    var flicker: Double = 1

    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        let tipX = 0.51 + 0.02 * flicker * sin(t * 2.6 + 0.4)
        let tipY = 0.40 + 0.02 * flicker * sin(t * 3.3)
        var path = Path()
        path.move(to: p(0.50, 0.98))
        path.addCurve(to: p(0.24, 0.76), control1: p(0.33, 0.98), control2: p(0.24, 0.88))
        path.addCurve(to: p(tipX, tipY), control1: p(0.24, 0.62), control2: p(tipX - 0.15, tipY + 0.12))
        path.addCurve(to: p(0.76, 0.76), control1: p(tipX + 0.13, tipY + 0.12), control2: p(0.76, 0.62))
        path.addCurve(to: p(0.50, 0.98), control1: p(0.76, 0.88), control2: p(0.67, 0.98))
        path.closeSubpath()
        return path
    }
}

/// Ember, the flame mascot. The flicker runs at 20 fps and stops when `animated` is false
/// (dimmed screen, Reduce Motion, screenshots).
struct EmberMascot: View {
    var mood: Mood = .calm
    var tier: FlameTier = .glow
    var animated = true
    var glow = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated)) { context in
            let t = animated ? context.date.timeIntervalSinceReferenceDate : 0
            let flicker = animated ? 1.0 : 0.0
            ZStack {
                if glow {
                    Ellipse()
                        .fill(tier.glow.opacity(tier == .ash ? 0.12 : 0.35))
                        .scaleEffect(x: 1.25, y: 0.75)
                        .offset(y: 30)
                        .blur(radius: 40)
                }
                FlameShape(t: t, flicker: flicker)
                    .fill(LinearGradient(colors: tier.outer, startPoint: .top, endPoint: .bottom))
                FlameCoreShape(t: t, flicker: flicker)
                    .fill(LinearGradient(colors: tier.core, startPoint: .top, endPoint: .bottom))
                MascotFace(mood: mood, t: t)
            }
        }
        .aspectRatio(0.8, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Ember, \(mood.rawValue)")
    }
}

/// Eyes and mouth, drawn in the flame's unit box.
struct MascotFace: View {
    var mood: Mood
    var t: Double

    private static let ink = Color(red: 0.23, green: 0.10, blue: 0.03)

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            let ink = GraphicsContext.Shading.color(Self.ink)
            let line = StrokeStyle(lineWidth: max(1.5, 0.022 * w), lineCap: .round, lineJoin: .round)
            let eyeW = 0.075 * w, eyeH = 0.11 * h
            // t is 0 when the flame is still (screenshots): eyes open then
            let blinking = t > 0 && (t + 1).truncatingRemainder(dividingBy: 3.7) < 0.14
            let eyes = [0.40, 0.60]

            func roundEyes(scale: Double = 1, squint: Double = 1) {
                for x in eyes {
                    let c = p(x, 0.72)
                    let ew = eyeW * scale
                    let eh = eyeH * scale * (blinking ? 0.12 : squint)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - ew / 2, y: c.y - eh / 2, width: ew, height: eh)), with: ink)
                    if !blinking && squint > 0.5 {
                        let r = ew * 0.22
                        let hx = c.x + ew * 0.14, hy = c.y - eh * 0.2
                        context.fill(Path(ellipseIn: CGRect(x: hx - r, y: hy - r, width: 2 * r, height: 2 * r)), with: .color(.white))
                    }
                }
            }

            func brows(inner: Double, outer: Double) {
                for (i, x) in eyes.enumerated() {
                    let dir = i == 0 ? -1.0 : 1.0
                    var path = Path()
                    path.move(to: p(x + dir * 0.045, 0.635 + outer))
                    path.addLine(to: p(x - dir * 0.01, 0.635 + inner))
                    context.stroke(path, with: ink, style: line)
                }
            }

            func arc(_ cx: Double, _ cy: Double, _ width: Double, _ depth: Double) {
                var path = Path()
                path.move(to: p(cx - width / 2, cy))
                path.addQuadCurve(to: p(cx + width / 2, cy), control: p(cx, cy + depth))
                context.stroke(path, with: ink, style: line)
            }

            switch mood {
            case .calm:
                roundEyes()
                arc(0.50, 0.80, 0.12, 0.05)
            case .focused:
                roundEyes(squint: 0.7)
                arc(0.50, 0.815, 0.07, 0.0)
            case .cheer:
                for x in eyes { arc(x, 0.73, 0.075, -0.06) }
                var mouth = Path()
                mouth.move(to: p(0.425, 0.785))
                mouth.addQuadCurve(to: p(0.575, 0.785), control: p(0.50, 0.90))
                mouth.closeSubpath()
                context.fill(mouth, with: ink)
            case .sleepy:
                for x in eyes { arc(x, 0.725, 0.07, 0.02) }
                context.fill(Path(ellipseIn: CGRect(x: 0.485 * w, y: 0.80 * h, width: 0.03 * w, height: 0.035 * h)), with: ink)
            case .sad:
                roundEyes(squint: 0.9)
                brows(inner: -0.02, outer: 0.01)
                arc(0.50, 0.835, 0.10, -0.04)
            case .shocked:
                roundEyes(scale: 1.2)
                context.fill(Path(ellipseIn: CGRect(x: 0.465 * w, y: 0.79 * h, width: 0.07 * w, height: 0.075 * h)), with: ink)
            case .worried:
                roundEyes()
                brows(inner: -0.025, outer: 0.0)
                var mouth = Path()
                mouth.move(to: p(0.445, 0.825))
                mouth.addCurve(to: p(0.555, 0.825), control1: p(0.48, 0.80), control2: p(0.52, 0.85))
                context.stroke(mouth, with: ink, style: line)
            }
        }
    }
}
