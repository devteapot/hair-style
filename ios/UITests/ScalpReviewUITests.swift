import XCTest

final class ScalpReviewUITests:XCTestCase {
    func testStagedScalpCanRenderWithoutEditing() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launch()
        let lab=app.buttons["Capture lab"]
        for _ in 0..<5 { if lab.isHittable { break };app.swipeUp() }
        XCTAssertTrue(lab.waitForExistence(timeout:10));lab.tap()
        let link=app.buttons["openScalpReview"]
        for _ in 0..<5 { if link.isHittable { break };app.swipeUp() }
        XCTAssertTrue(link.exists);link.tap()
        XCTAssertTrue(app.staticTexts["scalpRevision"].waitForExistence(timeout:20))
        XCTAssertFalse(app.staticTexts["scalpReviewError"].exists)
        let scene=app.descendants(matching:.any).matching(identifier:"scalpReviewScene").firstMatch
        XCTAssertTrue(scene.exists);scene.swipeLeft()
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Scalp review on device";shot.lifetime = .keepAlways;add(shot)
    }

    func testStagedScalpAdjustmentPersistsAfterRelaunch() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        func open() {
            app.launch()
            let lab=app.buttons["Capture lab"]
            XCTAssertTrue(lab.waitForExistence(timeout:10))
            if !lab.isHittable { app.swipeUp() };lab.tap()
            let link=app.buttons["openScalpReview"]
            for _ in 0..<4 { if link.isHittable { break };app.swipeUp() }
            XCTAssertTrue(link.waitForExistence(timeout:5));link.tap()
            XCTAssertTrue(app.staticTexts["scalpRevision"].waitForExistence(timeout:20))
        }
        open()
        let before=app.staticTexts["scalpRevision"].label
        XCTAssertFalse(app.staticTexts["scalpReviewError"].exists)
        let scene=app.descendants(matching:.any).matching(identifier:"scalpReviewScene").firstMatch
        XCTAssertTrue(scene.exists);scene.swipeLeft()
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Recorded face and inferred scalp review";attachment.lifetime = .keepAlways;add(attachment)
        let width=app.steppers["scalpWidth"]
        for _ in 0..<4 { if width.isHittable { break };app.swipeUp() }
        XCTAssertTrue(width.exists);width.buttons["scalpWidth-Increment"].tap()
        let position=app.steppers["scalpPositionY"]
        for _ in 0..<5 { if position.isHittable { break };app.swipeUp() }
        XCTAssertTrue(position.exists)
        let oldPosition=position.label
        position.buttons["scalpPositionY-Increment"].tap()
        XCTAssertNotEqual(position.label,oldPosition)
        let adjustedPosition=position.label
        let save=app.buttons["saveScalpAdjustment"]
        for _ in 0..<4 { if save.isHittable { break };app.swipeUp() }
        XCTAssertTrue(save.isEnabled);save.tap()
        let saved=NSPredicate { _,_ in app.staticTexts["scalpRevision"].label != before && !app.buttons["saveScalpAdjustment"].isEnabled }
        expectation(for:saved,evaluatedWith:nil);waitForExpectations(timeout:25)
        let after=app.staticTexts["scalpRevision"].label
        XCTAssertFalse(app.staticTexts["scalpReviewError"].exists)
        app.terminate();open()
        XCTAssertEqual(app.staticTexts["scalpRevision"].label,after)
        let restoredPosition=app.steppers["scalpPositionY"]
        for _ in 0..<5 { if restoredPosition.isHittable { break };app.swipeUp() }
        XCTAssertEqual(restoredPosition.label,adjustedPosition)
    }
}
