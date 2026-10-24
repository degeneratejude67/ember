import SwiftUI

/// Opened from the streak on Home: the flame, this week, freezes, the next milestone and
/// the rules in four lines.
struct StreakSheet: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let today = Today(store.data)
        let streak = today.streak
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    EmberMascot(mood: streak.todayDone ? .cheer : .calm, tier: today.tier, animated: !AppEnv.still)
                        .frame(height: 160)
                    VStack(spacing: 0) {
                        Text("\(streak.current)")
                            .font(.rounded(84, .heavy))
                            .monospacedDigit()
                            .foregroundStyle(streak.todayDone
                                             ? AnyShapeStyle(LinearGradient(colors: today.tier.outer.reversed(), startPoint: .top, endPoint: .bottom))
                                             : AnyShapeStyle(Theme.dim))
                        Text("day streak")
                            .font(.rounded(22, .heavy))
                            .foregroundStyle(Theme.text)
                    }
                    Text(statusLine(streak))
                        .font(.rounded(17, .semibold))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                    WeekStrip(week: today.week, days: today.days)
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    HStack(spacing: 12) {
                        fact("Best", "\(max(streak.best, streak.current)) days")
                        fact("Freezes", String(repeating: "❄︎", count: streak.freezes) + String(repeating: "·", count: Rules.maxFreezes - streak.freezes))
                        fact("Next milestone", "\(today.nextMilestone) days")
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How the streak works").font(.rounded(17, .bold)).foregroundStyle(Theme.text)
                            rule("flame.fill", "One finished block of \(Int(Rules.qualifyingMinutes)) minutes or more keeps it alive. The daily goal is separate.")
                            rule("snowflake", "Every \(Rules.freezeEvery) days earns a freeze (you can hold \(Rules.maxFreezes)). A freeze saves a missed day by itself.")
                            rule("arrow.uturn.backward", "Missed a day with no freeze? \(Rules.earnBackBlocks) blocks the next day earn it back.")
                            rule("moon.stars.fill", "The study day starts at \(store.data.prefs.dayStartHour == 0 ? "midnight" : "\(store.data.prefs.dayStartHour) am"), so late-night study counts for the evening before.")
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func statusLine(_ streak: StreakState) -> String {
        if streak.todayDone { return "Today's block is done. See you tomorrow." }
        if let earnBack = streak.earnBack {
            return "Yesterday was missed. \(earnBack.left) more block\(earnBack.left == 1 ? "" : "s") today bring\(earnBack.left == 1 ? "s" : "") back your \(earnBack.restores)-day streak."
        }
        if streak.current == 0 { return streak.best > 0 ? "Fresh start. One block today begins a new streak." : "One block today starts your streak." }
        return "One block today keeps it going."
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.rounded(11, .heavy))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.rounded(18, .heavy))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.ember).frame(width: 20)
            Text(text)
                .font(.rounded(15, .regular))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
