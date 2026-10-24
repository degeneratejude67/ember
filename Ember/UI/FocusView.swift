import SwiftUI

/// The running block: a large timer, the goal line, and as few controls as possible.
struct FocusView: View {
    let session: ActiveSession
    @ObservedObject private var store = Store.shared
    @ObservedObject private var controller = SessionController.shared
    @State private var starterBannerClosed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content(now: .now())
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
        let shownTime = countUp ? elapsed : (remaining ?? 0)
        // In fast UI-test mode a "minute" is one second; show it as minutes all the same.
        let clock = TimeText.clock(shownTime * 60 / spm)

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
            Spacer(minLength: 8)
            controls(s, countUp: countUp, paused: paused)
            footnote(s)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ s: ActiveSession) -> some View {
        let subject = store.data.subject(s.config.subjectID)
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
            Label(s.config.strictness.label, systemImage: s.config.strictness == .relaxed ? "leaf" : "flame.fill")
                .font(.rounded(13, .bold))
                .foregroundStyle(s.config.strictness == .relaxed ? Theme.teal : Theme.ember)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.card, in: Capsule())
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
        .accessibilityIdentifier("starter-banner")
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
        if s.config.strictness.polices {
            Text("Leaving Ember for more than \(Int(s.config.graceSeconds)) s ends the block. Locking the screen is fine.")
                .font(.rounded(13, .medium))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
    }
}
