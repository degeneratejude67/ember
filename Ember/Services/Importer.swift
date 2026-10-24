import Foundation

/// Merges course files dropped into Documents/Import (over USB, or with the Files app):
/// subjects, their topics and past papers. A course matches an existing subject by its code
/// ("ME 417") or its name; topics and papers already there are left alone. Each file moves
/// to Import/Done once read, so it is merged only once.
///
/// File format:
/// {"courses": [{"name": "ME 417 · IC Engines", "code": "ME 417",
///               "topics": [{"title": "...", "group": "Anup Sir", "asked": 41}],
///               "papers": ["2023-24", "2022-23"]}]}
enum Importer {
    struct File: Decodable {
        let courses: [Course]
    }

    struct Course: Decodable {
        let name: String
        let code: String?
        let topics: [TopicLine]?
        let papers: [String]?
    }

    struct TopicLine: Decodable {
        let title: String
        let group: String?
        let asked: Int?
        let slides: Int?
        let sections: [TopicSection]?
    }

    /// Share of a course's topics, by past-paper questions, marked high-yield.
    static let highYieldShare = 0.3

    /// Reads and merges every file waiting in Documents/Import; returns how many courses changed.
    @discardableResult
    static func run(into data: inout AppData, root: URL = AppEnv.dataRoot) -> Int {
        let fm = FileManager.default
        let folder = root.appendingPathComponent("Import", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return 0 }
        var changed = 0
        for file in files where file.pathExtension.lowercased() == "json" {
            guard let raw = try? Data(contentsOf: file), let parsed = try? JSONDecoder().decode(File.self, from: raw) else { continue }
            changed += merge(parsed, into: &data)
            let done = folder.appendingPathComponent("Done", isDirectory: true)
            try? fm.createDirectory(at: done, withIntermediateDirectories: true)
            try? fm.removeItem(at: done.appendingPathComponent(file.lastPathComponent))
            try? fm.moveItem(at: file, to: done.appendingPathComponent(file.lastPathComponent))
        }
        return changed
    }

    static func merge(_ file: File, into data: inout AppData) -> Int {
        var changed = 0
        for course in file.courses {
            let subjectID = subject(for: course, in: &data)
            var touched = false
            let existing = Set(data.topics.filter { $0.subjectID == subjectID }.map { $0.title.lowercased() })
            var order = (data.topics.filter { $0.subjectID == subjectID }.map(\.order).max() ?? -1) + 1
            let counts = (course.topics ?? []).compactMap(\.asked).sorted(by: >)
            let cutoffIndex = max(0, Int((Double(counts.count) * highYieldShare).rounded(.up)) - 1)
            let cutoff = counts.isEmpty ? Int.max : max(1, counts[min(cutoffIndex, counts.count - 1)])
            for line in course.topics ?? [] where !existing.contains(line.title.lowercased()) {
                data.topics.append(Topic(subjectID: subjectID, title: line.title, group: line.group, order: order,
                                         asked: line.asked, starred: (line.asked ?? 0) >= cutoff,
                                         slides: line.slides, sections: line.sections ?? []))
                order += 1
                touched = true
            }
            let sessions = Set(data.papers.filter { $0.subjectID == subjectID }.map(\.session))
            for session in course.papers ?? [] where !sessions.contains(session) {
                data.papers.append(PastPaper(subjectID: subjectID, session: session))
                touched = true
            }
            if touched { changed += 1 }
        }
        return changed
    }

    /// The subject a course belongs to: same code or same name, or a new one.
    private static func subject(for course: Course, in data: inout AppData) -> UUID {
        let code = course.code?.lowercased().replacingOccurrences(of: " ", with: "")
        if let match = data.subjects.first(where: { subject in
            let name = subject.name.lowercased()
            if name == course.name.lowercased() { return true }
            guard let code, !code.isEmpty else { return false }
            return name.replacingOccurrences(of: " ", with: "").contains(code)
        }) {
            if let i = data.subjects.firstIndex(where: { $0.id == match.id }), data.subjects[i].archived {
                data.subjects[i].archived = false
            }
            return match.id
        }
        let subject = StudySubject(name: course.name, colorIndex: data.subjects.count)
        data.subjects.append(subject)
        return subject.id
    }
}
