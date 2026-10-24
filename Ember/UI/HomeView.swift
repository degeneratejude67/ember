import SwiftUI

/// M0 home: the mascot and the two test screens. The real Home replaces this in M1.
struct HomeView: View {
    @State private var mood: Mood = .calm

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    EmberMascot(mood: mood, tier: .glow, animated: !AppEnv.isUITest)
                        .frame(height: 220)
                        .padding(.top, 24)
                        .onTapGesture {
                            mood = Mood.allCases[(Mood.allCases.firstIndex(of: mood)! + 1) % Mood.allCases.count]
                        }
                    VStack(spacing: 6) {
                        Text("Ember")
                            .font(.rounded(44, .heavy))
                            .foregroundStyle(Theme.text)
                        Text("Lock Lab build")
                            .font(.rounded(17, .semibold))
                            .foregroundStyle(Theme.dim)
                    }
                    if let days = Provisioning.daysLeft {
                        Text("Signature: \(days) day\(days == 1 ? "" : "s") left")
                            .font(.rounded(14, .semibold))
                            .foregroundStyle(days <= 2 ? Theme.danger : Theme.dim)
                    }
                    VStack(spacing: 14) {
                        NavigationLink { LockLabView() } label: { Text("Lock Lab") }
                            .buttonStyle(ChunkyButtonStyle())
                            .accessibilityIdentifier("open-locklab")
                        NavigationLink { SoundCheckView() } label: { Text("Sound check") }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.slate, lip: Theme.slateDeep))
                            .accessibilityIdentifier("open-sounds")
                    }
                    .padding(.top, 12)
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
        }
    }
}
