import SwiftUI

/// Switches between Home, the focus screen and the break screen by the session's phase,
/// with the celebration or the unfinished screen on top when a block has just ended.
struct RootView: View {
    @ObservedObject private var controller = SessionController.shared
    @ObservedObject private var store = Store.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Group {
                if let session = controller.session {
                    if session.isFocusing {
                        FocusView(session: session)
                    } else {
                        BreakView(session: session)
                    }
                } else {
                    HomeView()
                }
            }
            if let summary = controller.celebration {
                CelebrationView(summary: summary)
                    .transition(.opacity)
            } else if let info = controller.unfinished {
                UnfinishedView(info: info)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: screenKey)
        .onAppear { Audio.shared.effectsOn = store.data.prefs.soundsOn }
        .onChange(of: store.data.prefs.soundsOn) { _, on in Audio.shared.effectsOn = on }
    }

    private var screenKey: String {
        if controller.celebration != nil { return "celebration" }
        if controller.unfinished != nil { return "unfinished" }
        return controller.session?.phase.rawValue ?? "home"
    }
}
