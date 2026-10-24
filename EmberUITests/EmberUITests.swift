import XCTest

/// Drives Ember on the simulators. Screenshots go to SCREENSHOT_DIR (set by CI) and to the
/// test result.
final class EmberUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + extra
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    func testLabTour() {
        let app = launch(["-uitest-reset"])
        let lab = app.buttons["open-locklab"]
        XCTAssertTrue(lab.waitForExistence(timeout: 15))
        shot("01-home")

        app.buttons["open-sounds"].tap()
        XCTAssertTrue(app.navigationBars["Sound check"].waitForExistence(timeout: 5))
        shot("02-sound-check")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(lab.waitForExistence(timeout: 5))
        lab.tap()
        let verdict = app.staticTexts["lab-verdict"]
        XCTAssertTrue(verdict.waitForExistence(timeout: 5))
        shot("03-lock-lab")

        // Home and back after 3 s: Lock Lab should judge it a short absence (a slip).
        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        XCTAssertTrue(verdict.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label BEGINSWITH 'LEFT'"), evaluatedWith: verdict)
        waitForExpectations(timeout: 10)
        shot("04-lock-lab-after-home")
    }

    func testCompactTour() {
        let app = launch(["-uitest-reset"])
        XCTAssertTrue(app.buttons["open-locklab"].waitForExistence(timeout: 15))
        shot("compact-01-home")
        app.buttons["open-locklab"].tap()
        XCTAssertTrue(app.staticTexts["lab-verdict"].waitForExistence(timeout: 5))
        shot("compact-02-lock-lab")
    }
}
