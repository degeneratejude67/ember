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

/// App detection: Shortcuts automations tell Ember which app he opened, since iPadOS won't.
struct FocusGuardGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GuideSteps(
                intro: "iPadOS doesn't tell Ember which app you're in, but Shortcuts can. With these three automations, time in CollaNote counts with no limit, Safari, YouTube, Gemini or Claude get 10 minutes, and any other app 3 minutes. Then Ember asks \u{201C}Still studying?\u{201D}, and the block ends only if you don't answer within a minute. In every automation choose \u{201C}Run Immediately\u{201D} and turn off \u{201C}Notify When Run\u{201D}.",
                steps: [
                    "Study app: Shortcuts > Automation > + > App. Choose CollaNote (and Slate, Files), keep \u{201C}Is Opened\u{201D}, Run Immediately, Next. New Blank Automation, add \u{201C}Ember: in my study app\u{201D}.",
                    "Leaving it: + > App. Choose CollaNote (and Slate, Files) again, tick \u{201C}Is Closed\u{201D} and untick \u{201C}Is Opened\u{201D}. Add \u{201C}Ember: in another app\u{201D}.",
                    "Helper apps: + > App. Choose Safari, YouTube, Gemini, Claude, ChatGPT, keep \u{201C}Is Opened\u{201D}. Add \u{201C}Ember: in a helper app\u{201D}.",
                    "Optional, to catch the rest: + > App. Choose the apps you drift to (Instagram, WhatsApp, games), keep \u{201C}Is Opened\u{201D}. Add \u{201C}Ember: in another app\u{201D}.",
                    "Optional: + > App > Ember > Is Opened > Set Focus (a Study focus that allows only Ember and your study apps) silences everything else.",
                ],
                footer: "Without these, Ember treats time away as time in your study app when you study in one, and as \u{201C}another app\u{201D} (3 minutes) when you study in Ember only.")
                .navigationTitle("App detection")
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
                    .symbolEffect(.pulse, isActive: !AppEnv.isUITest)
                Button("Start without Guided Access", action: onStartWithout)
                    .buttonStyle(ChunkyButtonStyle(color: Theme.slate, lip: Theme.slateDeep, height: 52))
                    .frame(maxWidth: 380)
                    .accessibilityIdentifier("arming-skip")
                Button("Cancel", action: onCancel)
                    .font(.rounded(16, .semibold))
                    .foregroundStyle(Theme.dim)
                    .accessibilityIdentifier("arming-cancel")
            }
            .padding(28)
            .frame(maxWidth: 560)
        }
    }
}
