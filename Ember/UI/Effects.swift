import SwiftUI

/// A one-shot confetti burst. Seventy pieces are seeded once and their positions are worked
/// out from time alone (p + vt + gt²/2), so nothing is stored per frame; the view removes
/// its timeline after 2.6 s.
struct ConfettiBurst: View {
    /// Where the burst starts, as a fraction of the view.
    var origin = UnitPoint(x: 0.5, y: 0.35)
    var count = 70
    var seed: UInt64 = 7

    @State private var start = Date()
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [Theme.ember, Theme.gold, Theme.teal, Theme.ice,
                                          Color(red: 1, green: 0.45, blue: 0.62), .white]
    private static let lifetime = 2.6

    private struct Piece {
        let angle: Double, speed: Double, spin: Double, size: CGSize, color: Color, round: Bool
    }

    private var pieces: [Piece] {
        var rng = SeededRandom(seed: seed)
        return (0..<count).map { _ in
            Piece(angle: -Double.pi / 2 + rng.next(in: -1.15...1.15),
                  speed: rng.next(in: 380...900),
                  spin: rng.next(in: -9...9),
                  size: CGSize(width: rng.next(in: 6...11), height: rng.next(in: 9...16)),
                  color: Self.colors[Int(rng.next(in: 0...5.99))],
                  round: rng.next(in: 0...1) < 0.3)
        }
    }

    var body: some View {
        Group {
            if !done && !reduceMotion && !AppEnv.still {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince(start)
                    Canvas { ctx, size in
                        guard t < Self.lifetime else { return }
                        let o = CGPoint(x: origin.x * size.width, y: origin.y * size.height)
                        let fade = t > Self.lifetime - 0.6 ? (Self.lifetime - t) / 0.6 : 1
                        for piece in pieces {
                            let drag = 1 - min(0.55, t * 0.25)
                            let x = o.x + cos(piece.angle) * piece.speed * t * drag
                            let y = o.y + sin(piece.angle) * piece.speed * t * drag + 0.5 * 1100 * t * t
                            var layer = ctx
                            layer.opacity = fade
                            layer.translateBy(x: x, y: y)
                            layer.rotate(by: .radians(piece.spin * t))
                            let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                                              width: piece.size.width, height: piece.size.height)
                            let path = piece.round ? Path(ellipseIn: rect.insetBy(dx: 0, dy: (rect.height - rect.width) / 2))
                                                   : Path(roundedRect: rect, cornerRadius: 2)
                            layer.fill(path, with: .color(piece.color))
                        }
                    }
                }
                .task {
                    try? await Task.sleep(nanoseconds: UInt64(Self.lifetime * 1_000_000_000))
                    done = true
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A small deterministic random generator (SplitMix64), so a burst looks the same every time.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextUInt() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(nextUInt() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}

/// Monday to Sunday, Duolingo style: flames on studied days, ice on frozen ones, an empty
/// ring for missed days, and today's circle filling in when `fillToday` turns true.
struct WeekStrip: View {
    let week: [CompletionSummary.WeekDay]
    var fillToday = true
    var days = Days(dayStartHour: 4)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(week, id: \.key) { day in
                VStack(spacing: 6) {
                    Text(letter(day.key))
                        .font(.rounded(13, .bold))
                        .foregroundStyle(day.isToday ? Theme.ember : Theme.dim)
                    circle(day)
                        .frame(width: 34, height: 34)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week")
        .accessibilityIdentifier("week-strip")
    }

    @ViewBuilder private func circle(_ day: CompletionSummary.WeekDay) -> some View {
        let status = day.isToday && !fillToday ? nil : day.status
        ZStack {
            switch status {
            case .credited?, .repaired?:
                Circle().fill(LinearGradient(colors: [Theme.ember, Theme.gold], startPoint: .bottom, endPoint: .top))
                FlameShape().fill(.white.opacity(0.95)).frame(width: 13, height: 16)
            case .frozen?:
                Circle().fill(Theme.ice.opacity(0.85))
                Image(systemName: "snowflake").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            case .missed?:
                Circle().stroke(Theme.dim.opacity(0.45), lineWidth: 2.5)
            default:
                Circle().stroke(day.isToday ? Theme.ember.opacity(0.8) : Theme.cardHigh, lineWidth: 2.5)
            }
        }
        .scaleEffect(day.isToday && fillToday && status != nil ? 1.12 : 1)
    }

    private func letter(_ key: DayKey) -> String {
        let weekday = days.calendar.component(.weekday, from: days.noon(key))
        return ["S", "M", "T", "W", "T", "F", "S"][weekday - 1]
    }
}
