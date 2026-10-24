import SwiftUI

/// Picks the study technique, with the Custom lengths and the mock-exam length.
struct TechniqueSheet: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let prefs = store.data.prefs
        NavigationStack {
            List {
                Section {
                    ForEach(Preset.builtIn) { preset in
                        row(prefs.preset(id: preset.id))
                    }
                    row(prefs.custom)
                } footer: {
                    Text("Fixed breaks beat self-chosen ones: in a 2023 study, students on a timer reported less fatigue and distraction, and finished just as much.")
                }
                if prefs.presetID == Preset.exam.id {
                    Section("Mock exam length") {
                        Stepper(TimeText.minutes(prefs.examMinutes), value: $store.data.prefs.examMinutes, in: 30...240, step: 15)
                    }
                }
                if prefs.presetID == Preset.customDefault.id {
                    Section("Custom") {
                        Stepper("Focus \(prefs.custom.focusMinutes) min", value: $store.data.prefs.custom.focusMinutes, in: 5...180, step: 5)
                        Stepper("Break \(prefs.custom.shortBreakMinutes) min", value: $store.data.prefs.custom.shortBreakMinutes, in: 1...60)
                        Stepper("Long break \(prefs.custom.longBreakMinutes) min", value: $store.data.prefs.custom.longBreakMinutes, in: 1...60)
                        Stepper(prefs.custom.longEvery == 0 ? "No long break" : "Long break every \(prefs.custom.longEvery) rounds",
                                value: $store.data.prefs.custom.longEvery, in: 0...8)
                    }
                }
            }
            .navigationTitle("Technique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ preset: Preset) -> some View {
        let selected = store.data.prefs.presetID == preset.id
        return Button {
            store.data.prefs.presetID = preset.id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(preset.name).font(.rounded(17, .bold)).foregroundStyle(Theme.text)
                        Text(preset.shortLabel).font(.rounded(14, .semibold)).foregroundStyle(Theme.dim)
                    }
                    Text(preset.note)
                        .font(.rounded(14, .regular))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ember).font(.system(size: 20))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preset-\(preset.id)")
    }
}

/// Picks or adds the subject for the next block.
struct SubjectSheet: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice(nil, name: "No subject", color: Theme.dim)
                    ForEach(store.data.activeSubjects) { subject in
                        choice(subject.id, name: subject.name, color: SubjectPalette.color(subject.colorIndex))
                    }
                    .onDelete(perform: archive)
                } footer: {
                    Text("Swipe to remove a subject. Its history stays.")
                }
                Section("Add a subject") {
                    HStack {
                        TextField("e.g. Heat Transfer", text: $newName)
                            .onSubmit(add)
                            .accessibilityIdentifier("new-subject")
                        Button("Add", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func choice(_ id: UUID?, name: String, color: Color) -> some View {
        Button {
            if store.data.prefs.subjectID != id { store.data.prefs.topicID = nil }
            store.data.prefs.subjectID = id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 12, height: 12)
                Text(name).font(.rounded(17, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if store.data.prefs.subjectID == id {
                    Image(systemName: "checkmark").foregroundStyle(Theme.ember)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let subject = StudySubject(name: name, colorIndex: store.data.subjects.count)
        store.data.subjects.append(subject)
        store.data.prefs.subjectID = subject.id
        newName = ""
    }

    private func archive(_ offsets: IndexSet) {
        let ids = offsets.map { store.data.activeSubjects[$0].id }
        for id in ids {
            if let i = store.data.subjects.firstIndex(where: { $0.id == id }) { store.data.subjects[i].archived = true }
            if store.data.prefs.subjectID == id { store.data.prefs.subjectID = nil }
        }
    }
}

/// Relaxed, Deep Focus or Lock In, with the two setup guides.
struct ModeSheet: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var guide: Guide?

    enum Guide: String, Identifiable {
        case lockIn, focusGuard
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    modes
                }
                Section("Make it stricter") {
                    Button { guide = .lockIn } label: {
                        Label("Set up Lock In (Guided Access)", systemImage: "lock.fill")
                    }
                    Button { guide = .focusGuard } label: {
                        Label("Set up Focus Guard (Shortcuts)", systemImage: "shield.lefthalf.filled")
                    }
                }
            }
            .navigationTitle("Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $guide) { which in
                switch which {
                case .lockIn: LockInGuide()
                case .focusGuard: FocusGuardGuide()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var modes: some View {
        ForEach([Strictness.deep, .lockIn, .relaxed]) { mode in
            Button {
                store.data.prefs.strictness = mode
                dismiss()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.label).font(.rounded(17, .bold)).foregroundStyle(Theme.text)
                        Text(mode.summary)
                            .font(.rounded(14, .regular))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if store.data.prefs.strictness == mode {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ember).font(.system(size: 20))
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mode-\(mode.rawValue)")
        }
    }
}

/// Where he studies during blocks: in Ember only (paper, past papers), or inside a study app.
struct StudyAppSheet: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice(nil, name: "Ember only", icon: "flame.fill",
                           note: "Paper, books, past papers. Leaving Ember ends the block.")
                    ForEach(StudyApp.all) { app in
                        choice(app.id, name: app.name, icon: app.icon,
                               note: app.url == nil ? "Switch to it yourself after Start." : "Start opens it for you.")
                    }
                } footer: {
                    Text("When you study in another app, the time there counts as focus. iPadOS doesn't tell Ember which app you're in, so set up Focus Guard: then YouTube, Instagram or a game sends you straight back.")
                }
                Section("Keep the timer in sight") {
                    tip("rectangle.split.2x1", "Split View: open your notes, then drag Ember from the Dock to the side of the screen.")
                    tip("rectangle.righthalf.inset.filled", "Slide Over: drag Ember onto your notes. Swipe in from the right edge to peek at the timer, swipe it away to hide it.")
                    tip("bell.badge", "When the block ends you get Ember's chime and a notification; tap it to come back.")
                }
            }
            .navigationTitle("Study in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func choice(_ id: String?, name: String, icon: String, note: String) -> some View {
        Button {
            store.data.prefs.studyAppID = id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Theme.ember).frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.rounded(17, .bold)).foregroundStyle(Theme.text)
                    Text(note).font(.rounded(13, .regular)).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
                if store.data.prefs.studyAppID == id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ember).font(.system(size: 20))
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("study-\(id ?? "ember")")
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.teal).frame(width: 26)
            Text(text).font(.rounded(15, .regular)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
