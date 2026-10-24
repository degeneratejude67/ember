import Foundation

/// Loads and saves ember.json in Documents (visible in the Files app), keeps a backup per day
/// for a week, and never overwrites a file it could not read.
final class Store: ObservableObject {
    static let shared = Store(root: AppEnv.dataRoot, seed: AppEnv.isUITest ? Fixtures.seed : nil)

    @Published var data: AppData {
        didSet { scheduleSave() }
    }
    /// Something the user should know about the data file, shown as a banner.
    @Published var notice: String?

    let root: URL
    private var pending: DispatchWorkItem?
    private var lastBackupDay: String?

    private var fileURL: URL { root.appendingPathComponent("ember.json") }
    private var backupDir: URL { root.appendingPathComponent("Backups", isDirectory: true) }

    init(root: URL, seed: (() -> AppData?)? = nil) {
        self.root = root
        if let seeded = seed?() {
            data = seeded
            notice = nil
        } else {
            let (loaded, notice) = Store.load(from: root)
            data = loaded
            self.notice = notice
        }
    }

    static func load(from root: URL) -> (AppData, String?) {
        let fm = FileManager.default
        let file = root.appendingPathComponent("ember.json")
        guard fm.fileExists(atPath: file.path) else { return (AppData(), nil) }
        do {
            return (try JSONDecoder.ember.decode(AppData.self, from: Data(contentsOf: file)), nil)
        } catch {
            let stamp = stampFormatter("yyyyMMdd-HHmmss").string(from: Date())
            let kept = "ember.corrupt-\(stamp).json"
            try? fm.moveItem(at: file, to: root.appendingPathComponent(kept))
            if let backup = newestBackup(in: root),
               let raw = try? Data(contentsOf: backup),
               let data = try? JSONDecoder.ember.decode(AppData.self, from: raw) {
                return (data, "Ember couldn't read its data file, so it loaded the backup \(backup.lastPathComponent). The unreadable file was kept as \(kept).")
            }
            return (AppData(), "Ember couldn't read its data file. It was kept as \(kept).")
        }
    }

    func saveNow() {
        pending?.cancel()
        pending = nil
        write()
    }

    /// A copy of the data for sharing, as Ember-<date>.json in the temporary folder.
    func exportFile() -> URL? {
        guard let raw = try? JSONEncoder.ember.encode(data) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ember-\(Self.stampFormatter("yyyy-MM-dd").string(from: Date())).json")
        return (try? raw.write(to: url, options: .atomic)) == nil ? nil : url
    }

    private func scheduleSave() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.write() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func write() {
        guard let raw = try? JSONEncoder.ember.encode(data) else { return }
        backupIfNeeded()
        // Must still be writable while the screen is locked.
        try? raw.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Before the first save of each day, copies the current file to Backups/ember-yyyyMMdd.json
    /// and keeps the newest 7.
    private func backupIfNeeded() {
        let day = Self.stampFormatter("yyyyMMdd").string(from: Date())
        guard lastBackupDay != day else { return }
        lastBackupDay = day
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let target = backupDir.appendingPathComponent("ember-\(day).json")
        if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: fileURL, to: target) }
        for old in Self.backups(in: root).dropFirst(7) { try? fm.removeItem(at: old) }
    }

    /// Backups, newest first.
    static func backups(in root: URL) -> [URL] {
        let dir = root.appendingPathComponent("Backups", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("ember-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func newestBackup(in root: URL) -> URL? { backups(in: root).first }

    static func stampFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
