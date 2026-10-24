import Foundation

/// Launch-time switches. The UI tests start the app with `-uitest`, so it keeps its files in a
/// throwaway folder and never asks for permissions.
enum AppEnv {
    static let arguments = ProcessInfo.processInfo.arguments
    static let isUITest = arguments.contains("-uitest")

    /// Where Ember keeps its files: Documents (visible in the Files app), or a temporary
    /// folder under UI tests.
    static let dataRoot: URL = {
        let fm = FileManager.default
        let root: URL
        if isUITest {
            root = fm.temporaryDirectory.appendingPathComponent("EmberUITest", isDirectory: true)
            if arguments.contains("-uitest-reset") { try? fm.removeItem(at: root) }
        } else {
            root = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }()

    /// The value that follows a flag, e.g. `-uitest-grace 3`.
    static func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    /// `-uitest-fast` turns preset minutes into seconds, so a Pomodoro takes 25 s.
    static let secondsPerMinute: Double = isUITest && arguments.contains("-uitest-fast") ? 1 : 60

    /// `-uitest-still` stops the flicker and jumps animations to their end, for steady screenshots.
    static let still = isUITest && arguments.contains("-uitest-still")
}

/// Reads the signing expiry from the provisioning profile embedded by the signer, so the
/// app can warn before a free Apple ID signature runs out. Nil on unsigned builds.
enum Provisioning {
    static let expiry: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)) else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }()

    static var daysLeft: Int? {
        guard let expiry else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }
}

extension JSONEncoder {
    /// ISO-8601 dates and sorted, pretty keys, so saved files and exports read the same.
    static var ember: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var ember: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
