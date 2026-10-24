import SwiftUI

/// After a block ends early: no guilt trip, just what happened, what still counts, and one
/// tap to say what pulled him away.
struct UnfinishedView: View {
    let info: SessionController.Unfinished
    @ObservedObject private var controller = SessionController.shared

    struct Tag: Identifiable {
        let name: String
        let icon: String
        var id: String { name }
    }

    static let tags = [
        Tag(name: "Social media", icon: "bubble.left.and.bubble.right.fill"), Tag(name: "YouTube", icon: "play.rectangle.fill"),
        Tag(name: "Games", icon: "gamecontroller.fill"), Tag(name: "Messages", icon: "message.fill"),
        Tag(name: "Tired", icon: "moon.zzz.fill"), Tag(name: "Something else", icon: "ellipsis.circle.fill"),
    ]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    EmberMascot(mood: .sad, tier: .ash, animated: !AppEnv.still)
                        .frame(height: 170)
                    Text("Block unfinished")
                        .font(.rounded(34, .heavy))
                        .foregroundStyle(Theme.text)
                    Text(reasonLine)
                        .font(.rounded(18, .semibold))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                    Text(countLine)
                        .font(.rounded(18, .bold))
                        .foregroundStyle(Theme.ember)
                        .multilineTextAlignment(.center)
                    Text("What pulled you away?")
                        .font(.rounded(17, .bold))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 10)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(Self.tags) { tag in
                            Button {
                                controller.closeUnfinished(tag: tag.name)
                            } label: {
                                Label(tag.name, systemImage: tag.icon)
                                    .font(.rounded(15, .semibold))
                                    .foregroundStyle(Theme.text)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("tag-\(tag.name)")
                        }
                    }
                    Button("Skip") { controller.closeUnfinished(tag: nil) }
                        .font(.rounded(16, .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.top, 4)
                        .accessibilityIdentifier("unfinished-skip")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 36)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var reasonLine: String {
        switch info.record.reason {
        case .left:
            let away = Int(info.awaySeconds ?? 0)
            let text = away >= 60 ? "\(away / 60) min \(away % 60) s" : "\(away) s"
            return "You left Ember for \(text). The flame couldn't wait."
        case .gaveUp:
            return "You gave up on this one. That's allowed."
        default:
            return "This block didn't finish."
        }
    }

    private var countLine: String {
        let minutes = Int(info.record.minutes)
        if minutes == 0 { return "Your streak is untouched. Start again when you're ready." }
        return minutes == 1 ? "1 minute still counts toward today." : "\(minutes) minutes still count toward today."
    }
}
