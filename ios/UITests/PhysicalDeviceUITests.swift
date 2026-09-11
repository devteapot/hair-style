import XCTest

final class PhysicalDeviceUITests: XCTestCase {
    func testCompatiblePhoneShowsCaptureWithoutStartingIt() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical-device capability check")
        #else
        let app = XCUIApplication(); app.launch()
        continueAfterFailure = false
        XCTAssertTrue(app.staticTexts["Your camera system is supported"].waitForExistence(timeout: 15))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Face details")).firstMatch.tap()
        let capture = app.buttons["captureButton"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        XCTAssertFalse(capture.isEnabled)
        if !capture.isHittable { app.swipeUp() }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Physical front capture ready; consent not given"
        screenshot.lifetime = .keepAlways; add(screenshot)
        #endif
    }
}
