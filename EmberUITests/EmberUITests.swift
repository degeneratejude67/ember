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

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 10, _ message: String = "") -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message.isEmpty ? "\(element) missing" : message)
        return element
    }

    /// "12:34" or "1:02:03" in seconds.
    private func seconds(_ clock: String) -> Int {
        clock.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }

    // MARK: - Flows

    /// A whole Pomodoro round in fast mode (a minute is a second): Home, technique sheet,
    /// focus, celebration, break, round 2, then giving up.
    func testFastPomodoroRound() {
        let app = launch(["-uitest-reset", "-uitest-seed", "-uitest-fast"])
        wait(app.buttons["start"], 15)
        shot("01-home")

        app.buttons["technique-chip"].tap()
        wait(app.buttons["preset-pomodoro"], 5)
        shot("02-technique-sheet")
        app.buttons["preset-pomodoro"].tap()
        app.buttons["Done"].tap()

        let intent = app.textFields["intent-field"]
        intent.tap()
        // Return starts the block (the keyboard could cover the Start button).
        intent.typeText("Past paper 2019, Q3\n")
        wait(element(app, "focus-time"), 5)
        sleep(2)
        shot("03-focus")

        wait(app.buttons["continue"], 45, "the 25-second block never finished")
        sleep(1)
        shot("04-celebration")
        app.buttons["continue"].tap()
        // The first block of the day extends the seeded 12-day streak.
        wait(element(app, "streak-number"), 5, "no streak screen after the first block of the day")
        let continueButton = app.buttons["continue"]
        let lit = NSPredicate(format: "isEnabled == true")
        expectation(for: lit, evaluatedWith: continueButton)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(element(app, "streak-number").label, "13")
        shot("04b-streak")
        continueButton.tap()

        wait(element(app, "next-round"), 20, "the break never ended")
        shot("05-ready")
        app.buttons["next-round"].tap()
        let giveUp = element(app, "give-up")
        wait(giveUp, 5)
        giveUp.press(forDuration: 3.6)
        wait(app.staticTexts["Block unfinished"], 5)
        shot("06-unfinished-after-giving-up")
        app.buttons["tag-YouTube"].tap()
        wait(app.buttons["start"], 5)
    }

    /// Deep Focus: Home and back inside the grace time is a slip; staying away longer ends the block.
    func testLeavingTheApp() {
        let app = launch(["-uitest-reset", "-uitest-seed", "-uitest-grace", "4"])
        wait(app.buttons["start"], 15)
        app.buttons["start"].tap()
        wait(element(app, "focus-time"), 5)

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        let slips = wait(app.staticTexts["slips"], 10)
        XCTAssertEqual(slips.label, "1 slip")
        shot("10-focus-after-a-slip")

        XCUIDevice.shared.press(.home)
        sleep(8)
        app.activate()
        wait(app.staticTexts["Block unfinished"], 10, "staying away 8 s with a 4 s grace should end the block")
        shot("11-unfinished-after-leaving")
    }

    /// The running block survives the app being killed and relaunched.
    func testRelaunchKeepsTheBlock() {
        var app = launch(["-uitest-reset", "-uitest-seed"])
        wait(app.buttons["start"], 15)
        app.buttons["start"].tap()
        let before = seconds(wait(element(app, "focus-time"), 5).label)
        app.terminate()
        app = launch(["-uitest-seed"])
        let after = seconds(wait(element(app, "focus-time"), 15, "the block did not come back after relaunch").label)
        XCTAssertLessThanOrEqual(after, before)
        XCTAssertGreaterThan(after, before - 30)
    }

    /// "Just 5 minutes" turns into Flowtime after five (fast) minutes.
    func testJustFiveMinutes() {
        let app = launch(["-uitest-reset", "-uitest-seed", "-uitest-fast"])
        wait(app.buttons["starter"], 15)
        app.buttons["starter"].tap()
        wait(element(app, "starter-banner"), 15, "Just 5 minutes did not turn into Flowtime")
        shot("12-just-five-minutes-done")
        app.buttons["keep-going"].tap()
        wait(app.buttons["finish"], 5)
    }

    /// The parking lot keeps a thought for the break; the noise button cycles colours.
    func testParkingLotAndNoise() {
        let app = launch(["-uitest-reset", "-uitest-seed"])
        wait(app.buttons["start"], 15)
        app.buttons["start"].tap()
        wait(app.buttons["park"], 5).tap()
        let field = app.alerts.textFields.firstMatch
        wait(field, 5).tap()
        field.typeText("Reply to Nabil about the lab group")
        app.alerts.buttons["Park it"].tap()
        XCTAssertTrue(app.buttons["park"].label.contains("1"), app.buttons["park"].label)
        app.buttons["noise"].tap()
        XCTAssertTrue(app.buttons["noise"].label.contains("Brown"), app.buttons["noise"].label)
        shot("13-focus-parked-and-noise")
        app.buttons["noise"].tap()
        app.buttons["noise"].tap()
        app.buttons["noise"].tap()
        XCTAssertTrue(app.buttons["noise"].label.contains("off"), app.buttons["noise"].label)
    }

    /// Lock In waits for Guided Access (which the simulator can't start), with a way out.
    func testLockInWaitsForGuidedAccess() {
        let app = launch(["-uitest-reset", "-uitest-seed", "-uitest-arming"])
        wait(app.buttons["mode-chip"], 15).tap()
        wait(app.buttons["mode-lockIn"], 5).tap()
        app.buttons["start"].tap()
        wait(app.staticTexts["arming"], 5)
        shot("14-lock-in-arming")
        app.buttons["Start without Guided Access"].tap()
        wait(element(app, "focus-time"), 5)
        XCTAssertEqual(element(app, "mode-badge").label, "Deep Focus")
    }

    // MARK: - Screens

    /// Every screen from fixtures, still, for the screenshot review.
    func testScreensTour() {
        let screens = ["focus", "focus-ring", "focus-digits", "dimmed", "flow", "break", "ready", "complete",
                       "exam-complete", "unfinished"]
        for screen in screens {
            let app = launch(["-uitest-reset", "-uitest-still", "-uitest-screen", screen])
            sleep(2)
            shot("20-\(screen)")
            if screen == "focus" {
                XCUIDevice.shared.orientation = .landscapeLeft
                sleep(2)
                shot("20-focus-landscape")
                XCUIDevice.shared.orientation = .portrait
            }
            app.terminate()
        }
        for (step, name) in [(1, "streak"), (2, "goal"), (3, "rank-up")] {
            let app = launch(["-uitest-reset", "-uitest-still", "-uitest-screen", "complete", "-uitest-step", "\(step)"])
            sleep(2)
            shot("20-complete-\(name)")
            app.terminate()
        }
        let app = launch(["-uitest-reset", "-uitest-still", "-uitest-seed"])
        wait(app.buttons["start"], 15)
        app.buttons["streak-button"].tap()
        wait(app.navigationBars["Streak"], 5)
        shot("21-streak-sheet")
        app.buttons["Done"].tap()
        app.buttons["mode-chip"].tap()
        wait(app.buttons["mode-lockIn"], 5)
        shot("21-mode-sheet")
        app.buttons["Set up Lock In (Guided Access)"].tap()
        wait(app.navigationBars["Set up Lock In"], 5)
        shot("21-lock-in-guide")
        app.buttons["Done"].tap()
        app.buttons["Set up Focus Guard (Shortcuts)"].tap()
        wait(app.navigationBars["Focus Guard"], 5)
        shot("21-focus-guard-guide")
        app.buttons["Done"].tap()
        app.buttons["Done"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        shot("21-home-landscape")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["settings-button"].tap()
        wait(app.navigationBars["Settings"], 5)
        shot("22-settings")
        app.swipeUp()
        app.swipeUp()
        wait(app.buttons["Lock Lab"], 5).tap()
        wait(app.staticTexts["lab-verdict"], 5)
        shot("23-lock-lab")
    }

    /// Compact width (run on an iPhone simulator too, as in Split View).
    func testCompactTour() {
        for screen in ["focus", "break", "complete", "unfinished"] {
            let app = launch(["-uitest-reset", "-uitest-still", "-uitest-screen", screen])
            sleep(2)
            shot("compact-\(screen)")
            app.terminate()
        }
        let app = launch(["-uitest-reset", "-uitest-still", "-uitest-seed"])
        wait(app.buttons["start"], 15)
        shot("compact-home")
    }
}
