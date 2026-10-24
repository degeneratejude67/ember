import SwiftUI

/// The running block: a large timer, the goal line, and as few controls as possible.
/// After 30 s without a touch a dim overlay leaves only the time.
struct FocusView: View {
    let session: ActiveSession
    @ObservedObject private var store = Store.shared
    @ObservedObject private var controller = SessionController.shared
    @ObservedObject private var detector = LockDetector.shared
    @ObservedObject private var audio = Audio.shared
    @State private var starterBannerClosed = false
    @State private var parkingOpen = false
    @State private var parkingText = ""
    @State private var lastTouch = Date()

    private static let dimAfter = 30.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let dimmed = !AppEnv.isUITest && context.date.timeIntervalSince(lastTouch) > Self.dimAfter
                || AppEnv.value(after: "-uitest-screen") == "dimmed"
            ZStack {
                content(now: .now())
                if dimmed {
                    dimOverlay(now: .now())
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: dimmed)
        }
        .simultaneousGesture(TapGesture().onEnded { lastTouch = Date() })
        .alert("Park a thought", isPresented: $parkingOpen) {
            TextField("It will wait for your break", text: $parkingText)
                .accessibilityIdentifier("parking-field")
            Button("Park it") {
                controller.send(.addParking(parkingText))
                parkingText = ""
            }
            Button("Cancel", role: .cancel) { parkingText = "" }
        } message: {
            Text("Write it down so it stops pulling at you. You'll see it at the break.")
        }
    }

    private func content(now: Instant) -> some View {
        let s = session
        let spm = s.config.secondsPerMinute
        let elapsed = SessionEngine.focusElapsed(s, at: now)
        let remaining = SessionEngine.remaining(s, at: now)
        let countUp = s.plannedSeconds == nil
        let hour = 60 * spm
        let fraction = countUp ? elapsed.truncatingRemainder(dividingBy: hour) / hour
                               : (remaining ?? 0) / max(1, s.plannedSeconds ?? 1)
        let style = store.data.prefs.timerStyle
        let paused = s.phase == .paused
        let clock = clockText(now)

        return VStack(spacing: 18) {
            header(s)
            Spacer(minLength: 8)
            TimerFace(style: style, fraction: fraction, color: paused ? Theme.dim : Theme.ember)
                .frame(maxWidth: style == .digits ? 0 : 440, maxHeight: style == .digits ? 0 : 440)
                .overlay {
                    if style == .ring { timeText(clock, size: 76) }
                }
                .accessibilityHidden(true)
            if style != .ring {
                timeText(clock, size: style == .digits ? 120 : 64)
            }
            if !s.config.intent.isEmpty {
                Text("\u{201C}\(s.config.intent)\u{201D}")
                    .font(.rounded(20, .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("focus-intent")
            }
            if paused, let pausedAt = s.pausedAt {
                pausedNote(pausedAt: pausedAt, now: now)
            }
            if s.starterConverted && !starterBannerClosed {
                starterBanner
            }
            if let app = StudyApp.find(s.config.studyAppID) {
                studyBanner(app)
            }
            Spacer(minLength: 8)
            tools(s)
            controls(s, countUp: countUp, paused: paused)
            footnote(s)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clockText(_ now: Instant) -> String {
        let shown = session.plannedSeconds == nil
            ? SessionEngine.focusElapsed(session, at: now)
            : (SessionEngine.remaining(session, at: now) ?? 0)
        // In fast UI-test mode a "minute" is one second; show it as minutes all the same.
        return TimeText.clock(shown * 60 / session.config.secondsPerMinute)
    }

    private func header(_ s: ActiveSession) -> some View {
        let subject = store.data.subject(s.config.subjectID)
        let locked = s.config.strictness == .lockIn && detector.guidedAccess
        return HStack(spacing: 10) {
            if let subject {
                Circle().fill(SubjectPalette.color(subject.colorIndex)).frame(width: 10, height: 10)
                Text(subject.name).font(.rounded(16, .bold)).foregroundStyle(Theme.text).lineLimit(1)
            }
            Text(roundText(s))
                .font(.rounded(15, .semibold))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            Spacer(minLength: 0)
            if s.slips > 0 {
                Text(s.slips == 1 ? "1 slip" : "\(s.slips) slips")
                    .font(.rounded(13, .bold))
                    .foregroundStyle(Theme.gold)
                    .accessibilityIdentifier("slips")
            }
            Label(locked ? "Locked in" : s.config.strictness.label,
                  systemImage: locked ? "lock.fill" : s.config.strictness == .relaxed ? "leaf" : "flame.fill")
                .font(.rounded(13, .bold))
                .foregroundStyle(s.config.strictness == .relaxed ? Theme.teal : locked ? Theme.gold : Theme.ember)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.card, in: Capsule())
                .accessibilityIdentifier("mode-badge")
        }
    }

    private func roundText(_ s: ActiveSession) -> String {
        let preset = s.config.preset
        switch s.kind {
        case .cycle:
            if preset.longEvery > 0 {
                return "\(preset.name) · round \((s.round - 1) % preset.longEvery + 1) of \(preset.longEvery)"
            }
            return s.round > 1 ? "\(preset.name) · round \(s.round)" : preset.name
        case .flow: return s.starterConverted ? "Flowtime (from 5 minutes)" : "Flowtime"
        case .exam: return "Mock exam"
        case .starter: return "Just 5 minutes"
        }
    }

    private func timeText(_ clock: String, size: CGFloat) -> some View {
        Text(clock)
            .font(.rounded(size, .heavy))
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            .contentTransition(.numericText(countsDown: session.plannedSeconds != nil))
            .accessibilityIdentifier("focus-time")
    }

    private func pausedNote(pausedAt: Instant, now: Instant) -> some View {
        let text: String
        if session.config.strictness == .relaxed {
            text = "Paused"
        } else {
            let left = SessionEngine.pauseLimit - pausedAt.seconds(to: now)
            text = "Paused · carries on by itself in \(TimeText.clock(left))"
        }
        return Text(text)
            .font(.rounded(16, .bold))
            .foregroundStyle(Theme.gold)
            .accessibilityIdentifier("paused-note")
    }

    private var starterBanner: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("5 minutes done! The hardest part is over.")
                    .font(.rounded(17, .bold))
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("starter-banner")
                Text("It carries on as Flowtime. Finish whenever your focus drops; the break will be a fifth of your time.")
                    .font(.rounded(14, .regular))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Keep going") { starterBannerClosed = true }
                        .buttonStyle(ChunkyButtonStyle(height: 46))
                        .accessibilityIdentifier("keep-going")
                    Button("Finish") { controller.send(.finish) }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.slate, lip: Theme.slateDeep, height: 46))
                }
            }
        }
        .frame(maxWidth: 480)
    }

    /// Studying in another app: how to get back there, and what still counts.
    private func studyBanner(_ app: StudyApp) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Studying in \(app.name)", systemImage: app.icon)
                    .font(.rounded(17, .bold))
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("study-banner")
                Text(controller.studyHint ?? "Time in \(app.name) counts as focus. With Focus Guard set up, opening YouTube or a game sends you straight back here.")
                    .font(.rounded(14, .regular))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if FloatingTimer.isSupported {
                    HStack(spacing: 12) {
                        FloatingTimerPreview()
                            .frame(width: 160, height: 90)
                        Text("This mini timer floats over \(app.name) when you switch. Drag it anywhere, or tuck it into the side of the screen.")
                            .font(.rounded(13, .medium))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if app.url != nil {
                    Button("Back to \(app.name)") { controller.openStudyApp() }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.teal, lip: Theme.tealDeep, height: 46))
                        .accessibilityIdentifier("open-study-app")
                }
            }
        }
        .frame(maxWidth: 480)
    }

    /// Parking lot and focus noise.
    private func tools(_ s: ActiveSession) -> some View {
        HStack(spacing: 12) {
            Button {
                parkingOpen = true
            } label: {
                Label(s.parking.isEmpty ? "Park a thought" : "Parked: \(s.parking.count)", systemImage: "tray.and.arrow.down.fill")
            }
            .accessibilityIdentifier("park")
            Button {
                cycleNoise()
            } label: {
                Label(audio.noise.map { "\($0.label) noise" } ?? "Noise off",
                      systemImage: audio.noise == nil ? "speaker.slash.fill" : "waveform")
            }
            .accessibilityIdentifier("noise")
        }
        .font(.rounded(15, .semibold))
        .foregroundStyle(Theme.text)
        .buttonStyle(.bordered)
        .tint(Theme.cardHigh)
    }

    private func cycleNoise() {
        let order: [NoiseColor?] = [nil, .brown, .pink, .white]
        let i = order.firstIndex(of: store.data.prefs.noise) ?? 0
        store.data.prefs.noise = order[(i + 1) % order.count]
        controller.syncNoise()
    }

    private func controls(_ s: ActiveSession, countUp: Bool, paused: Bool) -> some View {
        HStack(spacing: 14) {
            if paused {
                Button("Resume") { controller.send(.resume) }
                    .buttonStyle(ChunkyButtonStyle(height: 50))
                    .frame(maxWidth: 200)
                    .accessibilityIdentifier("resume")
            } else if SessionEngine.canPause(s) {
                Button(s.config.strictness == .relaxed ? "Pause" : "Pause 2 min") { controller.send(.pause) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.slate, lip: Theme.slateDeep, height: 50))
                    .frame(maxWidth: 200)
                    .accessibilityIdentifier("pause")
            }
            Spacer(minLength: 0)
            if countUp {
                Button("Finish") { controller.send(.finish) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.teal, lip: Theme.tealDeep, height: 50))
                    .frame(maxWidth: 200)
                    .accessibilityIdentifier("finish")
            }
            HoldButton(title: "Hold to give up") { controller.send(.giveUp) }
                .accessibilityIdentifier("give-up")
        }
    }

    @ViewBuilder private func footnote(_ s: ActiveSession) -> some View {
        if s.config.strictness.polices && !s.config.studiesElsewhere {
            Text(s.config.checksIn
                 ? "You can leave Ember for up to \(Int(s.config.graceSeconds / 60)) min; then it checks in. Locking the screen is fine."
                 : "Leaving Ember for more than \(Int(s.config.graceSeconds)) s ends the block. Locking the screen is fine.")
                .font(.rounded(13, .medium))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
    }

    /// Only the time, dim, so the screen doesn't pull at him while he studies.
    private func dimOverlay(now: Instant) -> some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(clockText(now))
                    .font(.rounded(96, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ember.opacity(0.55))
                Text("Tap to wake")
                    .font(.rounded(14, .semibold))
                    .foregroundStyle(Theme.dim.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { lastTouch = Date() }
        .accessibilityIdentifier("dimmed")
    }
}
