import SwiftUI

/// Home: the streak, today's goal, Ember's mood, the next exam, and one big Start button.
struct HomeView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var controller = SessionController.shared
    @ObservedObject private var detector = LockDetector.shared
    @State private var intent = ""
    /// Lock In is waiting for Guided Access before starting this preset.
    @State private var armed: Preset?
    @State private var sheet: HomeSheet?
    @FocusState private var intentFocused: Bool

    enum HomeSheet: Identifiable {
        case technique, subject, mode, settings, streak, progress, exams, studyApp, topic
        case course(UUID)

        var id: String {
            if case let .course(subjectID) = self { return "course-\(subjectID)" }
            return String(describing: self)
        }
    }

    var body: some View {
        let data = store.data
        let today = Today(data)
        let greeting = today.greeting(hour: Calendar.current.component(.hour, from: Date()))
        let preset = data.prefs.preset
        let subject = data.subject(data.prefs.subjectID)
        let courseTopics = data.topics(of: subject?.id)
        let topic = data.topic(data.prefs.topicID).flatMap { $0.subjectID == subject?.id ? $0 : nil }

        ScrollView {
            VStack(spacing: 18) {
                topBar(today)
                banners
                EmberMascot(mood: greeting.mood, tier: today.tier, animated: !AppEnv.still)
                    .frame(height: 180)
                    .padding(.top, 4)
                Text(greeting.line)
                    .font(.rounded(20, .bold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("greeting")
                WeekStrip(week: today.week, days: today.days)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                courses(data)
                if let exam = today.nextExam {
                    Button { sheet = .exams } label: { examChip(exam, subject: data.subject(exam.subjectID)) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("exam-chip")
                                } else {
                    Button { sheet = .exams } label: {
                        Label("Add your exams", systemImage: "calendar.badge.plus")
                            .font(.rounded(15, .semibold))
                            .foregroundStyle(Theme.dim)
                    }
                    .accessibilityIdentifier("add-exams")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ChoiceChip(caption: "Technique", title: "\(preset.name) · \(preset.shortLabel)", identifier: "technique-chip") {
                        sheet = .technique
                    }
                    ChoiceChip(caption: "Subject", title: subject?.name ?? "No subject",
                               dot: subject.map { SubjectPalette.color($0.colorIndex) }, identifier: "subject-chip") {
                        sheet = .subject
                    }
                    ChoiceChip(caption: "Mode", title: data.prefs.strictness.label, identifier: "mode-chip") {
                        sheet = .mode
                    }
                    ChoiceChip(caption: "Study in", title: StudyApp.find(data.prefs.studyAppID)?.name ?? "Ember only",
                               identifier: "study-chip") {
                        sheet = .studyApp
                    }
                    if !courseTopics.isEmpty {
                        ChoiceChip(caption: "Topic", title: topic?.title ?? "Any topic",
                                   dot: topic.map { _ in Theme.gold }, identifier: "topic-chip") {
                            sheet = .topic
                        }
                    }
                }
                TextField("By the end I will…", text: $intent)
                    .font(.rounded(18, .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(intentFocused ? Theme.ember.opacity(0.6) : Theme.line))
                    .focused($intentFocused)
                    .submitLabel(.go)
                    .onSubmit { start(preset) }
                    .accessibilityIdentifier("intent-field")
                if let point = data.resume {
                    resumeCard(point, data: data)
                }
                Button("Start") { start(preset) }
                    .buttonStyle(ChunkyButtonStyle(height: 62))
                    .accessibilityIdentifier("start")
                Button {
                    start(.starter)
                } label: {
                    Text("Can't get going? **Just 5 minutes**")
                        .font(.rounded(16, .medium))
                        .foregroundStyle(Theme.dim)
                }
                .accessibilityIdentifier("starter")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if let preset = armed {
                ArmingView(onStartWithout: { begin(preset, strictness: .deep) }, onCancel: { armed = nil })
                    .transition(.opacity)
            }
        }
        .onChange(of: detector.guidedAccess) { _, on in
            if on, let preset = armed { begin(preset, strictness: .lockIn) }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .technique: TechniqueSheet()
            case .subject: SubjectSheet()
            case .mode: ModeSheet()
            case .settings: SettingsView()
            case .streak: StreakSheet()
            case .progress: StatsView()
            case .exams: ExamsView()
            case .studyApp: StudyAppSheet()
            case .topic:
                if let subjectID = store.data.prefs.subjectID { TopicPickerSheet(subjectID: subjectID) }
            case let .course(subjectID): CourseDetailView(subjectID: subjectID)
            }
        }
    }

    /// A session left with "Break to menu".
    private func resumeCard(_ point: ResumePoint, data: AppData) -> some View {
        let minutes = Int(Date().timeIntervalSince(point.at) / 60)
        let subject = data.subject(point.config.subjectID)?.name
        let topic = data.topic(point.config.topicID)?.title
        let what = [point.config.preset.name, subject, topic].compactMap { $0 }.joined(separator: " · ")
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("On a break for \(minutes < 1 ? "a moment" : TimeText.minutes(minutes))")
                    .font(.rounded(13, .bold))
                    .foregroundStyle(Theme.teal)
                Text("Round \(point.round) of \(what)")
                    .font(.rounded(17, .bold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Continue") { controller.resume() }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.teal, lip: Theme.tealDeep, height: 48))
                        .accessibilityIdentifier("continue-session")
                    Button("Not now") { store.data.resume = nil }
                        .font(.rounded(15, .semibold))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    /// The courses, each with its progress ring; tapping one opens its topics.
    @ViewBuilder private func courses(_ data: AppData) -> some View {
        let subjects = data.activeSubjects
        if !subjects.isEmpty {
            let now = Date()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(subjects) { subject in
                        Button {
                            sheet = .course(subject.id)
                        } label: {
                            CourseCard(subject: subject, topics: data.topics(of: subject.id),
                                       exam: data.exams.filter { $0.subjectID == subject.id && $0.at > now }.min { $0.at < $1.at },
                                       now: now)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("course-\(subject.name)")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func topBar(_ today: Today) -> some View {
        HStack(spacing: 14) {
            Button {
                sheet = .streak
            } label: {
                StreakPill(days: today.streak.current, tier: today.tier)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("streak-button")
            Spacer(minLength: 0)
            GoalRing(minutes: today.minutes, goal: today.goal)
            Button {
                sheet = .progress
            } label: {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Progress")
            .accessibilityIdentifier("progress-button")
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")
        }
    }

    @ViewBuilder private var banners: some View {
        if let notice = store.notice {
            Banner(text: notice, color: Theme.danger) { store.notice = nil }
        }
        if detector.guidedAccess && armed == nil {
            Banner(text: "Guided Access is still on. Triple-click Home and enter the passcode to leave Ember.",
                   color: Theme.gold, onClose: nil)
        }
        if let days = Provisioning.daysLeft, days <= 2 {
            Banner(text: days <= 0
                   ? "Ember's signature runs out today. Re-sign it with iloader on the PC."
                   : "Ember's signature runs out in \(days) day\(days == 1 ? "" : "s"). Re-sign it with iloader on the PC.",
                   color: Theme.gold, onClose: nil)
        }
    }

    private func examChip(_ exam: Exam, subject: StudySubject?) -> some View {
        let daysLeft = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                       to: Calendar.current.startOfDay(for: exam.at)).day ?? 0
        let when = daysLeft <= 0 ? "today" : daysLeft == 1 ? "tomorrow" : "in \(daysLeft) days"
        let urgent = daysLeft <= 3
        return HStack(spacing: 8) {
            Image(systemName: "calendar")
            Text("\(exam.title) exam \(when)")
                .lineLimit(1)
        }
        .font(.rounded(15, .bold))
        .foregroundStyle(urgent ? Theme.danger : Theme.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background((urgent ? Theme.danger : (subject.map { SubjectPalette.color($0.colorIndex) } ?? Theme.dim)).opacity(0.15),
                    in: Capsule())
    }

    private func start(_ preset: Preset) {
        intentFocused = false
        let strictness = store.data.prefs.strictness
        if strictness == .lockIn && !UIAccessibility.isGuidedAccessEnabled
            && (!AppEnv.isUITest || AppEnv.arguments.contains("-uitest-arming")) {
            armed = preset
        } else {
            begin(preset, strictness: strictness)
        }
    }

    private func begin(_ preset: Preset, strictness: Strictness) {
        armed = nil
        let prefs = store.data.prefs
        let topicID = store.data.topic(prefs.topicID).flatMap { $0.subjectID == prefs.subjectID ? $0.id : nil }
        controller.start(preset: preset, strictness: strictness, subjectID: prefs.subjectID, intent: intent,
                         studyApp: StudyApp.find(prefs.studyAppID), topicID: topicID)
        intent = ""
    }
}

struct Banner: View {
    let text: String
    let color: Color
    let onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(color)
            Text(text)
                .font(.rounded(14, .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(12)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
