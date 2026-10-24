import SwiftUI

/// The break countdown, then the ready screen that starts the next round.
struct BreakView: View {
    let session: ActiveSession
    @ObservedObject private var store = Store.shared
    @ObservedObject private var controller = SessionController.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ZStack {
                LinearGradient(colors: [Theme.teal.opacity(0.16), Theme.bg], startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        if session.phase == .ready { ready } else { running(now: .now()) }
                        if !session.parking.isEmpty { parkingList }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var tier: FlameTier { Today(store.data).tier }

    private func running(now: Instant) -> some View {
        let remaining = SessionEngine.breakRemaining(session, at: now) * 60 / session.config.secondsPerMinute
        return VStack(spacing: 16) {
            EmberMascot(mood: .sleepy, tier: tier, animated: !AppEnv.still)
                .frame(height: 120)
            Text(isLongBreak ? "Long break" : "Break")
                .font(.rounded(20, .bold))
                .foregroundStyle(Theme.teal)
            Text(TimeText.clock(remaining))
                .font(.rounded(96, .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityIdentifier("break-time")
            Text("Stand up, drink water, walk. iPad down.")
                .font(.rounded(20, .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text("Stay off the iPad until the chime for a clean break: +\(Rewards.cleanBreakBonus) XP.")
                .font(.rounded(14, .medium))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Button("+2 min") { controller.send(.extendBreak) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.teal, lip: Theme.tealDeep, height: 50))
                    .accessibilityIdentifier("extend-break")
                Button("Skip break") { controller.send(.skipBreak) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.slate, lip: Theme.slateDeep, height: 50))
                    .accessibilityIdentifier("skip-break")
            }
            .frame(maxWidth: 420)
            .padding(.top, 6)
            menuButton
        }
    }

    private var ready: some View {
        VStack(spacing: 16) {
            EmberMascot(mood: .focused, tier: tier, animated: !AppEnv.still)
                .frame(height: 140)
            Text("Break's over")
                .font(.rounded(34, .heavy))
                .foregroundStyle(Theme.text)
            Text(nextRoundText)
                .font(.rounded(18, .semibold))
                .foregroundStyle(Theme.dim)
            Button("Start round \(session.round + 1)") { controller.send(.startNextRound) }
                .buttonStyle(ChunkyButtonStyle(height: 62))
                .frame(maxWidth: 420)
                .accessibilityIdentifier("next-round")
            menuButton
            Button("End session") { controller.send(.stop) }
                .font(.rounded(16, .semibold))
                .foregroundStyle(Theme.dim)
                .accessibilityIdentifier("end-session")
        }
    }

    /// A free break: off the timer, back to Home, with Continue waiting there.
    private var menuButton: some View {
        Button {
            controller.breakToMenu()
        } label: {
            Label("Break to menu, continue later", systemImage: "house.fill")
                .font(.rounded(16, .semibold))
                .foregroundStyle(Theme.teal)
        }
        .accessibilityIdentifier("break-to-menu")
    }

    private var parkingList: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Parked while you focused", systemImage: "tray.full")
                    .font(.rounded(15, .bold))
                    .foregroundStyle(Theme.text)
                ForEach(Array(session.parking.enumerated()), id: \.offset) { _, item in
                    Text("• \(item)")
                        .font(.rounded(15, .regular))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: 480)
    }

    private var isLongBreak: Bool {
        let preset = session.config.preset
        return session.kind == .cycle && preset.longEvery > 0 && session.round % preset.longEvery == 0
    }

    private var nextRoundText: String {
        let preset = session.config.preset
        let minutes = session.kind == .cycle ? "\(preset.focusMinutes) minutes" : "another block"
        return "Round \(session.round + 1): \(minutes) of \(preset.name)."
    }
}
