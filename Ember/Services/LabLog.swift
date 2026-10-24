import Foundation

/// One line in the Lock Lab log.
struct LabEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var at: Instant
    var kind: String
    var detail = ""
}

/// The Lock Lab log: the last 300 events, saved to locklab.json in Documents so it can be
/// opened in the Files app or pulled over USB.
final class LabLog: ObservableObject {
    static let shared = LabLog()
    static let limit = 300

    @Published private(set) var events: [LabEvent] = []
    private let url = AppEnv.dataRoot.appendingPathComponent("locklab.json")

    private init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder.ember.decode([LabEvent].self, from: data) {
            events = saved
        }
    }

    /// Records an event now. Safe to call from any thread; the time is taken at the call.
    func add(_ kind: String, _ detail: String = "") {
        let event = LabEvent(at: .now(), kind: kind, detail: detail)
        if Thread.isMainThread {
            append(event)
        } else {
            DispatchQueue.main.async { self.append(event) }
        }
    }

    func clear() {
        events = []
        save()
    }

    private func append(_ event: LabEvent) {
        events.append(event)
        if events.count > Self.limit { events.removeFirst(events.count - Self.limit) }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder.ember.encode(events) else { return }
        // Must still be writable while the screen is locked.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The log as plain text, oldest first, with the gap to the previous line.
    var text: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        var lines: [String] = []
        var previous: Instant?
        for event in events {
            let delta = previous.map { String(format: "+%.2f", $0.seconds(to: event.at)) } ?? ""
            let wall = formatter.string(from: event.at.wall)
            lines.append("\(wall) \(String(format: "%9.3f", event.at.mono)) \(delta.padding(toLength: 8, withPad: " ", startingAt: 0)) \(event.kind) \(event.detail)")
            previous = event.at
        }
        return lines.joined(separator: "\n")
    }
}
