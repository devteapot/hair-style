import XCTest

final class LivePreviewUITests: XCTestCase {
    func testSyntheticRendererTimingExportsWithoutCamera() {
        let app = XCUIApplication(); app.launchArguments = ["--render-timing-test"]; app.launch()
        for _ in 0..<5 { if app.buttons["Capture lab"].isHittable { break }; app.swipeUp() }
        app.buttons["Capture lab"].tap()
        for _ in 0..<5 { if app.buttons["openLiveLab"].isHittable { break }; app.swipeUp() }
        app.buttons["openLiveLab"].tap(); app.buttons["loadPreviewFixture"].tap()
        let record=app.buttons["recordSyntheticRenderTiming"]
        XCTAssertTrue(record.waitForExistence(timeout:15)); record.tap()
        let summary=app.staticTexts["renderTimingSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout:15))
        XCTAssertTrue(summary.label.hasPrefix("Synthetic renderer callbacks:"))
        XCTAssertGreaterThan(Int(summary.label.split(separator:" ").last ?? "0") ?? 0, 0)
        for _ in 0..<5 { if app.buttons["Prepare timing export"].isHittable { break }; app.swipeUp() }
        app.buttons["Prepare timing export"].tap()
        XCTAssertTrue(app.buttons["Share timing report"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["Start camera"].exists)
    }
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
