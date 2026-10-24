import SwiftUI

enum Theme {
    static let bg = Color(red: 0.055, green: 0.059, blue: 0.075)
    static let card = Color(red: 0.10, green: 0.105, blue: 0.13)
    static let cardHigh = Color(red: 0.14, green: 0.145, blue: 0.175)
    static let line = Color.white.opacity(0.08)
    static let text = Color(white: 0.96)
    static let dim = Color(white: 0.60)

    static let ember = Color(red: 1.0, green: 0.478, blue: 0.102)
    static let emberDeep = Color(red: 0.78, green: 0.30, blue: 0.04)
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.24)
    static let teal = Color(red: 0.17, green: 0.77, blue: 0.66)
    static let tealDeep = Color(red: 0.08, green: 0.52, blue: 0.44)
    static let ice = Color(red: 0.35, green: 0.78, blue: 0.98)
    static let danger = Color(red: 1.0, green: 0.29, blue: 0.29)
    static let dangerDeep = Color(red: 0.72, green: 0.13, blue: 0.13)
    static let slate = Color(white: 0.22)
    static let slateDeep = Color(white: 0.13)
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Duolingo-style chunky button: a darker lip under the face, which presses down onto it
/// with a tap sound.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.ember
    var lip: Color = Theme.emberDeep
    var textColor: Color = .white
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return configuration.label
            .font(.rounded(18, .heavy))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(shape.fill(color))
            .background(shape.fill(lip).offset(y: pressed ? 0 : 5))
            .offset(y: pressed ? 5 : 0)
            .padding(.bottom, 5)
            .animation(.spring(response: 0.16, dampingFraction: 0.7), value: pressed)
            .onChange(of: pressed) { _, isPressed in
                if isPressed { Audio.shared.play(.tap) }
            }
    }
}

/// A rounded card on the dark background.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line))
    }
}
