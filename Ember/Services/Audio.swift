import AVFoundation
import Foundation

/// Ember's pre-rendered sound effects (tools/make_sounds.py). The file names double as
/// notification sound names.
enum SoundEffect: String, CaseIterable {
    case tap, start, complete, streak, milestone, fizzle, cue, nudge
    case breakEnd = "break-end"
    case tick1, tick2, tick3, tick4, tick5, tick6, tick7, tick8

    var fileName: String { rawValue + ".wav" }

    /// The count-up ticks rise a whole tone each; `index` 0...7.
    static func tick(_ index: Int) -> SoundEffect {
        let ticks: [SoundEffect] = [.tick1, .tick2, .tick3, .tick4, .tick5, .tick6, .tick7, .tick8]
        return ticks[min(max(index, 0), ticks.count - 1)]
    }
}

enum NoiseColor: String, CaseIterable, Codable, Identifiable {
    case white, pink, brown

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Plays sound effects and runs the ambient noise generator.
///
/// Effects use the `.ambient` session, which mixes with other audio and respects silent
/// mode. While noise plays the session is `.playback` + `.mixWithOthers`, so the noise
/// keeps going on the lock screen (UIBackgroundModes: audio) next to the user's music.
final class Audio: ObservableObject {
    static let shared = Audio()

    @Published var effectsOn = true
    @Published private(set) var noise: NoiseColor?
    @Published var noiseVolume: Float = 0.5 {
        didSet { noiseEngine.volume = noiseVolume }
    }

    private var players: [SoundEffect: AVAudioPlayer] = [:]
    private let noiseEngine = NoiseEngine()

    private init() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let noise = self.noise,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self.noiseEngine.start(noise)
        }
    }

    /// Loads every effect once, so the first play has no delay.
    func preload() {
        for effect in SoundEffect.allCases { _ = player(for: effect) }
    }

    func play(_ effect: SoundEffect) {
        guard effectsOn, let player = player(for: effect) else { return }
        configureSession()
        player.currentTime = 0
        player.play()
    }

    func setNoise(_ color: NoiseColor?) {
        noise = color
        configureSession()
        if let color {
            noiseEngine.volume = noiseVolume
            noiseEngine.start(color)
        } else {
            noiseEngine.stop()
        }
    }

    private func player(for effect: SoundEffect) -> AVAudioPlayer? {
        if let player = players[effect] { return player }
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[effect] = player
        return player
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        if noise != nil {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } else {
            try? session.setCategory(.ambient, mode: .default, options: [])
        }
        try? session.setActive(true)
    }
}

/// White, pink or brown noise generated live by an `AVAudioSourceNode`.
final class NoiseEngine {
    private let engine = AVAudioEngine()
    private let state = NoiseState()
    private var source: AVAudioSourceNode?

    var volume: Float = 0.5 {
        didSet { state.target = volume }
    }

    init() {
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.source != nil, !self.engine.isRunning else { return }
            try? self.engine.start()
        }
    }

    func start(_ color: NoiseColor) {
        state.color = color
        state.target = volume
        if source == nil {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            let state = self.state
            let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                guard let data = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                for i in 0..<Int(frameCount) {
                    data[i] = state.next()
                }
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            source = node
        }
        if !engine.isRunning { try? engine.start() }
    }

    func stop() {
        state.target = 0
        // let the fade-out finish before pausing the engine
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.state.target == 0 else { return }
            self.engine.pause()
        }
    }
}

/// Filter state for the noise, touched only on the audio render thread (plus the two
/// settings, which may change mid-buffer without harm).
final class NoiseState {
    var color: NoiseColor = .brown
    var target: Float = 0
    private var gain: Float = 0
    private var seed: UInt32 = 0x9E37_79B9
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brown: Float = 0

    func next() -> Float {
        // xorshift32 white noise in -1...1
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        let white = Float(seed) / Float(UInt32.max) * 2 - 1
        // about 0.5 s to reach the target volume, so starts and stops never click
        gain += (target - gain) * 0.0001
        let sample: Float
        switch color {
        case .white:
            sample = white * 0.25
        case .pink:
            // Paul Kellet's refined pink filter
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            sample = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11
            b6 = white * 0.115926
        case .brown:
            brown = (brown + 0.02 * white) / 1.02
            sample = brown * 3.5
        }
        return sample * gain
    }
}
