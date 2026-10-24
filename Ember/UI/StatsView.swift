import Charts
import SwiftUI

/// Progress: streak, rank and XP, this week, the last 7 days by subject, why blocks went
/// unfinished, mock-exam scores, and the history.
struct StatsView: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    /// A total per subject or per distraction tag.
    private struct Amount: Identifiable {
        let id: String
        let subjectID: UUID?
        let count: Int
        let minutes: Double
    }

    private struct DayBar: Identifiable {
        let id = UUID()
        let label: String
        let subject: String
        let minutes: Double
    }

    var body: some View {
        let data = store.data
        let today = Today(data)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header(today)
                    WeekStrip(week: today.week, days: today.days)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    lastSevenDays(data, today)
                    bySubject(data, today)
                    distractions(data, today)
                    examScores(data)
                    NavigationLink {
                        HistoryView()
                    } label: {
                        HStack {
                            Label("History", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text("\(data.sessions.count) blocks").foregroundStyle(Theme.dim)
                            Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
                        }
                        .font(.rounded(17, .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .accessibilityIdentifier("history-link")
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func header(_ today: Today) -> some View {
        let rank = Rewards.rank(hours: today.lifetimeHours)
        let next = Rewards.next(after: rank)
        return HStack(spacing: 12) {
            tile(title: "Streak", value: "\(today.streak.current)", detail: "best \(max(today.streak.best, today.streak.current))", color: Theme.ember)
            tile(title: "Freezes", value: "\(today.streak.freezes) / \(Rules.maxFreezes)", detail: "save a missed day", color: Theme.ice)
            VStack(alignment: .leading, spacing: 6) {
                Text("RANK").font(.rounded(11, .heavy)).foregroundStyle(Theme.gold)
                Text(rank.name).font(.rounded(22, .heavy)).foregroundStyle(Theme.text)
                ProgressView(value: Rewards.progress(hours: today.lifetimeHours)).tint(Theme.gold)
                Text(next.map { "\(Int(today.lifetimeHours)) h · \($0.name) at \(Int($0.hours)) h" } ?? "\(Int(today.lifetimeHours)) h")
                    .font(.rounded(12, .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(today.totalXP) XP").font(.rounded(13, .bold)).foregroundStyle(Theme.gold)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func tile(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.rounded(11, .heavy)).foregroundStyle(color)
            Text(value).font(.rounded(30, .heavy)).foregroundStyle(Theme.text).monospacedDigit()
            Text(detail).font(.rounded(12, .semibold)).foregroundStyle(Theme.dim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func lastSevenDays(_ data: AppData, _ today: Today) -> some View {
        let keys = (0..<7).map { today.days.adding($0 - 6, to: today.key) }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        var bars: [DayBar] = []
        for key in keys {
            let label = key == today.key ? "Today" : formatter.string(from: today.days.noon(key))
            let blocks = data.sessions.filter { $0.day == key }
            if blocks.isEmpty { bars.append(DayBar(label: label, subject: "None", minutes: 0)) }
            for (subject, minutes) in Dictionary(grouping: blocks, by: { data.subject($0.subjectID)?.name ?? "No subject" })
                .mapValues({ $0.reduce(0) { $0 + $1.minutes } }) {
                bars.append(DayBar(label: label, subject: subject, minutes: minutes))
            }
        }
        let names = data.subjects.map(\.name) + ["No subject", "None"]
        let colors = data.subjects.map { SubjectPalette.color($0.colorIndex) } + [Theme.dim, .clear]
        let total = bars.reduce(0) { $0 + $1.minutes }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Last 7 days").font(.rounded(17, .bold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(TimeText.minutes(Int(total))).font(.rounded(15, .bold)).foregroundStyle(Theme.dim)
                }
                Chart(bars) { bar in
                    BarMark(x: .value("Day", bar.label), y: .value("Minutes", bar.minutes))
                        .foregroundStyle(by: .value("Subject", bar.subject))
                        .cornerRadius(4)
                }
                .chartForegroundStyleScale(domain: names, range: colors)
                .chartLegend(.hidden)
                .chartXScale(domain: keys.map { $0 == today.key ? "Today" : formatter.string(from: today.days.noon($0)) })
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel { if let m = value.as(Double.self) { Text("\(Int(m))").foregroundStyle(Theme.dim) } }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.dim) }
                }
                .frame(height: 200)
                .accessibilityIdentifier("week-chart")
            }
        }
    }

    private func bySubject(_ data: AppData, _ today: Today) -> some View {
        let since = today.days.adding(-6, to: today.key)
        let recent = data.sessions.filter { $0.day >= since }
        let totals = Dictionary(grouping: recent, by: \.subjectID)
            .map { Amount(id: $0.key?.uuidString ?? "none", subjectID: $0.key, count: 0, minutes: $0.value.reduce(0) { $0 + $1.minutes }) }
            .sorted { $0.minutes > $1.minutes }
        let top = totals.first?.minutes ?? 1
        return Group {
            if !totals.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("By subject, last 7 days").font(.rounded(17, .bold)).foregroundStyle(Theme.text)
                        ForEach(totals) { amount in
                            let subject = data.subject(amount.subjectID)
                            let minutes = amount.minutes
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(subject?.name ?? "No subject").font(.rounded(15, .semibold)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Text(TimeText.minutes(Int(minutes))).font(.rounded(14, .bold)).foregroundStyle(Theme.dim)
                                }
                                GeometryReader { geo in
                                    Capsule().fill(subject.map { SubjectPalette.color($0.colorIndex) } ?? Theme.dim)
                                        .frame(width: max(6, geo.size.width * minutes / max(1, top)))
                                }
                                .frame(height: 8)
                            }
                        }
                    }
                }
            }
        }
    }

    private func distractions(_ data: AppData, _ today: Today) -> some View {
        let since = today.days.adding(-29, to: today.key)
        let unfinished = data.sessions.filter { $0.outcome == .unfinished && $0.day >= since }
        let tags = Dictionary(grouping: unfinished, by: { $0.distraction ?? "Not said" })
            .map { Amount(id: $0.key, subjectID: nil, count: $0.value.count, minutes: 0) }
            .sorted { $0.count > $1.count }
        return Group {
            if !unfinished.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Why blocks went unfinished").font(.rounded(17, .bold)).foregroundStyle(Theme.text)
                        Text("\(unfinished.count) of \(data.sessions.filter { $0.day >= since }.count) blocks in the last 30 days.")
                            .font(.rounded(14, .medium)).foregroundStyle(Theme.dim)
                        ForEach(tags) { tag in
                            HStack {
                                Text(tag.id).font(.rounded(15, .semibold)).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(tag.count)").font(.rounded(15, .bold)).foregroundStyle(Theme.danger)
                            }
                        }
                    }
                }
            }
        }
    }

    private func examScores(_ data: AppData) -> some View {
        let scored = data.sessions.filter { $0.examScore != nil }.sorted { $0.startedAt > $1.startedAt }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return Group {
            if !scored.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mock exams").font(.rounded(17, .bold)).foregroundStyle(Theme.text)
                        ForEach(scored.prefix(8)) { record in
                            HStack {
                                Text(data.subject(record.subjectID)?.name ?? "Mock exam").font(.rounded(15, .semibold))
                                Text(formatter.string(from: record.startedAt)).font(.rounded(13, .medium)).foregroundStyle(Theme.dim)
                                Spacer()
                                Text(record.examScore ?? "").font(.rounded(16, .heavy)).foregroundStyle(Theme.gold)
                            }
                            .foregroundStyle(Theme.text)
                        }
                    }
                }
            }
        }
    }
}

/// Every block, newest first. Subject and goal line can be fixed; blocks can be deleted.
struct HistoryView: View {
    @ObservedObject private var store = Store.shared
    @State private var editing: SessionRecord?

    var body: some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, HH:mm"
        let sessions = store.data.sessions.sorted { $0.startedAt > $1.startedAt }
        return List {
            ForEach(sessions) { record in
                Button { editing = record } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon(record))
                            .foregroundStyle(record.outcome == .unfinished ? Theme.danger : Theme.ember)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(store.data.subject(record.subjectID)?.name ?? "No subject") · \(Int(record.minutes)) min")
                                .font(.rounded(16, .semibold))
                                .foregroundStyle(Theme.text)
                            Text(record.intent.isEmpty ? formatter.string(from: record.startedAt)
                                                       : "\(formatter.string(from: record.startedAt)) · \(record.intent)")
                                .font(.rounded(13, .medium))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(record.presetName).font(.rounded(13, .semibold)).foregroundStyle(Theme.dim)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                let ids = offsets.map { sessions[$0].id }
                store.data.sessions.removeAll { ids.contains($0.id) }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { record in
            RecordEditor(record: record)
        }
    }

    private func icon(_ record: SessionRecord) -> String {
        switch record.outcome {
        case .completed: return record.lockedMinutes > 0 ? "lock.fill" : "flame.fill"
        case .unfinished: return "xmark.circle.fill"
        case .interrupted: return "bolt.horizontal.circle.fill"
        }
    }
}

/// Fixes a block's subject or goal line.
struct RecordEditor: View {
    let record: SessionRecord
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var subjectID: UUID?
    @State private var intent = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Subject", selection: $subjectID) {
                    Text("No subject").tag(UUID?.none)
                    ForEach(store.data.subjects) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                TextField("Goal line", text: $intent)
            }
            .navigationTitle("Edit block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let i = store.data.sessions.firstIndex(where: { $0.id == record.id }) {
                            store.data.sessions[i].subjectID = subjectID
                            store.data.sessions[i].intent = intent
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                subjectID = record.subjectID
                intent = record.intent
            }
        }
        .preferredColorScheme(.dark)
    }
}
