import SwiftUI
import UserNotifications

/// First launch: meet Ember, commit to a daily goal, add subjects and the next exam, allow
/// reminders. Four short pages; everything can be changed later.
struct OnboardingView: View {
    @ObservedObject private var store = Store.shared
    @State private var page = 0
    @State private var goal = 60
    @State private var subjects: [String] = []
    @State private var newSubject = ""
    @State private var hasExam = false
    @State private var examSubject = ""
    @State private var examDate = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date()))!
        .addingTimeInterval(9.5 * 3600)

    private struct GoalOption: Identifiable {
        let minutes: Int
        let name: String
        let note: String
        var id: Int { minutes }
    }

    private static let goals = [
        GoalOption(minutes: 30, name: "Casual", note: "A little every day"),
        GoalOption(minutes: 60, name: "Regular", note: "One solid hour"),
        GoalOption(minutes: 120, name: "Serious", note: "Two hours of real focus"),
        GoalOption(minutes: 240, name: "Exam mode", note: "Four hours: exams are close"),
    ]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    switch page {
                    case 0: welcome
                    case 1: goalPage
                    case 2: subjectsPage
                    default: remindersPage
                    }
                }
                .padding(28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: page)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            EmberMascot(mood: .cheer, tier: .glow, animated: !AppEnv.still)
                .frame(height: 230)
                .padding(.top, 30)
            Text("Hi, I'm Ember.")
                .font(.rounded(40, .heavy))
                .foregroundStyle(Theme.text)
            Text("I time focused study blocks and keep you honest: leave the app mid-block and the block ends. Finish one every day and I burn brighter.")
                .font(.rounded(19, .medium))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Let's go") { page = 1 }
                .buttonStyle(ChunkyButtonStyle(height: 60))
                .accessibilityIdentifier("onboarding-next")
        }
    }

    private var goalPage: some View {
        VStack(spacing: 16) {
            Text("How much will you study each day?")
                .font(.rounded(30, .heavy))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .padding(.top, 30)
            Text("Your streak only needs one block a day. The goal is what a good day looks like.")
                .font(.rounded(16, .medium))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
            ForEach(Self.goals) { option in
                Button {
                    goal = option.minutes
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name).font(.rounded(19, .heavy))
                            Text(option.note).font(.rounded(14, .medium)).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Text(TimeText.minutes(option.minutes)).font(.rounded(17, .bold))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(16)
                    .background(goal == option.minutes ? Theme.ember.opacity(0.18) : Theme.card,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(goal == option.minutes ? Theme.ember : Theme.line, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("goal-\(option.minutes)")
            }
            Button("Commit to my goal") { page = 2 }
                .buttonStyle(ChunkyButtonStyle(height: 60))
                .padding(.top, 8)
                .accessibilityIdentifier("onboarding-next")
        }
    }

    private var subjectsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What are you studying?")
                .font(.rounded(30, .heavy))
                .foregroundStyle(Theme.text)
                .padding(.top, 30)
            HStack {
                TextField("Add a subject, e.g. Heat Transfer", text: $newSubject)
                    .font(.rounded(17, .medium))
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onSubmit(addSubject)
                    .accessibilityIdentifier("onboarding-subject")
                Button("Add", action: addSubject)
                    .font(.rounded(16, .bold))
                    .disabled(newSubject.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            FlowChips(items: subjects) { name in subjects.removeAll { $0 == name } }
            Toggle(isOn: $hasExam) {
                Text("I have an exam coming up").font(.rounded(17, .semibold)).foregroundStyle(Theme.text)
            }
            .tint(Theme.ember)
            .padding(.top, 6)
            if hasExam {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Exam name", text: $examSubject)
                        .font(.rounded(17, .medium))
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    DatePicker("When", selection: $examDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .font(.rounded(17, .semibold))
                }
            }
            Button("Continue") { page = 3 }
                .buttonStyle(ChunkyButtonStyle(height: 60))
                .padding(.top, 8)
                .accessibilityIdentifier("onboarding-next")
        }
    }

    private var remindersPage: some View {
        VStack(spacing: 20) {
            EmberMascot(mood: .worried, tier: .glow, animated: !AppEnv.still)
                .frame(height: 170)
                .padding(.top, 30)
            Text("Can I nudge you?")
                .font(.rounded(32, .heavy))
                .foregroundStyle(Theme.text)
            Text("Only on days you haven't studied yet: once at your usual time, and a last call at 10 pm. Plus a chime when a block or break ends.")
                .font(.rounded(18, .medium))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow reminders") {
                if !AppEnv.isUITest {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                }
                finish(reminders: true)
            }
            .buttonStyle(ChunkyButtonStyle(height: 60))
            .accessibilityIdentifier("onboarding-allow")
            Button("Not now") { finish(reminders: false) }
                .font(.rounded(16, .semibold))
                .foregroundStyle(Theme.dim)
        }
    }

    private func addSubject() {
        let name = newSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !subjects.contains(name) else { return }
        subjects.append(name)
        newSubject = ""
    }

    private func finish(reminders: Bool) {
        var data = store.data
        data.prefs.goalMinutes = goal
        data.prefs.remindersOn = reminders
        for name in subjects where !data.subjects.contains(where: { $0.name == name }) {
            data.subjects.append(StudySubject(name: name, colorIndex: data.subjects.count))
        }
        if data.prefs.subjectID == nil { data.prefs.subjectID = data.subjects.first?.id }
        let examName = examSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasExam {
            let subject = data.subjects.first { $0.name.caseInsensitiveCompare(examName) == .orderedSame }
            data.exams.append(Exam(subjectID: subject?.id, title: examName.isEmpty ? "Exam" : examName, at: examDate))
        }
        data.prefs.onboarded = true
        store.data = data
        SessionController.shared.refreshReminders()
    }
}

/// Removable chips that wrap onto new lines.
struct FlowChips: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                HStack(spacing: 6) {
                    Circle().fill(SubjectPalette.color(index)).frame(width: 10, height: 10)
                    Text(item).font(.rounded(15, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { onRemove(item) } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.dim)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.card, in: Capsule())
            }
        }
    }
}
