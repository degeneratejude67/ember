import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var guide: ModeSheet.Guide?
    @State private var importing = false
    @State private var importResult: String?

    var body: some View {
        let prefs = store.data.prefs
        NavigationStack {
            Form {
                Section {
                    Stepper("\(prefs.goalMinutes) minutes a day", value: $store.data.prefs.goalMinutes, in: 15...600, step: 15)
                        .accessibilityIdentifier("goal-stepper")
                } header: {
                    Text("Daily goal")
                } footer: {
                    Text("The goal is separate from the streak: one finished block of 10 minutes or more keeps the streak alive.")
                }

                Section {
                    Picker("Any other app", selection: $store.data.prefs.graceSeconds) {
                        Text("10 seconds (strict)").tag(10)
                        Text("2 minutes").tag(120)
                        Text("3 minutes").tag(180)
                        Text("5 minutes").tag(300)
                    }
                    .accessibilityIdentifier("allowance-picker")
                    Picker("Helper apps", selection: $store.data.prefs.helperSeconds) {
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                        Text("15 minutes").tag(900)
                        Text("20 minutes").tag(1200)
                    }
                    .disabled(prefs.graceSeconds < 120)
                    Picker("Mode for new blocks", selection: $store.data.prefs.strictness) {
                        ForEach(Strictness.allCases) { Text($0.label).tag($0) }
                    }
                    Button("Set up Lock In (Guided Access)") { guide = .lockIn }
                    Button("Set up App detection (Shortcuts)") { guide = .focusGuard }
                } header: {
                    Text("Deep Focus")
                } footer: {
                    Text("Your study app (CollaNote, Slate) has no limit, helper apps (Safari, YouTube, Gemini, Claude) get the longer time, and any other app the shorter one. When the time is up, Ember asks \u{201C}Still studying?\u{201D}; the block ends only if there's no answer within a minute. Ember can only tell the apps apart with the App detection automations (Set up App detection). Locking the screen and Split View are always fine.")
                }

                Section("Timer") {
                    Picker("Style", selection: $store.data.prefs.timerStyle) {
                        ForEach(TimerStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Sounds", isOn: $store.data.prefs.soundsOn)
                    Picker("Focus noise", selection: $store.data.prefs.noise) {
                        Text("Off").tag(NoiseColor?.none)
                        ForEach(NoiseColor.allCases) { Text($0.label).tag(NoiseColor?.some($0)) }
                    }
                    if prefs.noise != nil {
                        Slider(value: $store.data.prefs.noiseVolume, in: 0...1) { Text("Noise volume") }
                    }
                }

                Section {
                    Toggle("Streak reminders", isOn: $store.data.prefs.remindersOn)
                        .onChange(of: prefs.remindersOn) { _, _ in SessionController.shared.refreshReminders() }
                } footer: {
                    Text("Only on days without a block yet: one at the time you usually start, and a last call at 10 pm.")
                }

                Section {
                    Picker("Study day starts at", selection: $store.data.prefs.dayStartHour) {
                        ForEach(0...6, id: \.self) { hour in Text(hour == 0 ? "Midnight" : "\(hour) am").tag(hour) }
                    }
                } footer: {
                    Text("Blocks before this hour count for the day before, so late-night study keeps yesterday's streak.")
                }

                Section("This build") {
                    if let days = Provisioning.daysLeft {
                        LabeledContent("Signature", value: days <= 0 ? "runs out today" : "\(days) days left")
                    }
                    NavigationLink("Lock Lab") { LockLabView() }
                    NavigationLink("Sound check") { SoundCheckView() }
                }

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Export history (JSON)", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Import courses (JSON)", systemImage: "square.and.arrow.down")
                    }
                    if let importResult {
                        Text(importResult).font(.rounded(13, .medium)).foregroundStyle(Theme.dim)
                    }
                    LabeledContent("Blocks saved", value: "\(store.data.sessions.count)")
                } header: {
                    Text("Data")
                } footer: {
                    Text("A course file lists courses, their lectures and slide counts: {\"courses\": [{\"name\": \"…\", \"topics\": [{\"title\": \"Lecture 1\", \"slides\": 40}]}]}. Courses already here are matched by name and only new lectures are added.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { exportURL = store.exportFile() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                importResult = importCourses(result)
            }
            .onChange(of: prefs.noiseVolume) { _, volume in Audio.shared.noiseVolume = Float(volume) }
            .sheet(item: $guide) { which in
                switch which {
                case .lockIn: LockInGuide()
                case .focusGuard: FocusGuardGuide()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Copies a picked course file into Documents/Import and merges it.
    private func importCourses(_ result: Result<URL, Error>) -> String {
        guard case let .success(url) = result else { return "Nothing imported." }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let before = (store.data.subjects.count, store.data.topics.count)
        let folder = AppEnv.dataRoot.appendingPathComponent("Import", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: target)
        guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { return "Couldn't read that file." }
        SessionController.shared.importCourses()
        let courses = store.data.subjects.count - before.0
        let lectures = store.data.topics.count - before.1
        return lectures == 0 && courses == 0 ? "Nothing new in that file." : "Added \(courses) courses and \(lectures) lectures."
    }
}
