import XCTest

final class HeadPreviewUITests: XCTestCase {
    func testHeadPreviewCanInspectStagedModelOrExplainEmptyState() throws {
        let app=XCUIApplication();app.launch();continueAfterFailure=false
        let lab=app.buttons["Capture lab"]
        XCTAssertTrue(lab.waitForExistence(timeout:10))
        if !lab.isHittable { app.swipeUp() };lab.tap()
        let open=app.buttons["openHeadPreview"]
        if !open.isHittable { app.swipeUp() };XCTAssertTrue(open.waitForExistence(timeout:5));open.tap()
        XCTAssertTrue(app.staticTexts["headPreviewNotice"].waitForExistence(timeout:10))
        let scene=app.descendants(matching:.any).matching(identifier:"reconstructedHeadScene").firstMatch
        if app.staticTexts["headPreviewLoaded"].waitForExistence(timeout:5) {
            XCTAssertTrue(scene.exists)
            scene.swipeLeft()
            let textured=XCTAttachment(screenshot:app.screenshot());textured.name="Imported head texture view";textured.lifetime = .keepAlways;add(textured)
            let toggle=app.switches["headClayToggle"]
            if !toggle.isHittable { app.swipeUp() };XCTAssertTrue(toggle.exists);toggle.tap()
            XCTAssertTrue(app.buttons["resetHeadView"].exists);app.buttons["resetHeadView"].tap()
            let clay=XCTAttachment(screenshot:app.screenshot());clay.name="Imported head geometry view";clay.lifetime = .keepAlways;add(clay)
        } else {
            XCTAssertTrue(app.staticTexts["No reconstructed model"].exists)
            XCTAssertTrue(app.buttons["importHeadPreview"].exists)
        }
    }
}
