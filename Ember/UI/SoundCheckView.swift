import SwiftUI

/// M0 check of the sounds, the noise generator and the mascot's moods and flame colours.
struct SoundCheckView: View {
    @ObservedObject private var audio = Audio.shared
    @State private var mood: Mood = .cheer
    @State private var countUp = 0
    @State private var counting = false

    private let effects: [(SoundEffect, String)] = [
        (.start, "Start"), (.complete, "Complete"), (.streak, "Streak"), (.milestone, "Milestone"),
        (.fizzle, "Unfinished"), (.breakEnd, "Break over"), (.cue, "Time check"), (.nudge, "Come back"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sounds").font(.rounded(17, .semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 4) {
                            ForEach(effects.indices, id: \.self) { i in
                                Button(effects[i].1) { Audio.shared.play(effects[i].0) }
                                    .buttonStyle(ChunkyButtonStyle(color: Theme.slate, lip: Theme.slateDeep, height: 48))
                            }
                        }
                        Button {
                            playCountUp()
                        } label: {
                            Text(counting ? "+\(countUp) XP" : "XP count-up")
                                .contentTransition(.numericText(value: Double(countUp)))
                        }
                        .buttonStyle(ChunkyButtonStyle())
                        .disabled(counting)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Focus noise").font(.rounded(17, .semibold))
                        Picker("Noise", selection: Binding(get: { audio.noise?.rawValue ?? "off" },
                                                           set: { audio.setNoise(NoiseColor(rawValue: $0)) })) {
                            Text("Off").tag("off")
                            ForEach(NoiseColor.allCases) { color in Text(color.label).tag(color.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Image(systemName: "speaker.fill").foregroundStyle(Theme.dim)
                            Slider(value: $audio.noiseVolume, in: 0...1)
                            Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.dim)
                        }
                        Text("Noise keeps playing when the screen locks. It also keeps Ember awake in the background, so run the Lock Lab test with noise off first.")
                            .font(.rounded(13, .regular))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ember's moods").font(.rounded(17, .semibold))
                        HStack(alignment: .center, spacing: 20) {
                            EmberMascot(mood: mood, tier: .glow, animated: !AppEnv.isUITest)
                                .frame(height: 140)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                                ForEach(Mood.allCases) { m in
                                    Button(m.rawValue.capitalized) { mood = m }
                                        .font(.rounded(14, .semibold))
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(m == mood ? Theme.ember.opacity(0.25) : Theme.cardHigh,
                                                    in: Capsule())
                                        .foregroundStyle(Theme.text)
                                }
                            }
                        }
                        Text("Flame colours by streak").font(.rounded(15, .semibold)).padding(.top, 6)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(FlameTier.allCases) { tier in
                                    VStack(spacing: 6) {
                                        EmberMascot(mood: tier == .ash ? .sleepy : .calm, tier: tier, animated: false, glow: false)
                                            .frame(height: 70)
                                        Text(tier == .ash ? "not yet" : "\(tier.startsAt)+ d")
                                            .font(.rounded(12, .semibold))
                                            .foregroundStyle(Theme.dim)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Sound check")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The celebration's XP count-up: eight rising ticks, then the completion chord.
    private func playCountUp() {
        counting = true
        countUp = 0
        Task { @MainActor in
            for i in 0..<8 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.snappy) { countUp = (i + 1) * 5 }
                Audio.shared.play(.tick(i))
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            Audio.shared.play(.complete)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            counting = false
        }
    }
}
