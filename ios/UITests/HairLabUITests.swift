import XCTest

final class HairLabUITests: XCTestCase {
    func testRendererComparisonUpdatesGeometryWithoutChangingRevision() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launch();openLab(app)
        if app.buttons["createHairFixture"].exists { app.buttons["createHairFixture"].tap() }
        let link=app.buttons["compareHairRenderers"];reveal(link,in:app);link.tap()
        let scene=app.otherElements["hairRendererComparisonScene"]
        XCTAssertTrue(scene.waitForExistence(timeout:30))
        let tube=scene.value as? String ?? ""
        XCTAssertTrue(tube.hasPrefix("guide_tube_mesh_v1|"))
        let revision=app.staticTexts["hairRendererRevision"].label
        app.segmentedControls["hairRendererPicker"].buttons["Ribbons"].tap()
        let ribbonReady=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value BEGINSWITH %@","guide_ribbon_mesh_v1|"),object:scene)
        wait(for:[ribbonReady],timeout:10)
        let ribbon=scene.value as? String ?? ""
        XCTAssertNotEqual(tube,ribbon)
        XCTAssertEqual(tube.split(separator:"|").last,ribbon.split(separator:"|").last)
        XCTAssertEqual(app.staticTexts["hairRendererRevision"].label,revision)
        let image=XCTAttachment(screenshot:app.screenshot());image.name="Ribbon renderer comparison";image.lifetime = .keepAlways;add(image)
        app.segmentedControls["hairRendererPicker"].buttons["Tubes"].tap()
        let tubeReady=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",tube),object:scene)
        wait(for:[tubeReady],timeout:10)
    }
    func testPreferenceRowsScaleAtAccessibilitySize() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        var heights:[CGFloat]=[]
        for category in ["UICTContentSizeCategoryL","UICTContentSizeCategoryAccessibilityXXXL"] {
            app.launchArguments=["-UIPreferredContentSizeCategoryName",category]
            app.launch();openLab(app)
            if app.buttons["createHairFixture"].exists { app.buttons["createHairFixture"].tap() }
            let link=app.buttons["openDesignPreferences"];reveal(link,in:app);link.tap()
            let guided=app.switches["guidedPreferences"]
            XCTAssertTrue(guided.waitForExistence(timeout:10))
            if guided.value as? String != "1" { guided.switches.firstMatch.tap() }
            let row=app.buttons["productPreference"];reveal(row,in:app)
            heights.append(row.frame.height)
            let shot=XCTAttachment(screenshot:app.screenshot());shot.name=category;shot.lifetime = .keepAlways;add(shot)
            print("Preference row height at \(category): \(row.frame.height)")
            app.terminate()
        }
        XCTAssertGreaterThan(heights[1],heights[0]*1.5)
    }

    func testHomeAndGuidedPreferencesAccessibility() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launch()
        try app.performAccessibilityAudit(for:[.contrast,.sufficientElementDescription,.textClipped,.dynamicType,.hitRegion])
        openLab(app)
        if app.buttons["createHairFixture"].exists { app.buttons["createHairFixture"].tap() }
        let link=app.buttons["openDesignPreferences"];reveal(link,in:app);link.tap()
        let guided=app.switches["guidedPreferences"]
        XCTAssertTrue(guided.waitForExistence(timeout:10))
        if guided.value as? String != "1" { guided.switches.firstMatch.tap() }
        XCTAssertTrue(app.switches["limitStylingTime"].waitForExistence(timeout:10))
        try app.performAccessibilityAudit(for:[.contrast,.sufficientElementDescription,.textClipped,.dynamicType,.hitRegion])
        app.swipeUp()
        try app.performAccessibilityAudit(for:[.contrast,.sufficientElementDescription,.textClipped,.dynamicType,.hitRegion]) { issue in
            print("Accessibility audit: \(issue); element: \(String(describing:issue.element))")
            return false
        }
    }

    func testScrolledPreferencesAccessibilityFromFreshLaunch() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launch()
        openLab(app)
        if app.buttons["createHairFixture"].exists { app.buttons["createHairFixture"].tap() }
        let link=app.buttons["openDesignPreferences"];reveal(link,in:app);link.tap()
        let guided=app.switches["guidedPreferences"]
        XCTAssertTrue(guided.waitForExistence(timeout:10))
        if guided.value as? String != "1" { guided.switches.firstMatch.tap() }
        XCTAssertTrue(app.switches["limitStylingTime"].waitForExistence(timeout:10))
        app.swipeUp()
        try app.performAccessibilityAudit(for:[.contrast,.sufficientElementDescription,.textClipped,.dynamicType,.hitRegion]) { issue in
            print("Accessibility audit: \(issue); element: \(String(describing:issue.element))")
            return false
        }
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Scrolled preferences contrast";shot.lifetime = .keepAlways;add(shot)
    }

    func testPreferenceChoiceLabelsAndSelection() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launch();openLab(app)
        if app.buttons["createHairFixture"].exists { app.buttons["createHairFixture"].tap() }
        let link=app.buttons["openDesignPreferences"];reveal(link,in:app);link.tap()
        let guided=app.switches["guidedPreferences"]
        XCTAssertTrue(guided.waitForExistence(timeout:10))
        if guided.value as? String != "1" { guided.switches.firstMatch.tap() }
        let heat=app.buttons["heatPreference"];reveal(heat,in:app)
        XCTAssertEqual(heat.label,"Heat tools");XCTAssertNotNil(heat.value)
        heat.tap()
        try app.performAccessibilityAudit(for:[.contrast,.sufficientElementDescription,.textClipped,.dynamicType,.hitRegion])
        app.buttons["No"].tap()
        XCTAssertEqual(app.buttons["heatPreference"].value as? String,"No")
    }

    func testDesignPreferencesPersistWithoutChangingHaircut() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launch();openLab(app)
        if app.buttons["createHairFixture"].exists { app.buttons["createHairFixture"].tap() }
        XCTAssertTrue(app.staticTexts["selectedHairHash"].waitForExistence(timeout:10))
        let original=app.staticTexts["selectedHairHash"].label
        func openPreferences() {
            let link=app.buttons["openDesignPreferences"];reveal(link,in:app);link.tap()
            XCTAssertTrue(app.switches["guidedPreferences"].waitForExistence(timeout:10))
        }
        openPreferences()
        let guided=app.switches["guidedPreferences"]
        if guided.value as? String == "1" { guided.switches.firstMatch.tap() }
        app.buttons["saveDesignPreferences"].tap()
        XCTAssertTrue(app.staticTexts["designPreferencesStatus"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["designPreferencesStatus"].label.contains("automatic"))
        let ready=NSPredicate { _,_ in guided.isEnabled }
        expectation(for:ready,evaluatedWith:nil);waitForExpectations(timeout:10)
        guided.switches.firstMatch.tap()
        let lengths=app.buttons["openLengthPreferences"]
        XCTAssertTrue(lengths.waitForExistence(timeout:10));lengths.tap()
        let enabled=app.switches["lengthEnabled_fringe"]
        reveal(enabled,in:app)
        if enabled.value as? String == "1" { enabled.switches.firstMatch.tap() }
        enabled.switches.firstMatch.tap()
        let minimum=app.steppers["lengthMin_fringe"]
        reveal(minimum,in:app);minimum.buttons["lengthMin_fringe-Increment"].tap()
        XCTAssertTrue(minimum.label.contains("11"))
        app.navigationBars.buttons.firstMatch.tap()
        let rangeValue = lengths.value as? String
        XCTAssertNotNil(rangeValue)
        XCTAssertTrue(rangeValue?.contains("regional range") == true)
        let rangeShot=XCTAttachment(screenshot:app.screenshot());rangeShot.name="Range summary and accessible value";rangeShot.lifetime = .keepAlways;add(rangeShot)
        let limit=app.switches["limitStylingTime"]
        XCTAssertTrue(limit.waitForExistence(timeout:10))
        if limit.value as? String != "1" { limit.switches.firstMatch.tap() }
        let save=app.buttons["saveDesignPreferences"];reveal(save,in:app);save.tap()
        XCTAssertTrue(app.staticTexts["designPreferencesStatus"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["designPreferencesStatus"].label.contains("guided"))
        XCTAssertTrue(app.buttons["exportDesignBrief"].exists)
        app.terminate();app.launch();openLab(app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,original)
        openPreferences()
        XCTAssertEqual(app.switches["guidedPreferences"].value as? String,"1")
        XCTAssertEqual(app.switches["limitStylingTime"].value as? String,"1")
        XCTAssertTrue(app.steppers["stylingMinutes"].exists)
        XCTAssertFalse(app.staticTexts["designPreferencesError"].exists)
        let restoredLengths=app.buttons["openLengthPreferences"]
        XCTAssertEqual(restoredLengths.value as? String,rangeValue)
        reveal(restoredLengths,in:app);restoredLengths.tap()
        let restoredMinimum=app.steppers["lengthMin_fringe"]
        reveal(restoredMinimum,in:app)
        XCTAssertTrue(restoredMinimum.label.contains("11"))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    private func openLab(_ app: XCUIApplication) {
        let lab = app.buttons["Capture lab"]
        reveal(lab,in: app); lab.tap()
        let open = app.buttons["openHairLab"]
        reveal(open,in: app); open.tap()
        XCTAssertTrue(app.staticTexts["hairLabNotice"].waitForExistence(timeout: 10))
    }
    private func expectStatus(_ text: String, app: XCUIApplication) {
        let status = app.staticTexts["hairRevisionStatus"]
        let predicate = NSPredicate(format: "label == %@", text)
        expectation(for: predicate, evaluatedWith: status)
        waitForExpectations(timeout: 10)
    }
    private func removeFixture(_ app: XCUIApplication) {
        let button = app.buttons["deleteHairFixture"]
        reveal(button,in: app); button.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["createHairFixture"].waitForExistence(timeout: 10))
    }
    func testDirectionEditPersistsWithUndoAndUnchangedLengths() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launch();openLab(app)
        if !app.buttons["createHairFixture"].waitForExistence(timeout:3) { removeFixture(app) }
        let create=app.buttons["createHairFixture"];reveal(create,in:app);create.tap()
        expectStatus("Saved · revision 1",app:app)
        let original=app.staticTexts["selectedHairHash"].label
        let lengths=app.staticTexts["hairLengths"].label
        let slider=app.sliders["fringeDirectionSlider"];reveal(slider,in:app);slider.adjust(toNormalizedSliderPosition:0.85)
        let preview=app.buttons["previewFringeDirection"];reveal(preview,in:app);preview.tap()
        expectStatus("Unsaved preview",app:app)
        XCTAssertEqual(app.staticTexts["hairLengths"].label,lengths)
        let save=app.buttons["saveHairRevision"];reveal(save,in:app);save.tap()
        expectStatus("Saved · revision 2",app:app)
        let changed=app.staticTexts["selectedHairHash"].label;XCTAssertNotEqual(changed,original)
        app.terminate();app.launch();openLab(app);expectStatus("Saved · revision 2",app:app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,changed)
        XCTAssertEqual(app.staticTexts["hairLengths"].label,lengths)
        let undo=app.buttons["undoHairRevision"];reveal(undo,in:app);undo.tap()
        expectStatus("Saved · revision 1",app:app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,original)
        let redo=app.buttons["redoHairRevision"];reveal(redo,in:app);redo.tap()
        expectStatus("Saved · revision 2",app:app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,changed)
        let details=app.buttons["hairDesignDetails"];reveal(details,in:app);details.tap()
        let explanation=app.staticTexts.containing(NSPredicate(format:"label BEGINSWITH 'Last edit: rotate fringe direction'")).firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout:10));reveal(explanation,in:app)
        XCTAssertTrue(explanation.label.contains("Last edit: rotate fringe direction by +"))
        XCTAssertTrue(explanation.label.contains("Roots and lengths are preserved"))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label BEGINSWITH 'Last edit: scale'")).firstMatch.exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Direction edit history";shot.lifetime = .keepAlways;add(shot)
        removeFixture(app)
    }

    func testGuidesEditCompareUndoRedoPersistAndDelete() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); openLab(app)
        // Prior failed test runs may have left this explicitly synthetic fixture.
        if !app.buttons["createHairFixture"].waitForExistence(timeout: 3) { removeFixture(app) }
        let create = app.buttons["createHairFixture"]
        reveal(create,in: app); create.tap()
        expectStatus("Saved · revision 1",app: app)
        let initial = app.staticTexts["selectedHairHash"].label
        XCTAssertTrue(app.staticTexts["hairLengths"].label.contains("Fringe 134 mm"))
        let preview = app.buttons["previewFringe"]
        reveal(preview,in: app); preview.tap()
        expectStatus("Unsaved preview",app: app)
        XCTAssertTrue(app.staticTexts["hairLengths"].label.contains("Fringe 70 mm"))
        let save = app.buttons["saveHairRevision"]
        reveal(save,in: app); save.tap()
        expectStatus("Saved · revision 2",app: app)
        let shortened = app.staticTexts["selectedHairHash"].label
        XCTAssertNotEqual(initial,shortened)
        let undo = app.buttons["undoHairRevision"]
        reveal(undo,in: app); undo.tap()
        expectStatus("Saved · revision 1",app: app)
        XCTAssertEqual(initial,app.staticTexts["selectedHairHash"].label)
        app.buttons["redoHairRevision"].tap()
        expectStatus("Saved · revision 2",app: app)
        XCTAssertEqual(shortened,app.staticTexts["selectedHairHash"].label)
        app.terminate(); app.launch(); openLab(app)
        expectStatus("Saved · revision 2",app: app)
        XCTAssertEqual(shortened,app.staticTexts["selectedHairHash"].label)
        let compare = app.switches["compareHairOriginal"]
        reveal(compare,in: app); compare.tap()
        expectStatus("Original · revision 1",app: app)
        XCTAssertTrue(app.staticTexts["hairLengths"].label.contains("Fringe 134 mm"))
        compare.tap(); expectStatus("Saved · revision 2",app: app)
        let crown = app.buttons["previewCrown"]
        reveal(crown,in: app); crown.tap()
        expectStatus("Unsaved preview",app: app)
        XCTAssertTrue(app.staticTexts["hairLengths"].label.contains("Fringe 70 mm"))
        XCTAssertTrue(app.staticTexts["hairLengths"].label.contains("crown 116 mm"))
        reveal(app.buttons["discardHairPreview"],in: app); app.buttons["discardHairPreview"].tap()
        expectStatus("Saved · revision 2",app: app)
        XCTAssertEqual(shortened,app.staticTexts["selectedHairHash"].label)
        app.swipeDown(); app.swipeDown()
        app.buttons["resetHairCamera"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native guide studio edited revision"; screenshot.lifetime = .keepAlways
        add(screenshot)
        removeFixture(app)
        app.terminate(); app.launch(); openLab(app)
        XCTAssertTrue(app.buttons["createHairFixture"].waitForExistence(timeout: 10))
    }
    func testDesignDetailsFollowDisplayedRevision() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); openLab(app)
        if !app.buttons["createHairFixture"].waitForExistence(timeout: 3) { removeFixture(app) }
        app.buttons["createHairFixture"].tap()
        expectStatus("Saved · revision 1", app: app)
        let details = app.buttons["hairDesignDetails"]
        reveal(details, in: app); details.tap()
        XCTAssertTrue(app.staticTexts["Revision 1 · Automatic defaults"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Current length is uncertain; this range does not establish that your hair can achieve it."].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Revision-specific design details"; screenshot.lifetime = .keepAlways; add(screenshot)
        details.tap()
        let preview = app.buttons["previewFringe"]
        reveal(preview, in: app); preview.tap()
        expectStatus("Unsaved preview", app: app)
        app.swipeDown()
        reveal(details, in: app); details.tap()
        XCTAssertTrue(app.staticTexts["Revision 2 · Automatic defaults"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Last edit: shorten fringe to at most 70.0 mm."].exists)
        details.tap()
        app.swipeDown()
        let compare = app.switches["compareHairOriginal"]
        reveal(compare, in: app); compare.tap()
        reveal(details, in: app); details.tap()
        XCTAssertTrue(app.staticTexts["Revision 1 · Automatic defaults"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Last edit: shorten fringe to at most 70.0 mm."].exists)
        details.tap()
        removeFixture(app)
    }

    func testNativeProcessingUploadsAndRestoresVerifiedResult() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); openLab(app)
        if app.buttons["createHairFixture"].waitForExistence(timeout: 2) { app.buttons["createHairFixture"].tap() }
        let open = app.buttons["openProcessingLab"]
        reveal(open, in: app); open.tap()
        let advance = app.buttons["advanceProcessingJob"]
        XCTAssertTrue(advance.waitForExistence(timeout: 10)); advance.tap()
        for _ in 0..<5 {
            let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: advance)
            wait(for: [idle], timeout: 20)
            if app.otherElements["processingResultScene"].exists { break }
            advance.tap()
        }
        XCTAssertTrue(app.otherElements["processingResultScene"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["processingError"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Verified native processing result"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch(); openLab(app)
        reveal(open, in: app); open.tap()
        XCTAssertTrue(app.otherElements["processingResultScene"].waitForExistence(timeout: 10))
    }
    func testNativeProcessingCancellationSurvivesRelaunch() throws {
        // Run with the loopback API available and no compiler worker.
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); openLab(app)
        if app.buttons["createHairFixture"].waitForExistence(timeout: 2) { app.buttons["createHairFixture"].tap() }
        let open = app.buttons["openProcessingLab"]
        reveal(open, in: app); open.tap()
        let advance = app.buttons["advanceProcessingJob"]
        XCTAssertTrue(advance.waitForExistence(timeout: 10))
        let remove = app.buttons["deleteProcessingJob"]
        if remove.exists {
            reveal(remove, in: app); remove.tap()
            app.alerts.buttons["Delete"].tap()
            let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)
            wait(for: [cleared], timeout: 15)
        }
        reveal(advance, in: app); advance.tap()
        let cancel = app.buttons["cancelProcessingJob"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: cancel)
        wait(for: [ready], timeout: 15); cancel.tap()
        let status = app.staticTexts["processingStatus"]
        let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Cancelled'"), object: status)
        wait(for: [cancelled], timeout: 15)
        XCTAssertFalse(app.staticTexts["processingError"].exists)
        app.terminate(); app.launch(); openLab(app)
        reveal(open, in: app); open.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 10)); XCTAssertEqual(status.label, "Cancelled")
        XCTAssertFalse(app.buttons["cancelProcessingJob"].exists)
        XCTAssertFalse(app.otherElements["processingResultScene"].exists)
    }
    func testNativeProcessingCachedResultWithoutServer() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); openLab(app)
        let open = app.buttons["openProcessingLab"]
        reveal(open, in: app); open.tap()
        XCTAssertTrue(app.otherElements["processingResultScene"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["processingError"].exists)
    }

}
