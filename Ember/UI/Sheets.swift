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

/// Relaxed or Deep Focus (Lock In arrives with Guided Access support).
struct ModeSheet: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach([Strictness.deep, .relaxed]) { mode in
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
            .navigationTitle("Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}
