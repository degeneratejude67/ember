import SwiftUI

/// The end of a completed block. Reveals run on one timeline with the sounds: the chord,
/// Ember cheering, minutes, XP counting up with rising ticks, then how clean the block was.
/// A tap anywhere jumps to the end.
struct CelebrationView: View {
    let record: SessionRecord
    @ObservedObject private var store = Store.shared
    @ObservedObject private var controller = SessionController.shared
    @State private var stage = 0
    @State private var shownMinutes = 0
    @State private var shownXP = 0
    @State private var intentAnswer: String?
    @State private var skipped = false

    var body: some View {
        let today = Today(store.data)
        let xp = xpForRecord(today)
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    EmberMascot(mood: .cheer, tier: today.tier, animated: !AppEnv.still)
                        .frame(height: 190)
                        .scaleEffect(stage >= 1 ? 1 : 0.5)
                        .opacity(stage >= 1 ? 1 : 0)
                    Text("Block complete!")
                        .font(.rounded(38, .heavy))
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 12) {
                        StatTile(title: "Focused", value: "\(shownMinutes) min", color: Theme.ember)
                            .opacity(stage >= 2 ? 1 : 0.25)
                        StatTile(title: "XP", value: "+\(shownXP)", color: Theme.gold)
                            .opacity(stage >= 3 ? 1 : 0.25)
                        StatTile(title: record.slips == 0 ? "Unbroken" : "Slips",
                                 value: record.slips == 0 ? "100%" : "\(record.slips)", color: Theme.teal)
                            .opacity(stage >= 4 ? 1 : 0.25)
                    }
                    .frame(maxWidth: 520)
                    if stage >= 4 {
                        streakLine(today)
                            .transition(.scale.combined(with: .opacity))
                    }
                    if stage >= 5 && !record.intent.isEmpty {
                        intentCheck
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if stage >= 5 {
                        Button("Continue") { controller.celebration = nil }
                            .buttonStyle(ChunkyButtonStyle(height: 60))
                            .frame(maxWidth: 420)
                            .accessibilityIdentifier("continue")
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { skipToEnd(xp) }
        .task { await play(xp) }
        .accessibilityIdentifier("celebration")
    }

    private func xpForRecord(_ today: Today) -> Int {
        let welcome = Rewards.welcomeBackIDs(store.data.sessions, status: today.streak.status, days: today.days)
        return Rewards.xp(record, welcomeBack: welcome.contains(record.id))
    }

    @ViewBuilder private func streakLine(_ today: Today) -> some View {
        let firstToday = store.data.sessions.filter { $0.day == record.day && $0.qualifies }.first?.id == record.id
        if record.qualifies && firstToday {
            HStack(spacing: 8) {
                FlameShape()
                    .fill(LinearGradient(colors: today.tier.outer, startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 28)
                Text("\(today.streak.current)-day streak")
                    .font(.rounded(22, .heavy))
                    .foregroundStyle(Theme.text)
            }
            .accessibilityIdentifier("celebration-streak")
        } else if today.goalReached {
            Label("Daily goal reached", systemImage: "checkmark.seal.fill")
                .font(.rounded(20, .bold))
                .foregroundStyle(Theme.gold)
        } else {
            Text("\(Int(max(0, Double(today.goal) - today.minutes))) minutes to today's goal")
                .font(.rounded(18, .semibold))
                .foregroundStyle(Theme.dim)
        }
    }

    private var intentCheck: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("You said: \u{201C}\(record.intent)\u{201D}")
                    .font(.rounded(16, .semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ForEach(["done", "partly", "notYet"], id: \.self) { key in
                        Button(key == "done" ? "Done" : key == "partly" ? "Partly" : "Not yet") {
                            intentAnswer = key
                            controller.setIntentResult(key, for: record.id)
                        }
                        .font(.rounded(15, .bold))
                        .foregroundStyle(intentAnswer == key ? Color.white : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(intentAnswer == key ? Theme.ember : Theme.cardHigh,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: 520)
    }

    // MARK: - Timeline

    private func play(_ xp: Int) async {
        if AppEnv.still {
            skipToEnd(xp)
            return
        }
        Audio.shared.play(.complete)
        await wait(0.45)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { stage = max(stage, 1) }
        await wait(0.45)
        withAnimation(.easeOut(duration: 0.2)) { stage = max(stage, 2) }
        let minutes = Int(record.minutes.rounded())
        for i in 1...6 where !skipped {
            withAnimation(.snappy) { shownMinutes = minutes * i / 6 }
            await wait(0.06)
        }
        await wait(0.25)
        withAnimation(.easeOut(duration: 0.2)) { stage = max(stage, 3) }
        for i in 0..<8 where !skipped {
            withAnimation(.snappy) { shownXP = xp * (i + 1) / 8 }
            Audio.shared.play(.tick(i))
            await wait(0.15)
        }
        await wait(0.2)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { stage = max(stage, 4) }
        await wait(0.5)
        withAnimation(.easeOut(duration: 0.3)) { stage = max(stage, 5) }
    }

    private func skipToEnd(_ xp: Int) {
        skipped = true
        shownMinutes = Int(record.minutes.rounded())
        shownXP = xp
        stage = 5
    }

    private func wait(_ seconds: Double) async {
        guard !skipped else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.rounded(12, .heavy))
                .kerning(0.5)
                .foregroundStyle(color)
            Text(value)
                .font(.rounded(26, .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.5), lineWidth: 2))
    }
}
