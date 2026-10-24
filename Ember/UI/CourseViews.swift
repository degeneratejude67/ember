import SwiftUI

/// A course on Home: progress ring, reviews due and the exam countdown. Opens the course.
struct CourseCard: View {
    let subject: StudySubject
    let topics: [Topic]
    let exam: Exam?
    let now: Date

    var body: some View {
        let progress = TopicProgress.progress(topics)
        let due = topics.filter { TopicProgress.isDue($0, now: now) }.count
        let color = SubjectPalette.color(subject.colorIndex)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    Circle().stroke(Theme.cardHigh, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.rounded(13, .heavy))
                        .foregroundStyle(Theme.text)
                }
                .frame(width: 52, height: 52)
                Spacer(minLength: 6)
                if due > 0 {
                    Text("\(due) due")
                        .font(.rounded(12, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.ember, in: Capsule())
                }
            }
            Text(subject.name)
                .font(.rounded(16, .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(examLine)
                .font(.rounded(12, .semibold))
                .foregroundStyle(examUrgent ? Theme.danger : Theme.dim)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 168, height: 156, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.35)))
    }

    private var examDays: Int? {
        guard let exam else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now),
                                               to: Calendar.current.startOfDay(for: exam.at)).day
    }

    private var examUrgent: Bool { (examDays ?? 99) <= 3 }

    private var examLine: String {
        guard let days = examDays else { return topics.isEmpty ? "Add topics" : "\(topics.count) topics" }
        return days <= 0 ? "Exam today" : days == 1 ? "Exam tomorrow" : "Exam in \(days) days"
    }
}

/// One course: progress, what to study next, reviews due, every topic by section, and the
/// past papers.
struct CourseDetailView: View {
    let subjectID: UUID
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editingTopic: Topic?
    @State private var adding = false

    var body: some View {
        let data = store.data
        let subject = data.subject(subjectID)
        let topics = data.topics(of: subjectID)
        let now = Date()
        let minutes = TopicProgress.minutes(data.sessions)
        let exam = data.exams.filter { $0.subjectID == subjectID && $0.at > now }.min { $0.at < $1.at }
        let due = topics.filter { TopicProgress.isDue($0, now: now) }
        let groups = Dictionary(grouping: topics, by: { $0.group ?? "" })
        let groupOrder = topics.reduce(into: [String]()) { names, t in
            let g = t.group ?? ""
            if !names.contains(g) { names.append(g) }
        }
        NavigationStack {
            List {
                Section {
                    header(topics: topics, exam: exam, now: now, hours: data.sessions.filter { $0.subjectID == subjectID }
                        .reduce(0) { $0 + $1.minutes } / 60)
                }
                .listRowBackground(Theme.card)

                let next = TopicProgress.next(topics, now: now)
                if !next.isEmpty {
                    Section("Study next") {
                        ForEach(next) { topic in
                            TopicRow(topic: topic, minutes: minutes[topic.id] ?? 0, now: now)
                                .contentShape(Rectangle())
                                .onTapGesture { studyNext(topic) }
                                .accessibilityIdentifier("next-\(topic.order)")
                        }
                    }
                }
                if !due.isEmpty {
                    Section("Due for review (\(due.count))") {
                        ForEach(due) { topic in row(topic, minutes: minutes) }
                    }
                }
                ForEach(groupOrder, id: \.self) { group in
                    Section(group.isEmpty ? "Topics" : group) {
                        ForEach(groups[group] ?? []) { topic in row(topic, minutes: minutes) }
                            .onDelete { offsets in
                                let ids = offsets.map { (groups[group] ?? [])[$0].id }
                                store.data.topics.removeAll { ids.contains($0.id) }
                            }
                    }
                }
                if topics.isEmpty {
                    Section {
                        Text("Add the course's topics (lectures, chapters or kinds of question) to track how well you know each one.")
                            .font(.rounded(15, .medium))
                            .foregroundStyle(Theme.dim)
                        Button("Add topics") { adding = true }
                    }
                }
                papersSection(data.papers(of: subjectID))
            }
            .navigationTitle(subject?.name ?? "Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("add-topics")
                }
            }
            .sheet(item: $editingTopic) { topic in TopicEditor(topic: topic) }
            .sheet(isPresented: $adding) { AddTopicsSheet(subjectID: subjectID) }
        }
        .preferredColorScheme(.dark)
    }

    private func header(topics: [Topic], exam: Exam?, now: Date, hours: Double) -> some View {
        let progress = TopicProgress.progress(topics)
        let counts = Dictionary(grouping: topics, by: \.status).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Theme.cardHigh, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(LinearGradient(colors: [Theme.ember, Theme.gold], startPoint: .bottom, endPoint: .top),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.rounded(22, .heavy))
                        .foregroundStyle(Theme.text)
                }
                .frame(width: 90, height: 90)
                .accessibilityIdentifier("course-progress")
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(counts[.mastered] ?? 0) mastered · \(counts[.reviewed] ?? 0) reviewed")
                        .font(.rounded(16, .bold)).foregroundStyle(Theme.text)
                    Text("\(counts[.learning] ?? 0) learning · \(counts[.notStarted] ?? 0) not started")
                        .font(.rounded(14, .semibold)).foregroundStyle(Theme.dim)
                    Text(String(format: "%.1f hours studied", hours))
                        .font(.rounded(14, .semibold)).foregroundStyle(Theme.dim)
                }
            }
            if let exam {
                let pace = TopicProgress.pace(topics, examAt: exam.at, now: now)
                Label(paceLine(exam: exam, pace: pace), systemImage: "calendar.badge.clock")
                    .font(.rounded(14, .bold))
                    .foregroundStyle(pace.days <= 3 ? Theme.danger : Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("High-yield topics (\u{2605}) are the ones asked most in past papers; they count twice in the percentage.")
                .font(.rounded(12, .medium))
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 6)
    }

    private func paceLine(exam: Exam, pace: (left: Int, perDay: Double, days: Int)) -> String {
        let when = pace.days <= 0 ? "today" : pace.days == 1 ? "tomorrow" : "in \(pace.days) days"
        guard pace.left > 0 else { return "Exam \(when). Every topic is at least reviewed: keep reviewing." }
        let rate = pace.perDay < 1 ? "1 every \(Int((1 / max(pace.perDay, 0.01)).rounded())) days" : String(format: "%.0f a day", pace.perDay.rounded(.up))
        return "Exam \(when): \(pace.left) topics still to learn, about \(rate)."
    }

    private func row(_ topic: Topic, minutes: [UUID: Double]) -> some View {
        TopicRow(topic: topic, minutes: minutes[topic.id] ?? 0, now: Date())
            .contentShape(Rectangle())
            .onTapGesture { editingTopic = topic }
            .swipeActions(edge: .leading) {
                Button { setStatus(topic, .mastered) } label: { Label("Mastered", systemImage: "checkmark.seal.fill") }
                    .tint(Theme.gold)
                Button { setStatus(topic, .learning) } label: { Label("Learning", systemImage: "circle.lefthalf.filled") }
                    .tint(Theme.ember)
            }
    }

    @ViewBuilder private func papersSection(_ papers: [PastPaper]) -> some View {
        if !papers.isEmpty {
            Section {
                ForEach(papers) { paper in
                    Button {
                        if let i = store.data.papers.firstIndex(where: { $0.id == paper.id }) {
                            store.data.papers[i].done.toggle()
                            store.data.papers[i].doneAt = store.data.papers[i].done ? Date() : nil
                        }
                    } label: {
                        HStack {
                            Image(systemName: paper.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(paper.done ? Theme.teal : Theme.dim)
                            Text(paper.session).font(.rounded(16, .semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            if let score = paper.score {
                                Text(score).font(.rounded(15, .heavy)).foregroundStyle(Theme.gold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Past papers (\(papers.filter(\.done).count) of \(papers.count) done)")
            } footer: {
                Text("Run one as a Mock exam and its score is saved here.")
            }
        }
    }

    private func setStatus(_ topic: Topic, _ status: TopicStatus) {
        guard let i = store.data.topics.firstIndex(where: { $0.id == topic.id }) else { return }
        store.data.topics[i] = TopicProgress.set(topic, status: status, now: Date())
    }

    /// Picks the topic (and its course) for the next block, then goes back to Home.
    private func studyNext(_ topic: Topic) {
        store.data.prefs.subjectID = topic.subjectID
        store.data.prefs.topicID = topic.id
        dismiss()
    }
}

struct TopicRow: View {
    let topic: Topic
    let minutes: Double
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: topic.status.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if topic.starred {
                        Image(systemName: "star.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.gold)
                    }
                    Text(topic.title)
                        .font(.rounded(15, .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(detail)
                    .font(.rounded(12, .medium))
                    .foregroundStyle(TopicProgress.isDue(topic, now: now) ? Theme.ember : Theme.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch topic.status {
        case .notStarted: return Theme.dim
        case .learning: return Theme.ember
        case .reviewed: return Theme.teal
        case .mastered: return Theme.gold
        }
    }

    private var detail: String {
        var parts = [topic.status.label]
        if minutes >= 1 { parts.append(TimeText.minutes(Int(minutes))) }
        if let asked = topic.asked, asked > 0 { parts.append("asked \(asked)×") }
        if let due = topic.reviewDue, topic.status != .notStarted {
            if due <= now {
                parts.append("review due")
            } else {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: due).day ?? 0
                parts.append(days <= 1 ? "review tomorrow" : "review in \(days) days")
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Edits one topic: status, high-yield star, notes; or picks it for the next block.
struct TopicEditor: View {
    let topic: Topic
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var status: TopicStatus = .notStarted
    @State private var starred = false
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Topic", text: $title)
                Picker("How well you know it", selection: $status) {
                    ForEach(TopicStatus.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                Toggle("High-yield", isOn: $starred)
                Section("Notes") {
                    TextField("Formulas to remember, weak spots…", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Button("Study this in the next block") {
                        save()
                        store.data.prefs.subjectID = topic.subjectID
                        store.data.prefs.topicID = topic.id
                        dismiss()
                    }
                    .accessibilityIdentifier("study-topic")
                }
            }
            .navigationTitle("Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                title = topic.title
                status = topic.status
                starred = topic.starred
                note = topic.note
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard let i = store.data.topics.firstIndex(where: { $0.id == topic.id }) else { return }
        var updated = store.data.topics[i]
        if updated.status != status { updated = TopicProgress.set(updated, status: status, now: Date()) }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { updated.title = trimmed }
        updated.starred = starred
        updated.note = note
        store.data.topics[i] = updated
    }
}

/// Paste or type topics, one per line; a line ending in ":" starts a section.
struct AddTopicsSheet: View {
    let subjectID: UUID
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("One topic per line", text: $text, axis: .vertical)
                        .lineLimit(8...20)
                        .accessibilityIdentifier("topics-text")
                } footer: {
                    Text("Paste a syllabus or the slide titles. A line ending in a colon (\u{201C}Anup Sir:\u{201D}) starts a section for the lines under it.")
                }
            }
            .navigationTitle("Add topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        add()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func add() {
        var order = (store.data.topics(of: subjectID).map(\.order).max() ?? -1) + 1
        var group: String?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "•-*\u{2013}"))
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasSuffix(":") {
                group = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            store.data.topics.append(Topic(subjectID: subjectID, title: line, group: group, order: order))
            order += 1
        }
    }
}

/// Picks the topic for the next block: suggestions first, then the whole course.
struct TopicPickerSheet: View {
    let subjectID: UUID
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showCourse = false

    var body: some View {
        let topics = store.data.topics(of: subjectID)
        let now = Date()
        let minutes = TopicProgress.minutes(store.data.sessions)
        let next = TopicProgress.next(topics, now: now, limit: 4)
        NavigationStack {
            List {
                Section {
                    choice(nil, title: "Any topic", detail: "Just the course")
                }
                if !next.isEmpty {
                    Section("Suggested") {
                        ForEach(next) { topic in pick(topic, minutes: minutes, now: now) }
                    }
                }
                Section("All topics") {
                    ForEach(topics) { topic in pick(topic, minutes: minutes, now: now) }
                }
            }
            .navigationTitle("Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Course") { showCourse = true }
                }
            }
            .sheet(isPresented: $showCourse) { CourseDetailView(subjectID: subjectID) }
        }
        .preferredColorScheme(.dark)
    }

    private func pick(_ topic: Topic, minutes: [UUID: Double], now: Date) -> some View {
        Button {
            store.data.prefs.topicID = topic.id
            dismiss()
        } label: {
            HStack {
                TopicRow(topic: topic, minutes: minutes[topic.id] ?? 0, now: now)
                if store.data.prefs.topicID == topic.id {
                    Image(systemName: "checkmark").foregroundStyle(Theme.ember)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("topic-\(topic.order)")
    }

    private func choice(_ id: UUID?, title: String, detail: String) -> some View {
        Button {
            store.data.prefs.topicID = id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.rounded(16, .bold)).foregroundStyle(Theme.text)
                    Text(detail).font(.rounded(13, .medium)).foregroundStyle(Theme.dim)
                }
                Spacer()
                if store.data.prefs.topicID == id { Image(systemName: "checkmark").foregroundStyle(Theme.ember) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
