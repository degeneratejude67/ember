import SwiftUI

enum SubjectPalette {
    static let colors: [Color] = [
        Color(red: 0.36, green: 0.78, blue: 0.98), Color(red: 0.70, green: 0.53, blue: 1.0),
        Color(red: 1.0, green: 0.45, blue: 0.62), Color(red: 0.45, green: 0.86, blue: 0.48),
        Color(red: 1.0, green: 0.78, blue: 0.30), Color(red: 0.30, green: 0.85, blue: 0.80),
        Color(red: 1.0, green: 0.55, blue: 0.35), Color(red: 0.60, green: 0.68, blue: 1.0),
    ]

    static func color(_ index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }
}

/// The streak count with a small flame in the streak's colours.
struct StreakPill: View {
    let days: Int
    let tier: FlameTier

    var body: some View {
        HStack(spacing: 6) {
            FlameShape()
                .fill(LinearGradient(colors: tier.outer, startPoint: .top, endPoint: .bottom))
                .frame(width: 20, height: 25)
            Text("\(days)")
                .font(.rounded(22, .heavy))
                .monospacedDigit()
                .foregroundStyle(tier == .ash ? Theme.dim : Theme.text)
                .contentTransition(.numericText(value: Double(days)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(days) day streak")
        .accessibilityIdentifier("streak-pill")
    }
}

/// Today's minutes against the daily goal.
struct GoalRing: View {
    let minutes: Double
    let goal: Int
    var size: CGFloat = 44

    var body: some View {
        let progress = goal > 0 ? min(1, minutes / Double(goal)) : 0
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.cardHigh, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(progress >= 1 ? Theme.gold : Theme.ember, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if progress >= 1 {
                    Image(systemName: "checkmark").font(.system(size: size * 0.32, weight: .heavy)).foregroundStyle(Theme.gold)
                }
            }
            .frame(width: size, height: size)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(minutes)) / \(goal) min")
                    .font(.rounded(15, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text("today")
                    .font(.rounded(12, .semibold))
                    .foregroundStyle(Theme.dim)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(minutes)) of \(goal) minutes today")
        .accessibilityIdentifier("goal-ring")
    }
}

/// A rounded button showing a choice, with a caption above it.
struct ChoiceChip: View {
    let caption: String
    let title: String
    var dot: Color?
    var identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(caption)
                    .font(.rounded(12, .semibold))
                    .foregroundStyle(Theme.dim)
                HStack(spacing: 8) {
                    if let dot { Circle().fill(dot).frame(width: 10, height: 10) }
                    Text(title)
                        .font(.rounded(17, .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// A pie slice from 12 o'clock, clockwise, covering `fraction` of the circle.
struct PieSlice: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        guard fraction > 0 else { return path }
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(1, fraction)), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The focus timer: a Time Timer-style shrinking disc, a ring, or digits only.
struct TimerFace: View {
    let style: TimerStyle
    /// Remaining (countdown) or elapsed-within-the-hour (count-up), 0...1.
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                switch style {
                case .disc:
                    Circle().fill(Theme.card)
                    ticks(side)
                    PieSlice(fraction: fraction)
                        .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .padding(side * 0.09)
                    Circle().fill(Theme.cardHigh).frame(width: side * 0.07, height: side * 0.07)
                case .ring:
                    Circle().stroke(Theme.card, lineWidth: side * 0.06)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(color, style: StrokeStyle(lineWidth: side * 0.06, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                case .digits:
                    EmptyView()
                }
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func ticks(_ side: CGFloat) -> some View {
        ForEach(0..<60, id: \.self) { i in
            Capsule()
                .fill(i % 5 == 0 ? Theme.dim.opacity(0.8) : Theme.dim.opacity(0.3))
                .frame(width: i % 5 == 0 ? 3 : 1.5, height: i % 5 == 0 ? side * 0.045 : side * 0.025)
                .offset(y: -side / 2 + side * 0.04)
                .rotationEffect(.degrees(Double(i) * 6))
        }
    }
}

/// A button that only fires after being held for `duration` seconds, filling as it is held.
struct HoldButton: View {
    let title: String
    var duration: Double = 3
    var color: Color = Theme.danger
    let action: () -> Void

    @State private var holding = false
    @State private var progress = 0.0

    var body: some View {
        Text(holding ? "Keep holding…" : title)
            .font(.rounded(15, .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                GeometryReader { geo in
                    Capsule().fill(color.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(color.opacity(0.35)).frame(width: geo.size.width * progress)
                        }
                        .clipShape(Capsule())
                }
            )
            .overlay(Capsule().stroke(color.opacity(0.5)))
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
                holding = false
                progress = 0
                action()
            } onPressingChanged: { pressing in
                holding = pressing
                if pressing {
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            }
            .accessibilityAddTraits(.isButton)
    }
}
