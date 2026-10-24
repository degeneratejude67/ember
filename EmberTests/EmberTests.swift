import AVFoundation
import XCTest
@testable import Ember

final class EmberTests: XCTestCase {
    func testInstantUsesTheMonotonicClock() {
        // the wall clock jumped an hour (clock change); the monotonic reading says 30 s
        let a = Instant(wall: Date(timeIntervalSince1970: 1_000), mono: 50)
        let b = Instant(wall: Date(timeIntervalSince1970: 4_630), mono: 80)
        XCTAssertEqual(a.seconds(to: b), 30, accuracy: 0.001)
        XCTAssertEqual(b.gap(a), 30, accuracy: 0.001)
    }

    func testInstantFallsBackToTheWallClockAfterAReboot() {
        let a = Instant(wall: Date(timeIntervalSince1970: 1_000), mono: 5_000)
        let b = Instant(wall: Date(timeIntervalSince1970: 1_600), mono: 20)
        XCTAssertEqual(a.seconds(to: b), 600, accuracy: 0.001)
    }

    func testEverySoundIsBundledAndShortEnoughForNotifications() throws {
        for effect in SoundEffect.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: effect.rawValue, withExtension: "wav"), effect.rawValue)
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0.03, effect.rawValue)
            XCTAssertLessThan(player.duration, 30, effect.rawValue)
        }
    }

    func testTicksClampToTheEightFiles() {
        XCTAssertEqual(SoundEffect.tick(-1), .tick1)
        XCTAssertEqual(SoundEffect.tick(3), .tick4)
        XCTAssertEqual(SoundEffect.tick(20), .tick8)
    }

    func testLabEventRoundTrip() throws {
        let event = LabEvent(at: Instant(wall: Date(timeIntervalSince1970: 1_700_000_000), mono: 12.5),
                             kind: "darwin.lockcomplete", detail: "+0.31 s")
        let back = try JSONDecoder.ember.decode([LabEvent].self, from: JSONEncoder.ember.encode([event]))
        XCTAssertEqual(back, [event])
    }

    func testFlameTiers() {
        XCTAssertEqual(FlameTier.forStreak(12, lit: false), .ash)
        XCTAssertEqual(FlameTier.forStreak(0, lit: true), .ash)
        XCTAssertEqual(FlameTier.forStreak(1, lit: true), .spark)
        XCTAssertEqual(FlameTier.forStreak(7, lit: true), .blaze)
        XCTAssertEqual(FlameTier.forStreak(30, lit: true), .blue)
        XCTAssertEqual(FlameTier.forStreak(365, lit: true), .plasma)
        for tier in FlameTier.allCases where tier != .ash {
            XCTAssertEqual(FlameTier.forStreak(tier.startsAt, lit: true), tier)
        }
    }

    func testTheFloatingTimerDrawsAFrame() throws {
        let frame = FloatingTimer.Frame(time: "18:42", caption: "IC Engines · CollaNote", tier: .glow, paused: false)
        let buffer = try XCTUnwrap(FloatingTimer.render(frame))
        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 480)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), 270)
        XCTAssertNotNil(FloatingTimer.sample(buffer))
    }
}
