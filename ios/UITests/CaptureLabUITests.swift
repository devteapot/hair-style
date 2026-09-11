import XCTest

final class CaptureLabUITests: XCTestCase {
    func testSimulatorCanInspectSyntheticEvidenceWithoutOpeningCamera() throws {
        let app = XCUIApplication()
        app.launch()
        continueAfterFailure = false
        XCTAssertTrue(app.staticTexts["capabilityNotice"].waitForExistence(timeout: 10))
        let lab = app.buttons["Capture lab"]
        if !lab.isHittable { app.swipeUp() }
        lab.tap()
        let fixture = app.buttons["createFixture"]
        if !fixture.isHittable { app.swipeUp() }
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        fixture.tap()
        let pass = app.buttons["savedPass"].firstMatch
        XCTAssertTrue(pass.waitForExistence(timeout: 10))
        if !pass.isHittable { app.swipeDown() }
        pass.tap()
        XCTAssertTrue(app.staticTexts["syntheticNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["scanQualityStatus"].exists)
        let analyze = app.buttons["analyzeLandmarks"]
        if !analyze.isHittable { app.swipeUp() }
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        analyze.tap()
        XCTAssertTrue(app.staticTexts["landmarkStatus"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["landmarkStatus"].label,"No face detected. Check orientation and visibility.")
        let landmarkAttachment = XCTAttachment(screenshot: app.screenshot())
        landmarkAttachment.name = "Face analysis on non-face fixture"
        landmarkAttachment.lifetime = .keepAlways
        add(landmarkAttachment)
        app.swipeDown()
        let display = app.segmentedControls["reviewDisplay"]
        display.buttons["3D depth"].tap()
        XCTAssertTrue(app.staticTexts["Frame 1 of 3"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Synthetic depth inspection"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.swipeUp()
        for _ in 0..<5 { if app.buttons["exportCapture"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.otherElements["captureTiming"].exists || app.staticTexts["Saved frame timing"].exists)
        XCTAssertTrue(app.buttons["exportCapture"].isEnabled)
        app.buttons["exportCapture"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        app.buttons["header.closeButton"].tap()
        XCTAssertTrue(app.buttons["deleteCapture"].waitForExistence(timeout: 5))
        app.buttons["deleteCapture"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["A cut that\nstarts with you."].waitForExistence(timeout: 5))
    }
    func testDeletingCaptureDiscardsCompletedLateExport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--hold-export-publication-test"]
        app.launch()
        let lab = app.buttons["Capture lab"]
        for _ in 0..<5 { if lab.isHittable { break }; app.swipeUp() }
        lab.tap()
        let fixture = app.buttons["createFixture"]
        for _ in 0..<5 { if fixture.isHittable { break }; app.swipeUp() }
        fixture.tap()
        let pass = app.buttons["savedPass"].firstMatch
        XCTAssertTrue(pass.waitForExistence(timeout: 10))
        for _ in 0..<5 { if pass.isHittable { break }; app.swipeDown() }
        pass.tap()
        XCTAssertTrue(app.staticTexts["syntheticNotice"].waitForExistence(timeout: 10))
        let export = app.buttons["exportCapture"]
        for _ in 0..<5 { if export.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(export.isEnabled); export.tap()
        XCTAssertTrue(app.staticTexts["exportPublicationHeld"].waitForExistence(timeout: 10))
        let delete = app.buttons["deleteCapture"]
        for _ in 0..<3 { if delete.isHittable { break }; app.swipeUp() }
        delete.tap(); app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["A cut that\nstarts with you."].waitForExistence(timeout: 5))
        let unwanted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"),
            object: app.otherElements["ActivityListView"])
        unwanted.isInverted = true
        wait(for: [unwanted], timeout: 6)
    }

    func testGuestCredentialSurvivesRelaunchAndIsEndpointScoped() {
        let app = XCUIApplication()
        app.launchArguments = ["--credential-probe-write"]; app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic credential saved"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["--credential-probe-read"]; app.launch()
        XCTAssertTrue(app.staticTexts["Credential restored, isolated and deleted"].waitForExistence(timeout: 10))
    }

}
