import SwiftUI

/// Exams with their countdowns, the hours studied for each since it was added, and mock-exam
/// scores for that subject.
struct ExamsView: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Exam?
    @State private var adding = false

    var body: some View {
        let exams = store.data.exams.sorted { $0.at < $1.at }
        NavigationStack {
            List {
                if exams.isEmpty {
                    Text("No exams yet. Add one to see a countdown on Home and track your hours for it.")
                        .font(.rounded(15, .medium))
                        .foregroundStyle(Theme.dim)
                }
                ForEach(exams) { exam in
                    Button { editing = exam } label: { row(exam) }
                        .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let ids = offsets.map { exams[$0].id }
                    store.data.exams.removeAll { ids.contains($0.id) }
                }
            }
            .navigationTitle("Exams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("add-exam")
                }
            }
            .sheet(item: $editing) { exam in ExamEditor(exam: exam) }
            .sheet(isPresented: $adding) { ExamEditor(exam: nil) }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ exam: Exam) -> some View {
        let subject = store.data.subject(exam.subjectID)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, HH:mm"
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: exam.at)).day ?? 0
        let studied = store.data.sessions
            .filter { $0.subjectID != nil && $0.subjectID == exam.subjectID && $0.startedAt >= exam.createdAt }
            .reduce(0) { $0 + $1.minutes } / 60
        let scores = store.data.sessions.filter { $0.subjectID == exam.subjectID && $0.examScore != nil }.compactMap(\.examScore)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(subject.map { SubjectPalette.color($0.colorIndex) } ?? Theme.dim).frame(width: 10, height: 10)
                Text(exam.title).font(.rounded(18, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text(days < 0 ? "done" : days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days) days")
                    .font(.rounded(15, .heavy))
                    .foregroundStyle(days <= 3 && days >= 0 ? Theme.danger : Theme.ember)
            }
            Text(formatter.string(from: exam.at)).font(.rounded(14, .medium)).foregroundStyle(Theme.dim)
            if let target = exam.targetHours, target > 0 {
                ProgressView(value: min(1, studied / target)).tint(Theme.ember)
                Text(String(format: "%.1f of %.0f hours studied since you added it", studied, target))
                    .font(.rounded(13, .semibold)).foregroundStyle(Theme.dim)
            } else if exam.subjectID != nil {
                Text(String(format: "%.1f hours studied since you added it", studied))
                    .font(.rounded(13, .semibold)).foregroundStyle(Theme.dim)
            }
            if !scores.isEmpty {
                Text("Mock exams: " + scores.suffix(4).joined(separator: ", "))
                    .font(.rounded(13, .semibold)).foregroundStyle(Theme.gold)
            }
            let topics = store.data.topics(of: exam.subjectID)
            if !topics.isEmpty {
                let pace = TopicProgress.pace(topics, examAt: exam.at, now: Date())
                Text("\(Int((TopicProgress.progress(topics) * 100).rounded()))% done · \(pace.left) \(pace.unit) to go")
                    .font(.rounded(13, .bold)).foregroundStyle(Theme.ember)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Adds or edits one exam.
struct ExamEditor: View {
    let exam: Exam?
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var subjectID: UUID?
    @State private var at = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    @State private var hasTarget = false
    @State private var targetHours = 10.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exam name", text: $title)
                    .accessibilityIdentifier("exam-title")
                Picker("Subject", selection: $subjectID) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.data.activeSubjects) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                DatePicker("When", selection: $at, displayedComponents: [.date, .hourAndMinute])
                Toggle("Target study hours", isOn: $hasTarget)
                if hasTarget {
                    Stepper(String(format: "%.0f hours", targetHours), value: $targetHours, in: 1...100)
                }
            }
            .navigationTitle(exam == nil ? "New exam" : "Edit exam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty && subjectID == nil)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        guard let exam else {
            subjectID = store.data.prefs.subjectID
            title = store.data.subject(subjectID)?.name ?? ""
            return
        }
        title = exam.title
        subjectID = exam.subjectID
        at = exam.at
        hasTarget = exam.targetHours != nil
        targetHours = exam.targetHours ?? 10
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = name.isEmpty ? (store.data.subject(subjectID)?.name ?? "Exam") : name
        if let exam, let i = store.data.exams.firstIndex(where: { $0.id == exam.id }) {
            store.data.exams[i].title = finalTitle
            store.data.exams[i].subjectID = subjectID
            store.data.exams[i].at = at
            store.data.exams[i].targetHours = hasTarget ? targetHours : nil
        } else {
            store.data.exams.append(Exam(subjectID: subjectID, title: finalTitle, at: at, targetHours: hasTarget ? targetHours : nil))
        }
        dismiss()
    }
}
