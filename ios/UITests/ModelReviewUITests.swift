import XCTest

final class ModelReviewUITests:XCTestCase {
    private func openConditioningPreparation(_ app:XCUIApplication) {
        let button=app.buttons["preparePersonalGeneration"];reveal(button,app)
        if button.frame.midY > app.frame.height*0.7 {
            app.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.8)).press(forDuration:0.05,
                thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.5)))
        }
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:button)
        wait(for:[ready],timeout:30);button.tap()
        XCTAssertTrue(app.textFields["processingEndpoint"].waitForExistence(timeout:60))
    }
    func testNativeConditioningPreservesSourceAndRestoresReviewedCandidate() throws {
        // Requires the refined revision-2 fixture and an enabled local model worker on 8767.
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--refined-model-review-test"];open(app)
        status("Saved · revision 2",app)
        let sourceHash=app.staticTexts["selectedHairHash"].label
        openConditioningPreparation(app)
        let endpoint=app.textFields["processingEndpoint"];XCTAssertTrue(endpoint.waitForExistence(timeout:60));endpoint.tap()
        endpoint.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(endpoint.value as? String ?? "").count))
        endpoint.typeText("http://127.0.0.1:8767\n")
        let prepConsent=app.switches["personalPreparationConsent"];reveal(prepConsent,app);prepConsent.switches.firstMatch.tap()
        let advancePreparation=app.buttons["advanceProcessingJob"];reveal(advancePreparation,app);advancePreparation.tap()
        let candidate=app.buttons["openPersonalConditioning"]
        XCTAssertTrue(candidate.waitForExistence(timeout:60));reveal(candidate,app);candidate.tap()
        let advance=app.buttons["advanceConditioning"]
        XCTAssertTrue(advance.waitForExistence(timeout:15));XCTAssertFalse(advance.isEnabled)
        let consent=app.switches["conditioningConsent"];reveal(consent,app);consent.switches.firstMatch.tap()
        reveal(advance,app);advance.tap()
        let review=app.staticTexts["conditioningReview"]
        XCTAssertTrue(review.waitForExistence(timeout:180))
        XCTAssertFalse(app.staticTexts["conditioningError"].exists)
        XCTAssertTrue(review.label.contains("24 guide curves"));XCTAssertTrue(review.label.contains("2 anatomy regions"))
        let revision=app.staticTexts["conditioningRevision"].label
        let saveStudio=app.buttons["saveCandidateStudio"];reveal(saveStudio,app);saveStudio.tap()
        status("Saved · revision 1",app)
        let studioHash=app.staticTexts["selectedHairHash"].label
        XCTAssertTrue(revision.contains(studioHash));XCTAssertNotEqual(studioHash,sourceHash)
        app.terminate();open(app);status("Saved · revision 2",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,sourceHash)
        openConditioningPreparation(app);XCTAssertTrue(candidate.waitForExistence(timeout:30));reveal(candidate,app);candidate.tap()
        XCTAssertTrue(review.waitForExistence(timeout:60));XCTAssertEqual(app.staticTexts["conditioningRevision"].label,revision)
        XCTAssertFalse(app.staticTexts["conditioningError"].exists)
        reveal(review,app)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Native conditioning candidate restored";shot.lifetime = .keepAlways;add(shot)
        let remove=app.buttons["deleteConditioning"];reveal(remove,app);remove.tap();app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(consent.waitForExistence(timeout:20))
        app.navigationBars.buttons.element(boundBy:0).tap()
        let removePreparation=app.buttons["deleteProcessingJob"]
        XCTAssertTrue(removePreparation.waitForExistence(timeout:30));reveal(removePreparation,app)
        let deletionReady=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:removePreparation)
        wait(for:[deletionReady],timeout:30);removePreparation.tap()
        XCTAssertTrue(app.alerts.buttons["Delete"].waitForExistence(timeout:10));app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(prepConsent.waitForExistence(timeout:20))
        app.terminate();app.launch()
        let lab=app.buttons["Capture lab"];reveal(lab,app);lab.tap()
        let library=app.buttons["savedCandidateStudios"];XCTAssertTrue(library.waitForExistence(timeout:15));reveal(library,app);library.tap()
        let savedStudio=app.buttons["Candidate \(studioHash)"];XCTAssertTrue(savedStudio.waitForExistence(timeout:15));savedStudio.tap()
        status("Saved · revision 1",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,studioHash)
        let removeStudio=app.buttons["deleteHairFixture"];reveal(removeStudio,app);removeStudio.tap();app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No model review"].waitForExistence(timeout:20))
        app.terminate();open(app);status("Saved · revision 2",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,sourceHash)
    }

    func testSavedCandidateStudioSurvivesProcessingDeletion() throws {
        // Requires one separately saved candidate from the real conditioning scenario.
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--refined-model-review-test"];open(app)
        status("Saved · revision 2",app)
        let source=app.staticTexts["selectedHairHash"].label
        app.terminate();app.launch()
        let lab=app.buttons["Capture lab"];reveal(lab,app);lab.tap()
        let library=app.buttons["savedCandidateStudios"];reveal(library,app);library.tap()
        let candidate=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'candidateStudio-'")).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout:20))
        let hash=String(candidate.identifier.dropFirst("candidateStudio-".count).prefix(10));candidate.tap()
        status("Saved · revision 1",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,hash)
        XCTAssertNotEqual(hash,source)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Separate saved candidate studio";shot.lifetime = .keepAlways;add(shot)
        let remove=app.buttons["deleteHairFixture"];reveal(remove,app);remove.tap();app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No model review"].waitForExistence(timeout:20))
        app.terminate();open(app);status("Saved · revision 2",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,source)
    }

    func testFreshShortCandidateHighlightsConflictsAfterRelaunch() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--fresh-short-review-test"];open(app)
        let load=app.buttons["loadPreparedModelReview"];if load.waitForExistence(timeout:3) { reveal(load,app);load.tap() }
        status("Saved · revision 1",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,"eb21601869")
        let legend=app.staticTexts["conflictingSegmentLegend"]
        XCTAssertTrue(legend.waitForExistence(timeout:90));XCTAssertTrue(legend.label.contains("68 of 68"))
        XCTAssertFalse(app.staticTexts["conflictingRootLegend"].exists)
        app.terminate();open(app);status("Saved · revision 1",app)
        XCTAssertTrue(legend.waitForExistence(timeout:90));XCTAssertTrue(legend.label.contains("68 of 68"))
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,"eb21601869")
        let compare=app.switches["compareHairOriginal"];reveal(compare,app);compare.tap()
        let originalLegend=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS '68 of 68'"),object:legend)
        wait(for:[originalLegend],timeout:90)
        status("Original · revision 1",app)
        reveal(compare,app);compare.tap()
        let selectedLegend=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS '68 of 68'"),object:legend)
        wait(for:[selectedLegend],timeout:90)
        reveal(legend,app)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Fresh short candidate curve conflicts";shot.lifetime = .keepAlways;add(shot)
    }

    func testPreparedPipelineRevisionRetainsCurveReviewAfterRelaunch() throws {
        // Requires the retained actual pipeline package in its isolated simulator fixture.
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--prepared-pipeline-model-review-test"];open(app)
        let load=app.buttons["loadPreparedModelReview"]
        XCTAssertTrue(load.waitForExistence(timeout:10));reveal(load,app);load.tap()
        status("Saved · revision 1",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,"ead3e0a232")
        app.terminate();open(app);status("Saved · revision 1",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,"ead3e0a232")
        let clearance=app.staticTexts["faceClearanceStatus"]
        XCTAssertTrue(clearance.waitForExistence(timeout:60));reveal(clearance,app)
        let checked=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Hair curves need revision"),object:clearance)
        wait(for:[checked],timeout:60)
        XCTAssertEqual(app.staticTexts["faceClearanceRevision"].label,"Checked revision ead3e0a232")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS '24 guide curves conflict'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'Ear surfaces are unavailable'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["conflictingRootLegend"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Prepared pipeline curve review restored";shot.lifetime = .keepAlways;add(shot)
    }

    func testPersonalPreparationRequiresConsentAndRestoresVerifiedResult() throws {
        // Requires the refined revision-2 fixture and loopback service on port 8767.
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--refined-model-review-test"];open(app)
        status("Saved · revision 2",app)
        let sourceHash=app.staticTexts["selectedHairHash"].label
        let prepare=app.buttons["preparePersonalGeneration"];reveal(prepare,app);prepare.tap()
        let advance=app.buttons["advanceProcessingJob"]
        XCTAssertTrue(advance.waitForExistence(timeout:30));XCTAssertFalse(advance.isEnabled)
        let endpoint=app.textFields["processingEndpoint"];endpoint.tap()
        endpoint.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(endpoint.value as? String ?? "").count))
        endpoint.typeText("http://127.0.0.1:8767\n")
        let consent=app.switches["personalPreparationConsent"];reveal(consent,app);consent.switches.firstMatch.tap()
        reveal(advance,app);XCTAssertTrue(advance.isEnabled);advance.tap()
        let result=app.staticTexts["personalPreparationResult"]
        // No manual refresh: the visible active job must retrieve its result.
        XCTAssertTrue(result.waitForExistence(timeout:60))
        XCTAssertFalse(app.staticTexts["processingError"].exists)
        XCTAssertEqual(result.label,"No supplied-surface attachment conflicts")
        XCTAssertTrue(app.staticTexts["personalPreparationLimitations"].label.contains("2 anatomy regions"))
        app.terminate();open(app);status("Saved · revision 2",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,sourceHash)
        reveal(prepare,app);prepare.tap()
        XCTAssertTrue(result.waitForExistence(timeout:30))
        XCTAssertEqual(result.label,"No supplied-surface attachment conflicts")
        XCTAssertFalse(app.staticTexts["processingError"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Native personal preparation restored";shot.lifetime = .keepAlways;add(shot)
        let remove=app.buttons["deleteProcessingJob"];reveal(remove,app);remove.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(consent.waitForExistence(timeout:20))
    }
    func testRefinedEditPersistsAndHandsExactRevisionToAlignment() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--refined-model-review-test"];open(app)
        let load=app.buttons["loadPreparedModelReview"]
        XCTAssertTrue(load.waitForExistence(timeout:10));reveal(load,app);load.tap()
        status("Saved · revision 1",app)
        let original=app.staticTexts["selectedHairHash"].label
        let slider=app.sliders["fringeLengthSlider"];reveal(slider,app);slider.adjust(toNormalizedSliderPosition:0.8)
        let preview=app.buttons["previewFringe"];reveal(preview,app);preview.tap()
        status("Unsaved preview",app)
        let save=app.buttons["saveHairRevision"];reveal(save,app);save.tap()
        status("Saved · revision 2",app)
        let changed=app.staticTexts["selectedHairHash"].label
        XCTAssertNotEqual(original,changed)
        app.terminate();open(app);status("Saved · revision 2",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,changed)
        let clearance=app.staticTexts["faceClearanceStatus"]
        XCTAssertTrue(clearance.waitForExistence(timeout:60));reveal(clearance,app)
        XCTAssertEqual(clearance.label,"No conflicts with the supplied face surface")
        XCTAssertEqual(app.staticTexts["faceClearanceRevision"].label,"Checked revision \(changed)")
        let alignment=app.buttons["alignModelLivePreview"];reveal(alignment,app);alignment.tap()
        XCTAssertTrue(app.staticTexts["alignmentRevision"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["alignmentRevision"].label.contains(changed))
        XCTAssertTrue(app.staticTexts["alignmentPointPrompt"].label.contains("Point 1 of 7"))
        XCTAssertFalse(app.buttons["startAlignmentCamera"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Refined edited revision alignment handoff";shot.lifetime = .keepAlways;add(shot)
    }
    func testRefinedResearchRevisionShowsExactHashAndIncompleteEvidence() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--refined-model-review-test"];open(app)
        let load=app.buttons["loadPreparedModelReview"]
        XCTAssertTrue(load.waitForExistence(timeout:10));reveal(load,app);load.tap()
        status("Saved · revision 1",app)
        XCTAssertTrue(app.staticTexts["researchRevisionNotice"].exists)
        let clearance=app.staticTexts["faceClearanceStatus"]
        XCTAssertTrue(clearance.waitForExistence(timeout:60));reveal(clearance,app)
        let checked=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","No conflicts with the supplied face surface"),object:clearance)
        wait(for:[checked],timeout:60)
        XCTAssertEqual(app.staticTexts["faceClearanceRevision"].label,"Checked revision 09083db360")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'Ear surfaces are unavailable'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["conflictingRootLegend"].exists)
        let clearanceShot=XCTAttachment(screenshot:app.screenshot());clearanceShot.name="Refined research clearance limitations";clearanceShot.lifetime = .keepAlways;add(clearanceShot)
        for _ in 0..<8 { app.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.25)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.8))) }
        let reset=app.buttons["resetHairCamera"];if reset.isHittable { reset.tap() }
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Refined research model preview";shot.lifetime = .keepAlways;add(shot)
        let remove=app.buttons["deleteHairFixture"];reveal(remove,app);remove.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["importModelReview"].waitForExistence(timeout:20))
    }
    func testConditionedReviewShowsConflictingAttachmentMarkers() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--conditioned-model-review-test"];open(app)
        let load=app.buttons["loadPreparedModelReview"]
        XCTAssertTrue(load.waitForExistence(timeout:10));reveal(load,app);load.tap()
        status("Saved · revision 1",app)
        let legend=app.staticTexts["conflictingRootLegend"]
        XCTAssertTrue(legend.waitForExistence(timeout:45))
        XCTAssertTrue(legend.label.contains("6 attachments"))
        let clearance=app.staticTexts["faceClearanceStatus"]
        XCTAssertTrue(clearance.exists);XCTAssertEqual(clearance.label,"Review scalp attachments")
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Conditioned model attachment conflicts";shot.lifetime = .keepAlways;add(shot)
        let before=app.staticTexts["selectedHairHash"].label
        let slider=app.sliders["fringeLengthSlider"];reveal(slider,app);slider.adjust(toNormalizedSliderPosition:0.8)
        let preview=app.buttons["previewFringe"];reveal(preview,app);preview.tap()
        let error=app.staticTexts["hairLabError"]
        XCTAssertTrue(error.waitForExistence(timeout:60))
        XCTAssertTrue(error.label.contains("supplied anatomy"))
        status("Saved · revision 1",app)
        XCTAssertEqual(app.staticTexts["selectedHairHash"].label,before)
        XCTAssertFalse(app.buttons["saveHairRevision"].exists)
        let remove=app.buttons["deleteHairFixture"];reveal(remove,app);remove.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["importModelReview"].waitForExistence(timeout:20))
    }
    func testClearanceReviewIsBoundToDisplayedRevision() throws {
        continueAfterFailure=false
        let app=XCUIApplication();open(app)
        let status=app.staticTexts["faceClearanceStatus"]
        reveal(status,app);XCTAssertTrue(status.waitForExistence(timeout:30))
        let checked=app.staticTexts["faceClearanceRevision"]
        XCTAssertTrue(checked.exists)
        let first=checked.label
        let slider=app.sliders["fringeLengthSlider"];reveal(slider,app);slider.adjust(toNormalizedSliderPosition:0.5)
        let preview=app.buttons["previewFringe"];reveal(preview,app);preview.tap()
        self.status("Unsaved preview",app)
        for _ in 0..<6 { if checked.isHittable { break };app.swipeDown() }
        let changed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND label != %@",first),object:checked)
        wait(for:[changed],timeout:30)
        let previewHash=checked.label
        let compare=app.switches["compareHairOriginal"]
        for _ in 0..<6 { if compare.isHittable { break };app.swipeDown() }
        compare.tap()
        reveal(status,app);XCTAssertTrue(status.waitForExistence(timeout:30))
        let original=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND label != %@",previewHash),object:checked)
        wait(for:[original],timeout:30)
        XCTAssertFalse(app.staticTexts["faceClearanceError"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Face clearance review";shot.lifetime = .keepAlways;add(shot)
        for _ in 0..<6 { if compare.isHittable { break };app.swipeDown() }
        compare.tap();reveal(status,app)
        let restored=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@",previewHash),object:checked)
        wait(for:[restored],timeout:30)
        let discard=app.buttons["discardHairPreview"];reveal(discard,app);discard.tap()
    }
    private func reveal(_ element:XCUIElement,_ app:XCUIApplication) {
        for _ in 0..<7 { if element.isHittable { return };app.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.8)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.25))) }
        XCTAssertTrue(element.isHittable)
    }
    private func open(_ app:XCUIApplication) {
        app.launch()
        let lab=app.buttons["Capture lab"];reveal(lab,app);lab.tap()
        let link=app.buttons["openModelReview"];reveal(link,app);link.tap()
        XCTAssertTrue(app.staticTexts["hairLabNotice"].waitForExistence(timeout:15))
    }
    private func status(_ text:String,_ app:XCUIApplication) {
        expectation(for:NSPredicate(format:"label == %@",text),evaluatedWith:app.staticTexts["hairRevisionStatus"])
        waitForExpectations(timeout:90)
    }
    func testPreparedModelEditsPersistAndRejectUnsafeVolume() throws {
        continueAfterFailure=false
        let app=XCUIApplication();open(app)
        let load=app.buttons["loadPreparedModelReview"]
        XCTAssertTrue(load.waitForExistence(timeout:10));reveal(load,app);load.tap()
        status("Saved · revision 1",app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS '763 guide curves'")).firstMatch.exists)
        let original=app.staticTexts["selectedHairHash"].label
        let scene=app.descendants(matching:.any).matching(identifier:"hairGuideScene").firstMatch
        XCTAssertTrue(scene.exists);scene.swipeLeft()
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Generated model guides with captured face";shot.lifetime = .keepAlways;add(shot)
        let slider=app.sliders["fringeLengthSlider"];reveal(slider,app);slider.adjust(toNormalizedSliderPosition:0.8)
        let preview=app.buttons["previewFringe"];reveal(preview,app);preview.tap();status("Unsaved preview",app)
        let save=app.buttons["saveHairRevision"];reveal(save,app);save.tap();status("Saved · revision 2",app)
        let shortened=app.staticTexts["selectedHairHash"].label;XCTAssertNotEqual(original,shortened)
        let reduce=app.buttons["previewCrown"];reveal(reduce,app);reduce.tap()
        XCTAssertTrue(app.staticTexts["hairLabError"].waitForExistence(timeout:60))
        XCTAssertTrue(app.staticTexts["hairLabError"].label.contains("envelope"))
        status("Saved · revision 2",app);XCTAssertEqual(shortened,app.staticTexts["selectedHairHash"].label)
        let increase=app.buttons["previewMoreCrown"];reveal(increase,app);increase.tap();status("Unsaved preview",app)
        reveal(save,app);save.tap();status("Saved · revision 3",app)
        let enlarged=app.staticTexts["selectedHairHash"].label
        let undo=app.buttons["undoHairRevision"];reveal(undo,app);undo.tap();status("Saved · revision 2",app)
        XCTAssertEqual(shortened,app.staticTexts["selectedHairHash"].label)
        app.buttons["redoHairRevision"].tap();status("Saved · revision 3",app)
        app.terminate();open(app);status("Saved · revision 3",app)
        XCTAssertEqual(enlarged,app.staticTexts["selectedHairHash"].label)
        let compare=app.switches["compareHairOriginal"];reveal(compare,app);compare.tap();status("Original · revision 1",app)
        compare.tap();status("Saved · revision 3",app)
        XCTAssertFalse(app.staticTexts["hairLabError"].exists)
    }

    func testPhysicalPreparedModelCanRenderWithoutEditing() throws {
        continueAfterFailure=false
        let app=XCUIApplication();open(app)
        let load=app.buttons["loadPreparedModelReview"]
        if load.waitForExistence(timeout:5) { reveal(load,app);load.tap() }
        status("Saved · revision 1",app)
        XCTAssertFalse(app.staticTexts["hairLabError"].exists)
        let scene=app.descendants(matching:.any).matching(identifier:"hairGuideScene").firstMatch
        XCTAssertTrue(scene.exists);scene.swipeLeft()
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Model review on physical phone";shot.lifetime = .keepAlways;add(shot)
    }

    func testPreparedModelCanOpenManualAlignmentWithoutCamera() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); open(app)
        let load = app.buttons["loadPreparedModelReview"]
        if load.waitForExistence(timeout: 3) { reveal(load, app); load.tap() }
        status("Saved · revision 1", app)
        let hash = app.staticTexts["selectedHairHash"].label
        let compare = app.switches["compareHairOriginal"]
        reveal(compare, app); compare.tap()
        let alignment = app.buttons["alignModelLivePreview"]
        reveal(alignment, app); XCTAssertFalse(alignment.isEnabled)
        // Return to the saved selection before navigation.
        for _ in 0..<5 { if compare.isHittable { break }; app.swipeDown() }
        compare.tap(); reveal(alignment, app); alignment.tap()
        XCTAssertTrue(app.staticTexts["alignmentRevision"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["alignmentRevision"].label.contains(hash))
        XCTAssertTrue(app.staticTexts["alignmentPointPrompt"].label.contains("Point 1 of 7"))
        let picker = app.descendants(matching: .any).matching(identifier: "recordedFacePointPicker").firstMatch
        XCTAssertTrue(picker.exists)
        XCTAssertFalse(app.buttons["startAlignmentCamera"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Recorded-face alignment before camera"; shot.lifetime = .keepAlways; add(shot)
        // Tap a visible cheek patch; the center of this real partial scan is a
        // hole. This tests selection mechanics, not anatomical correspondence.
        picker.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["alignmentPointPrompt"].label.contains("Point 2 of 7"))
        let undo = app.buttons["Undo last point"]; reveal(undo, app); undo.tap()
        XCTAssertTrue(app.staticTexts["alignmentPointPrompt"].label.contains("Point 1 of 7"))
        XCTAssertFalse(app.buttons["continueAlignmentReference"].isEnabled)
    }

    func testSavedSimulatorModelCanBeDeleted() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure=false
        let app=XCUIApplication();open(app);status("Saved · revision 3",app)
        let remove=app.buttons["deleteHairFixture"];reveal(remove,app);remove.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["importModelReview"].waitForExistence(timeout:20))
        app.terminate();open(app)
        XCTAssertTrue(app.buttons["importModelReview"].waitForExistence(timeout:20))
        XCTAssertFalse(app.staticTexts["hairRevisionStatus"].exists)
        XCTAssertFalse(app.buttons["loadPreparedModelReview"].exists)
        #else
        throw XCTSkip("Deletion check is isolated to the simulator experiment.")
        #endif
    }
}
