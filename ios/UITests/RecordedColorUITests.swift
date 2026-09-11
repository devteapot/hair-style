import XCTest

final class RecordedColorUITests: XCTestCase {
    func testChooseRecordedColorSaveAndUndo() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--recorded-color-test"]; app.launch()
        func reveal(_ element: XCUIElement, up: Bool = true) {
            for _ in 0..<8 { if element.isHittable { return }; if up { app.swipeUp() } else { app.swipeDown() } }
        }
        let lab = app.buttons["Capture lab"]; reveal(lab); lab.tap()
        let fixture = app.buttons["createFixture"]; reveal(fixture); fixture.tap()
        let studio = app.buttons["openHairLab"]; reveal(studio); studio.tap()
        let create = app.buttons["createHairFixture"]
        if !create.waitForExistence(timeout: 3) {
            let delete = app.buttons["deleteHairFixture"]; reveal(delete); delete.tap()
            app.alerts.buttons["Delete"].tap()
        }
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let choose = app.buttons["chooseRecordedHairColor"]; reveal(choose); choose.tap()
        let source = app.buttons["recordedColorSource"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10)); source.tap()
        let save = app.buttons["saveHairRevision"]
        XCTAssertTrue(save.waitForExistence(timeout: 10)); reveal(save); save.tap()
        let saved = app.staticTexts["Saved · revision 2"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        let undo = app.buttons["undoHairRevision"]; reveal(undo); undo.tap()
        XCTAssertTrue(app.staticTexts["Saved · revision 1"].waitForExistence(timeout: 10))
        let redo = app.buttons["redoHairRevision"]; reveal(redo); redo.tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        for _ in 0..<5 { app.swipeDown() }
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Saved recorded-color revision"; image.lifetime = .keepAlways; add(image)
    }
}
