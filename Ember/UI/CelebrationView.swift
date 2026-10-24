import SwiftUI

/// The end of a completed block: up to four screens, each with its reveals and sounds on one
/// timeline. The block screen comes first; then the streak (if this was today's first
/// block), the daily goal (if just reached) and a rank-up. A tap jumps a screen to its end.
struct CelebrationView: View {
    let summary: CompletionSummary
    @ObservedObject private var controller = SessionController.shared
    @State private var index = Int(AppEnv.value(after: "-uitest-step") ?? "") ?? 0

    var body: some View {
        let steps = summary.steps
        let step = steps[min(index, steps.count - 1)]
        ZStack {
            Theme.bg.ignoresSafeArea()
            Group {
                switch step {
                case .complete: CompleteStep(summary: summary, onContinue: next)
                case .streak: StreakStep(summary: summary, onContinue: next)
                case .goal: GoalStep(summary: summary, onContinue: next)
                case .rankUp: RankUpStep(summary: summary, onContinue: next)
                }
            }
            .id(index)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        }
    }

    private func next() {
        if index + 1 < summary.steps.count {
            withAnimation(.easeInOut(duration: 0.35)) { index += 1 }
        } else {
            controller.celebration = nil
        }
    }
}

/// Runs a step's reveals in order; `skip(to:)` jumps to the end state.
@MainActor
final class Beats: ObservableObject {
    @Published var stage = 0
    private(set) var skipped = false

    func wait(_ seconds: Double) async {
        guard !skipped else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func reach(_ stage: Int, _ animation: Animation = .easeOut(duration: 0.25)) {
        guard !skipped else { return }
        withAnimation(animation) { self.stage = max(self.stage, stage) }
    }

    func skip(to final: Int) {
        skipped = true
        stage = final
    }
}

// MARK: - Block complete

struct CompleteStep: View {
    let summary: CompletionSummary
    let onContinue: () -> Void
    @ObservedObject private var controller = SessionController.shared
    @StateObject private var beats = Beats()
    @State private var shownMinutes = 0
    @State private var shownXP = 0
    @State private var intentAnswer: String?
    @State private var score = ""
    @State private var scoreSaved = false

    private var record: SessionRecord { summary.record }
    /// Guided Access was on for 90% of the block or more.
    private var lockedIn: Bool { record.minutes > 0 && record.lockedMinutes >= 0.9 * record.minutes }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 22) {
                    EmberMascot(mood: .cheer, tier: summary.tierAfter, animated: !AppEnv.still)
                        .frame(height: 190)
                        .scaleEffect(beats.stage >= 1 ? 1 : 0.5)
                        .opacity(beats.stage >= 1 ? 1 : 0)
                    Text(summary.firstEver ? "Your first block!" : "Block complete!")
                        .font(.rounded(38, .heavy))
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 12) {
                        StatTile(title: "Focused", value: "\(shownMinutes) min", color: Theme.ember)
                            .opacity(beats.stage >= 2 ? 1 : 0.25)
                        StatTile(title: "XP", value: "+\(shownXP)", color: Theme.gold)
                            .opacity(beats.stage >= 3 ? 1 : 0.25)
                        if lockedIn {
                            StatTile(title: "Locked in", value: "×1.5", color: Theme.gold)
                                .opacity(beats.stage >= 4 ? 1 : 0.25)
                        } else {
                            StatTile(title: record.slips == 0 ? "Unbroken" : "Slips",
                                     value: record.slips == 0 ? "100%" : "\(record.slips)", color: Theme.teal)
                                .opacity(beats.stage >= 4 ? 1 : 0.25)
                        }
                    }
                    .frame(maxWidth: 520)
                    if beats.stage >= 4 && !summary.extendedStreak {
                        progressLine
                            .transition(.scale.combined(with: .opacity))
                    }
                    if beats.stage >= 5 && !record.intent.isEmpty {
                        intentCheck
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if beats.stage >= 5 && record.presetID == Preset.exam.id {
                        scoreCard
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if beats.stage >= 5 {
                        Button("Continue", action: onContinue)
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
            ConfettiBurst(origin: UnitPoint(x: 0.5, y: 0.22))
        }
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .task { await play() }
    }

    @ViewBuilder private var progressLine: some View {
        if summary.minutesAfter >= Double(summary.goal) {
            Label("Daily goal reached", systemImage: "checkmark.seal.fill")
                .font(.rounded(20, .bold))
                .foregroundStyle(Theme.gold)
        } else {
            let left = Int((Double(summary.goal) - summary.minutesAfter).rounded(.up))
            Text(left <= Int(record.minutes) + 1 ? "One more block reaches today's goal." : "\(left) minutes to today's goal.")
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

    /// Mock exams: mark it with the past paper's answers, then note the score.
    private var scoreCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mark it, then note your score")
                    .font(.rounded(16, .semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 10) {
                    TextField("e.g. 142 / 210", text: $score)
                        .font(.rounded(17, .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.cardHigh, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("exam-score")
                    Button(scoreSaved ? "Saved" : "Save") {
                        controller.setExamScore(score, for: record.id)
                        scoreSaved = true
                    }
                    .font(.rounded(15, .bold))
                    .disabled(score.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(maxWidth: 520)
    }

    private func play() async {
        if AppEnv.still { return skip() }
        Audio.shared.play(.complete)
        await beats.wait(0.45)
        beats.reach(1, .spring(response: 0.45, dampingFraction: 0.55))
        await beats.wait(0.45)
        beats.reach(2)
        let minutes = Int(record.minutes.rounded())
        for i in 1...6 where !beats.skipped {
            withAnimation(.snappy) { shownMinutes = minutes * i / 6 }
            await beats.wait(0.06)
        }
        await beats.wait(0.25)
        beats.reach(3)
        for i in 0..<8 where !beats.skipped {
            withAnimation(.snappy) { shownXP = summary.xp * (i + 1) / 8 }
            Audio.shared.play(.tick(i))
            await beats.wait(0.15)
        }
        await beats.wait(0.2)
        beats.reach(4, .spring(response: 0.4, dampingFraction: 0.7))
        await beats.wait(0.5)
        beats.reach(5, .easeOut(duration: 0.3))
    }

    private func skip() {
        shownMinutes = Int(record.minutes.rounded())
        shownXP = summary.xp
        beats.skip(to: 5)
    }
}

// MARK: - Streak

struct StreakStep: View {
    let summary: CompletionSummary
    let onContinue: () -> Void
    @StateObject private var beats = Beats()
    @State private var shown: Int
    @State private var shareCard: Image?

    init(summary: CompletionSummary, onContinue: @escaping () -> Void) {
        self.summary = summary
        self.onContinue = onContinue
        _shown = State(initialValue: summary.streakBefore)
    }

    private var lit: Bool { beats.stage >= 1 }

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                Spacer(minLength: 20)
                EmberMascot(mood: .cheer, tier: lit ? summary.tierAfter : .ash, animated: !AppEnv.still)
                    .frame(height: 230)
                    .scaleEffect(lit ? 1 : 0.45)
                Text("\(shown)")
                    .font(.rounded(112, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: summary.tierAfter.outer.reversed(), startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText(value: Double(shown)))
                    .accessibilityIdentifier("streak-number")
                Text("day streak")
                    .font(.rounded(26, .heavy))
                    .foregroundStyle(Theme.text)
                    .padding(.top, -16)
                Text(caption)
                    .font(.rounded(18, .semibold))
                    .foregroundStyle(summary.milestone != nil ? Theme.gold : Theme.dim)
                    .multilineTextAlignment(.center)
                    .opacity(beats.stage >= 3 ? 1 : 0)
                WeekStrip(week: summary.week, fillToday: beats.stage >= 2)
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Spacer(minLength: 20)
                Button("Continue", action: onContinue)
                    .buttonStyle(ChunkyButtonStyle(height: 60))
                    .frame(maxWidth: 420)
                    .opacity(beats.stage >= 4 ? 1 : 0)
                    .disabled(beats.stage < 4)
                    .accessibilityIdentifier("continue")
                if let card = shareCard, beats.stage >= 4 {
                    ShareLink(item: card, preview: SharePreview("\(summary.streakAfter)-day streak", image: card)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.rounded(16, .semibold))
                            .foregroundStyle(Theme.dim)
                    }
                    .accessibilityIdentifier("share-streak")
                }
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            if summary.milestone != nil && beats.stage >= 3 {
                ConfettiBurst(origin: UnitPoint(x: 0.5, y: 0.3), seed: 11)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .task { await play() }
        .onAppear(perform: makeShareCard)
    }

    /// Milestone days get a square card to share, rendered once.
    private func makeShareCard() {
        guard summary.milestone != nil, shareCard == nil else { return }
        let renderer = ImageRenderer(content: StreakCard(days: summary.streakAfter, tier: summary.tierAfter))
        renderer.scale = 2
        shareCard = renderer.uiImage.map { Image(uiImage: $0) }
    }

    private var caption: String {
        if let milestone = summary.milestone {
            let hotter = summary.tierAfter != summary.tierBefore ? " Ember burns hotter now." : ""
            return "\(milestone)-day milestone!\(hotter)"
        }
        if summary.earnedBack { return "Streak earned back. Welcome back!" }
        if summary.freezeEarned { return "You earned a streak freeze. It saves a missed day by itself." }
        if summary.firstEver { return "Day one. Come back tomorrow to make it two." }
        return "Study tomorrow to keep it going."
    }

    private func play() async {
        if AppEnv.still { return skip() }
        Audio.shared.play(.streak)
        await beats.wait(0.3)
        beats.reach(1, .spring(response: 0.5, dampingFraction: 0.5))
        await beats.wait(0.35)
        withAnimation(.snappy(duration: 0.4)) { shown = summary.streakAfter }
        await beats.wait(0.35)
        beats.reach(2, .spring(response: 0.35, dampingFraction: 0.6))
        await beats.wait(0.3)
        beats.reach(3)
        if summary.milestone != nil { Audio.shared.play(.milestone) }
        await beats.wait(0.5)
        beats.reach(4)
    }

    private func skip() {
        shown = summary.streakAfter
        beats.skip(to: 4)
    }
}

// MARK: - Daily goal

struct GoalStep: View {
    let summary: CompletionSummary
    let onContinue: () -> Void
    @StateObject private var beats = Beats()
    @State private var progress: Double

    init(summary: CompletionSummary, onContinue: @escaping () -> Void) {
        self.summary = summary
        self.onContinue = onContinue
        _progress = State(initialValue: summary.goal > 0 ? min(1, summary.minutesBefore / Double(summary.goal)) : 0)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 22) {
                Spacer(minLength: 20)
                ZStack {
                    Circle().stroke(Theme.card, lineWidth: 26)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(LinearGradient(colors: [Theme.ember, Theme.gold], startPoint: .bottom, endPoint: .top),
                                style: StrokeStyle(lineWidth: 26, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 64, weight: .heavy))
                            .foregroundStyle(Theme.gold)
                            .scaleEffect(beats.stage >= 2 ? 1 : 0.2)
                            .opacity(beats.stage >= 2 ? 1 : 0)
                        Text("\(Int(summary.minutesAfter)) min")
                            .font(.rounded(26, .heavy))
                            .foregroundStyle(Theme.text)
                    }
                }
                .frame(width: 250, height: 250)
                Text("Daily goal reached!")
                    .font(.rounded(36, .heavy))
                    .foregroundStyle(Theme.text)
                Text("\(summary.goal) minutes done. Anything more today is a bonus.")
                    .font(.rounded(18, .semibold))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 20)
                Button("Continue", action: onContinue)
                    .buttonStyle(ChunkyButtonStyle(height: 60))
                    .frame(maxWidth: 420)
                    .opacity(beats.stage >= 3 ? 1 : 0)
                    .disabled(beats.stage < 3)
                    .accessibilityIdentifier("continue")
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            if beats.stage >= 2 { ConfettiBurst(origin: UnitPoint(x: 0.5, y: 0.3), seed: 23) }
        }
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .task { await play() }
    }

    private func play() async {
        if AppEnv.still { return skip() }
        await beats.wait(0.25)
        withAnimation(.easeInOut(duration: 0.9)) { progress = 1 }
        await beats.wait(0.9)
        Audio.shared.play(.milestone)
        beats.reach(2, .spring(response: 0.4, dampingFraction: 0.5))
        await beats.wait(0.6)
        beats.reach(3)
    }

    private func skip() {
        progress = 1
        beats.skip(to: 3)
    }
}

// MARK: - Rank up

struct RankUpStep: View {
    let summary: CompletionSummary
    let onContinue: () -> Void
    @StateObject private var beats = Beats()

    var body: some View {
        let next = Rewards.next(after: summary.rankAfter)
        ZStack {
            VStack(spacing: 20) {
                Spacer(minLength: 20)
                EmberMascot(mood: .cheer, tier: summary.tierAfter, animated: !AppEnv.still)
                    .frame(height: 200)
                Text("New rank")
                    .font(.rounded(20, .heavy))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                Text(summary.rankAfter.name)
                    .font(.rounded(64, .heavy))
                    .foregroundStyle(LinearGradient(colors: [Theme.gold, Theme.ember], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(beats.stage >= 1 ? 1 : 0.3)
                    .opacity(beats.stage >= 1 ? 1 : 0)
                Text("\(Int(summary.hoursAfter)) hours of focus so far.")
                    .font(.rounded(18, .semibold))
                    .foregroundStyle(Theme.text)
                if let next {
                    VStack(spacing: 8) {
                        ProgressView(value: beats.stage >= 2 ? Rewards.progress(hours: summary.hoursAfter) : 0)
                            .tint(Theme.gold)
                            .frame(maxWidth: 320)
                        Text("Next: \(next.name) at \(Int(next.hours)) hours")
                            .font(.rounded(15, .semibold))
                            .foregroundStyle(Theme.dim)
                    }
                }
                Spacer(minLength: 20)
                Button("Continue", action: onContinue)
                    .buttonStyle(ChunkyButtonStyle(height: 60))
                    .frame(maxWidth: 420)
                    .opacity(beats.stage >= 3 ? 1 : 0)
                    .disabled(beats.stage < 3)
                    .accessibilityIdentifier("continue")
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            if beats.stage >= 1 { ConfettiBurst(origin: UnitPoint(x: 0.5, y: 0.4), seed: 31) }
        }
        .contentShape(Rectangle())
        .onTapGesture { beats.skip(to: 3) }
        .task { await play() }
    }

    private func play() async {
        if AppEnv.still { return beats.skip(to: 3) }
        Audio.shared.play(.milestone)
        await beats.wait(0.3)
        beats.reach(1, .spring(response: 0.45, dampingFraction: 0.5))
        await beats.wait(0.5)
        beats.reach(2, .easeInOut(duration: 0.8))
        await beats.wait(0.8)
        beats.reach(3)
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

/// The square card shared on milestone days.
struct StreakCard: View {
    let days: Int
    let tier: FlameTier

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.08, blue: 0.07), Theme.bg], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                EmberMascot(mood: .cheer, tier: tier, animated: false)
                    .frame(height: 210)
                Text("\(days)")
                    .font(.rounded(120, .heavy))
                    .foregroundStyle(LinearGradient(colors: tier.outer.reversed(), startPoint: .top, endPoint: .bottom))
                Text("day study streak")
                    .font(.rounded(34, .heavy))
                    .foregroundStyle(.white)
                Text("Ember")
                    .font(.rounded(22, .bold))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 10)
            }
        }
        .frame(width: 540, height: 540)
    }
}
