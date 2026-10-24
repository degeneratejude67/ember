import Foundation

/// A moment in time: the wall clock plus a monotonic reading. The monotonic clock keeps
/// counting while the iPad sleeps and ignores changes to the device clock; it restarts at
/// a reboot.
struct Instant: Codable, Equatable {
    var wall: Date
    var mono: Double

    static func now() -> Instant {
        Instant(wall: Date(), mono: Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000)
    }

    /// Seconds from `self` to `later`. Uses the monotonic clock while it runs forward, and the
    /// wall clock after a reboot reset it.
    func seconds(to later: Instant) -> Double {
        later.mono >= mono ? later.mono - mono : max(0, later.wall.timeIntervalSince(wall))
    }

    /// Distance between two instants, whichever comes first.
    func gap(_ other: Instant) -> Double {
        other.mono >= mono ? seconds(to: other) : other.seconds(to: self)
    }
}
