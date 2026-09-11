import XCTest

final class LivePreviewUITests: XCTestCase {
    func testSimulatorExplainsUnsupportedLivePreviewWithoutStartingCamera() {
        let app = XCUIApplication(); app.launch()
        for _ in 0..<5 {
            if app.buttons["Capture lab"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["Capture lab"].tap()
        let link = app.buttons["openLiveLab"]
        for _ in 0..<4 { if link.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(app.staticTexts["liveUnsupported"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start camera"].exists)
        app.buttons["loadPreviewFixture"].tap()
        XCTAssertTrue(app.otherElements["importedHairScene"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["importedHairIdentity"].label.contains("Synthetic test asset"))
        XCTAssertTrue(app.staticTexts["importedHairIdentity"].label.contains("Revision 1"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Imported synthetic preview inspection"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
