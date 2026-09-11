import XCTest

final class HairAnalysisUITests: XCTestCase {
    func testImportReportThroughFilesAndRestore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--hair-analysis-review-test"]
        app.launch()
        func reveal(_ element: XCUIElement, up: Bool = true) {
            for _ in 0..<7 { if element.isHittable { return }; if up { app.swipeUp() } else { app.swipeDown() } }
        }
        let lab = app.buttons["Capture lab"]; reveal(lab); lab.tap()
        let create = app.buttons["createFixture"]; reveal(create); create.tap()
        let pass = app.buttons["savedPass"].firstMatch
        XCTAssertTrue(pass.waitForExistence(timeout: 10)); reveal(pass, up: false); pass.tap()
        let importer = app.buttons["importHairAnalysis"]; reveal(importer)
        XCTAssertTrue(importer.isEnabled); importer.tap()
        let browse = app.buttons["Browse"]
        if browse.waitForExistence(timeout: 3) { browse.tap() }
        let onPhone = app.cells.containing(.staticText, identifier: "On My iPhone").firstMatch
        if onPhone.waitForExistence(timeout: 3) { onPhone.tap() }
        let folder = app.cells.containing(.staticText, identifier: "Personalized Hair").firstMatch
        if folder.waitForExistence(timeout: 3) { folder.tap() }
        let file = app.cells.containing(.staticText, identifier: "Hair analysis fixture.json").firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
        file.tap()
        let summary = app.staticTexts["hairAnalysisSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.label, "Inferred hair: 500 image pixels")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Imported hair evidence"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launch()
        reveal(app.buttons["Capture lab"]); app.buttons["Capture lab"].tap()
        let restoredPass = app.buttons["savedPass"].firstMatch
        XCTAssertTrue(restoredPass.waitForExistence(timeout: 10)); reveal(restoredPass, up: false); restoredPass.tap()
        reveal(app.staticTexts["hairAnalysisSummary"])
        XCTAssertEqual(app.staticTexts["hairAnalysisSummary"].label, "Inferred hair: 500 image pixels")
        reveal(app.sliders["Frame"], up: false)
        app.sliders["Frame"].adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue(app.staticTexts["Frame 3 of 3"].waitForExistence(timeout: 5))
        reveal(app.buttons["importHairAnalysis"])
        XCTAssertFalse(app.staticTexts["hairAnalysisSummary"].exists)
    }
}
