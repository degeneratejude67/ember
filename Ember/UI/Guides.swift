import SwiftUI

/// One-time setup for Lock In: Guided Access pins the iPad to Ember until the passcode.
struct LockInGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GuideSteps(
                intro: "Lock In uses Guided Access, which is built into iPadOS. While it is on, the iPad stays on Ember: no Home, no app switcher, no notifications. Only the passcode gets you out.",
                steps: [
                    "Open Settings > Accessibility > Guided Access and turn it on.",
                    "Tap Passcode Settings > Set Guided Access Passcode. Best of all, ask a friend to type one you don't know.",
                    "In Passcode Settings, turn Touch ID off, so only the passcode ends it.",
                    "Back in Ember, choose Lock In and press Start, then triple-click the Home button and tap Start at the top right.",
                    "When the session is over, triple-click Home and enter the passcode.",
                ],
                footer: "Lock In blocks earn 1.5× XP for every locked minute. If Guided Access is turned off mid-block, the block carries on under Deep Focus.")
                .navigationTitle("Set up Lock In")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .preferredColorScheme(.dark)
    }
}

/// Optional: a Shortcuts automation that bounces him back to Ember from distracting apps
/// while a block runs.
struct FocusGuardGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GuideSteps(
                intro: "Focus Guard sends you straight back to Ember if you open YouTube, Instagram or a game during a block. Outside blocks those apps open normally. It takes two minutes in the Shortcuts app.",
                steps: [
                    "Open Shortcuts > Automation > + > App.",
                    "Choose YouTube, Instagram and any games. Keep \u{201C}Is Opened\u{201D}, choose \u{201C}Run Immediately\u{201D}, then Next.",
                    "Tap New Blank Automation and add the action \u{201C}Is Ember focusing?\u{201D} (search for Ember).",
                    "Add an \u{201C}If\u{201D} action: If \u{201C}Is Ember focusing?\u{201D} is true.",
                    "Inside the If, add \u{201C}Open App\u{201D} and choose Ember. Tap Done.",
                    "Optional: a second automation, App > Ember > Is Opened > Run Immediately > Set Focus (a Study focus that allows only Ember), silences everything else while you study.",
                ],
                footer: "Bouncing back takes a second or two, so it counts as a slip, not a failed block.")
                .navigationTitle("Focus Guard")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .preferredColorScheme(.dark)
    }
}

private struct GuideSteps: View {
    let intro: String
    let steps: [String]
    let footer: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(intro)
                    .font(.rounded(17, .medium))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.rounded(15, .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Theme.ember, in: Circle())
                        Text(step)
                            .font(.rounded(16, .regular))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(footer)
                    .font(.rounded(14, .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// Lock In's start: waits for Guided Access, then the block begins by itself.
struct ArmingView: View {
    let onStartWithout: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 20) {
                EmberMascot(mood: .focused, tier: .glow, animated: !AppEnv.still)
                    .frame(height: 150)
                Text("Lock in")
                    .font(.rounded(34, .heavy))
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("arming")
                Text("Triple-click the Home button, then tap Start at the top right. Your block begins the moment Guided Access is on.")
                    .font(.rounded(19, .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.gold)
                    .symbolEffect(.pulse)
                Button("Start without Guided Access", action: onStartWithout)
                    .buttonStyle(ChunkyButtonStyle(color: Theme.slate, lip: Theme.slateDeep, height: 52))
                    .frame(maxWidth: 380)
                Button("Cancel", action: onCancel)
                    .font(.rounded(16, .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(28)
            .frame(maxWidth: 560)
        }
    }
}
