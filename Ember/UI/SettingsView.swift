import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var guide: ModeSheet.Guide?

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
                    Picker("Grace time", selection: $store.data.prefs.graceSeconds) {
                        ForEach([5, 10, 20, 30], id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    Picker("Mode for new blocks", selection: $store.data.prefs.strictness) {
                        ForEach(Strictness.allCases) { Text($0.label).tag($0) }
                    }
                    Button("Set up Lock In (Guided Access)") { guide = .lockIn }
                    Button("Set up Focus Guard (Shortcuts)") { guide = .focusGuard }
                } header: {
                    Text("Deep Focus")
                } footer: {
                    Text("Leaving Ember for longer than the grace time ends the block. Locking the screen and Split View are fine.")
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

                Section("Data") {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Export history (JSON)", systemImage: "square.and.arrow.up")
                        }
                    }
                    LabeledContent("Blocks saved", value: "\(store.data.sessions.count)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { exportURL = store.exportFile() }
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
}
