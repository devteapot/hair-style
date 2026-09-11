import XCTest
@testable import HairCore

final class LiveHairTests: XCTestCase {
    private func calibration() throws -> (ScalpProfile, LiveHairCalibration) {
        let (input, _) = try SyntheticHaircut.create()
        let points = [Point3D(x: -0.04,y: 0.01,z: 0.02), Point3D(x: 0.04,y: 0.01,z: 0.02),
            Point3D(x: 0,y: -0.04,z: 0.03), Point3D(x: 0.01,y: 0.05,z: 0.01),
            Point3D(x: -0.03,y: -0.02,z: 0.01), Point3D(x: 0.03,y: -0.02,z: 0.01),
            Point3D(x: 0,y: 0.03,z: 0.04)]
        let transform = RigidTransform(rowMajor: [1,0,0,0.01, 0,1,0,0.02, 0,0,1,-0.03, 0,0,0,1])
        let pairs = points.enumerated().map { LandmarkPair(id: "p\($0.offset)", source: $0.element, target: transform.apply($0.element)) }
        let request = LiveCalibrationRequest(scalpSHA256: try HairArtifactHash.digest(input.scalp),
            trackingSessionID: UUID().uuidString, anchorID: UUID().uuidString,
            landmarkEvidenceSHA256: input.scalp.sourceSHA256[0],
            registration: RegistrationInput(sourceFrameID: "personal_canonical", targetFrameID: "ar_face_local",
                evidenceSource: .syntheticFixture, fitPairs: Array(pairs.prefix(4)), validationPairs: Array(pairs.suffix(3))))
        return (input.scalp, try LiveHairAlignment.calibrate(request, scalp: input.scalp))
    }
    func testCompositionAppliesCalibrationBeforeWorldPoseAndRejectsTampering() throws {
        let (scalp, calibration) = try calibration()
        let world = RigidTransform(rowMajor: [0,-1,0,0.1, 1,0,0,0.2, 0,0,1,0.3, 0,0,0,1])
        let point = Point3D(x: 0.02,y: 0.03,z: 0.04)
        let result = try LiveHairAlignment.worldFromCanonical(worldFromFace: world, calibration: calibration)
        XCTAssertLessThan((result.apply(point) - world.apply(calibration.registration.targetFromSource.apply(point))).length, 1e-10)
        var forged = calibration; forged.registration.targetFromSource = .identity
        XCTAssertThrowsError(try LiveHairTracker(calibration: forged, scalp: scalp))
        var bad = calibration.request; bad.registration.validationPairs[0].target.x += 0.05
        XCTAssertThrowsError(try LiveHairAlignment.calibrate(bad, scalp: scalp))
    }
    func testAcquisitionLossWatchdogLateFramesAndAnchorChange() throws {
        let (scalp, calibration) = try calibration()
        var tracker = try LiveHairTracker(calibration: calibration, scalp: scalp)
        var sample = LiveFaceSample(trackingSessionID: calibration.request.trackingSessionID,
            anchorID: calibration.request.anchorID, timestamp: 1, tracked: true, worldFromFace: .identity)
        for i in 0..<3 { sample.timestamp = 1 + Double(i)*0.01; try tracker.update(sample) }
        XCTAssertEqual(tracker.presentation(now: 1.03).state, .visible)
        sample.timestamp = 1; sample.tracked = false; try tracker.update(sample)
        XCTAssertEqual(tracker.presentation(now: 1.04).state, .visible)
        XCTAssertNil(tracker.presentation(now: 1.3).worldFromCanonical)
        sample.tracked = true
        for i in 0..<2 { sample.timestamp = 1.31 + Double(i)*0.01; try tracker.update(sample) }
        XCTAssertEqual(tracker.presentation(now: 1.33).state, .acquiring)
        sample.timestamp = 1.34; try tracker.update(sample)
        XCTAssertEqual(tracker.presentation(now: 1.34).state, .visible)
        sample.anchorID = UUID().uuidString; sample.timestamp = 1.35; try tracker.update(sample)
        XCTAssertEqual(tracker.presentation(now: 1.35).state, .recalibrationRequired)
        _ = tracker.presentation(now: .nan)
        sample.anchorID = calibration.request.anchorID; sample.timestamp = 1.36; try tracker.update(sample)
        XCTAssertEqual(tracker.presentation(now: 1.36).state, .recalibrationRequired)
    }
    func testPoseJumpAndInterruptionRequireFreshCalibration() throws {
        let (scalp, calibration) = try calibration()
        var tracker = try LiveHairTracker(calibration: calibration, scalp: scalp)
        var sample = LiveFaceSample(trackingSessionID: calibration.request.trackingSessionID,
            anchorID: calibration.request.anchorID, timestamp: 1, tracked: true, worldFromFace: .identity)
        try tracker.update(sample)
        sample.timestamp = 1.01
        sample.worldFromFace = RigidTransform(rowMajor: [1,0,0,0.5, 0,1,0,0, 0,0,1,0, 0,0,0,1])
        try tracker.update(sample)
        XCTAssertEqual(tracker.presentation(now: 1.01).state, .recalibrationRequired)
        tracker = try LiveHairTracker(calibration: calibration, scalp: scalp)
        tracker.interrupt()
        try tracker.update(sample)
        XCTAssertNil(tracker.presentation(now: 1.01).worldFromCanonical)
    }
    func testMultipleFacesLatchEvenWhenCalibratedAnchorRemains() throws {
        let (scalp, calibration) = try calibration()
        var tracker = try LiveHairTracker(calibration: calibration, scalp: scalp)
        var sample = LiveFaceSample(trackingSessionID: calibration.request.trackingSessionID,
            anchorID: calibration.request.anchorID, timestamp: 1, tracked: true, worldFromFace: .identity)
        for i in 0..<3 { sample.timestamp = 1 + Double(i)*0.01; try tracker.update(sample) }
        XCTAssertEqual(tracker.presentation(now: 1.02).state, .visible)
        sample.timestamp = 1.03; sample.faceCount = 2; try tracker.update(sample)
        XCTAssertNil(tracker.presentation(now: 1.03).worldFromCanonical)
        sample.faceCount = 1
        for i in 0..<5 { sample.timestamp = 1.04 + Double(i)*0.01; try tracker.update(sample) }
        XCTAssertEqual(tracker.presentation(now: 1.09).state, .recalibrationRequired)
        tracker = try LiveHairTracker(calibration: calibration, scalp: scalp)
        sample.timestamp = 2; sample.faceCount = 0; try tracker.update(sample)
        XCTAssertEqual(tracker.presentation(now: 2).state, .trackingLost)
    }

}
