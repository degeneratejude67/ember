import SwiftUI

/// Diagnostics for Deep Focus: shows how iPadOS reports leaving the app, locking the screen,
/// Control Center and Guided Access on this iPad, and judges each absence.
struct LockLabView: View {
    @ObservedObject private var detector = LockDetector.shared
    @ObservedObject private var log = LabLog.shared
    @State private var showSteps = true

    private static let steps = [
        "Turn on \u{201C}Nudge test\u{201D} and allow notifications.",
        "Press Home. Wait 5 seconds. Open Ember again.",
        "Press the top button to lock the iPad. Wait 15 seconds. Unlock with Touch ID.",
        "Pull down Control Center, then close it.",
        "Pull down Notification Center, then close it.",
        "Double-press Home for the app switcher, then tap Ember.",
        "Drag Slate from the Dock beside Ember (Split View), use it for 5 seconds, then close it.",
        "Press Home. Wait 20 seconds. Open Ember again.",
        "If Guided Access is set up: triple-click Home, start it, then end it.",
        "Tell Claude you're done. The log is in Files > On My iPad > Ember > locklab.json.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Last absence")
                            .font(.rounded(14, .semibold))
                            .foregroundStyle(Theme.dim)
                        Text(detector.lastVerdict)
                            .font(.rounded(20, .bold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("lab-verdict")
                        HStack(spacing: 16) {
                            Label(detector.guidedAccess ? "Guided Access on" : "Guided Access off",
                                  systemImage: detector.guidedAccess ? "lock.fill" : "lock.open")
                            Label("\(log.events.count) events", systemImage: "list.bullet")
                        }
                        .font(.rounded(14, .medium))
                        .foregroundStyle(Theme.dim)
                    }
                }

                Card {
                    Toggle(isOn: $detector.nudgeArmed) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nudge test").font(.rounded(17, .semibold))
                            Text("A notification 3 s after you leave, cancelled if you locked the screen.")
                                .font(.rounded(13, .regular))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .tint(Theme.ember)
                    .onChange(of: detector.nudgeArmed) { _, armed in
                        if armed { detector.requestNotifications() }
                    }
                }

                Card {
                    DisclosureGroup(isExpanded: $showSteps) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.rounded(14, .heavy))
                                        .foregroundStyle(Theme.ember)
                                        .frame(width: 20, alignment: .trailing)
                                    Text(step)
                                        .font(.rounded(15, .regular))
                                        .foregroundStyle(Theme.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("The 2-minute test").font(.rounded(17, .semibold)).foregroundStyle(Theme.text)
                    }
                    .tint(Theme.dim)
                }

                Text("Log, newest first")
                    .font(.rounded(14, .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.leading, 4)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(log.events.reversed()) { event in
                        LabRow(event: event)
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Lock Lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: log.text) { Image(systemName: "square.and.arrow.up") }
                Button(role: .destructive) { log.clear() } label: { Image(systemName: "trash") }
                    .accessibilityIdentifier("lab-clear")
            }
        }
    }
}

private struct LabRow: View {
    let event: LabEvent

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var color: Color {
        if event.kind == "verdict" { return Theme.gold }
        if event.kind.hasPrefix("darwin") || event.kind.hasPrefix("protected") { return Theme.ice }
        if event.kind.hasPrefix("nudge") { return Theme.ember }
        return Theme.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(Self.time.string(from: event.at.wall))
                    .foregroundStyle(Theme.dim)
                Text(event.kind)
                    .foregroundStyle(color)
                    .fontWeight(.semibold)
            }
            if !event.detail.isEmpty {
                Text(event.detail)
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 13, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
