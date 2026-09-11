import XCTest
@testable import HairCore

final class HeadPoseRegistrationTests: XCTestCase {
    private let anchor = UUID().uuidString
    private func frame(_ transform: RigidTransform, time: Double) -> FrameMetadata {
        var m = FrameMetadata(imageTimestamp: time, depthTimestamp: time, imageSize: PixelSize(64,48))
        m.headPose = HeadPoseEvidence(headFromOpticalCamera: transform, timestamp: time, anchorID: anchor)
        m.quality.headPoseAvailable = true
        return m
    }

    func testRelativeDirectionPreservesHeadPointWithRotationAndTranslation() throws {
        let source = frame(RigidTransform(rowMajor:[1,0,0,0.1, 0,1,0,0.2, 0,0,1,0.3, 0,0,0,1]), time:1)
        let target = frame(RigidTransform(rowMajor:[0,-1,0,0.2, 1,0,0,0.4, 0,0,1,0.1, 0,0,0,1]), time:2)
        let relative = try HeadPoseRegistration.relativeTransform(source:source,target:target)
        let p = Point3D(x:0.3,y:0.2,z:0.5), mapped = relative.apply(p)
        XCTAssertEqual(mapped.x,0,accuracy:1e-12)
        XCTAssertEqual(mapped.y,-0.2,accuracy:1e-12)
        XCTAssertEqual(mapped.z,0.7,accuracy:1e-12)
        XCTAssertLessThan((target.headPose!.headFromOpticalCamera.apply(mapped)-source.headPose!.headFromOpticalCamera.apply(p)).length,1e-12)
        let inverse = try HeadPoseRegistration.relativeTransform(source:target,target:source)
        XCTAssertLessThan((inverse.apply(mapped)-p).length,1e-12)
    }

    func testMissingChangedMirroredOrMistimedEvidenceIsRejected() throws {
        let source = frame(.identity,time:1)
        var target = frame(.identity,time:2)
        target.headPose?.anchorID = UUID().uuidString
        XCTAssertThrowsError(try HeadPoseRegistration.relativeTransform(source:source,target:target))
        target = frame(.identity,time:2); target.headPose = nil; target.quality.headPoseAvailable = false
        XCTAssertThrowsError(try HeadPoseRegistration.relativeTransform(source:source,target:target))
        target = frame(.identity,time:2); target.depthTimestamp = 1.9
        XCTAssertThrowsError(try HeadPoseRegistration.relativeTransform(source:source,target:target))
        target = frame(.identity,time:2); target.mirrored = true
        XCTAssertThrowsError(try HeadPoseRegistration.relativeTransform(source:source,target:target))
    }

    func testBundleReplayRetainsOutlierAndNeverFitsToValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let bundle = try SyntheticCapture.create(in:root,kind:.frontFace)
        var manifest = try CaptureBundle.load(bundle)
        var request = HeadPoseRegistrationRequest(sourceFrameID:manifest.frames[0].metadata.id,
            targetFrameID:manifest.frames[1].metadata.id, validationPairs:[
                .init(id:"a",source:.init(x:30,y:20),target:.init(x:30,y:20)),
                .init(id:"b",source:.init(x:40,y:30),target:.init(x:40,y:30)),
                .init(id:"outlier",source:.init(x:50,y:35),target:.init(x:20,y:35))])
        XCTAssertThrowsError(try HeadPoseRegistration.inspect(bundle:bundle,request:request))
        for i in 0..<2 {
            var pose = RigidTransform.identity; pose.rowMajor[3] = Double(i)*0.01
            manifest.frames[i].metadata.headPose = HeadPoseEvidence(headFromOpticalCamera:pose,
                timestamp:manifest.frames[i].metadata.imageTimestamp,anchorID:anchor)
            manifest.frames[i].metadata.quality.headPoseAvailable = true
        }
        try ManifestCoding.encoder().encode(manifest).write(to:bundle.appendingPathComponent("manifest.json"))
        let report = try HeadPoseRegistration.inspect(bundle:bundle,request:request)
        XCTAssertFalse(report.acceptedForFusion)
        XCTAssertEqual(report.evidenceSource,.syntheticFixture)
        XCTAssertEqual(report.validationResiduals.count,3)
        XCTAssertEqual(report.validationMedianMeters,0.01,accuracy:1e-7)
        XCTAssertGreaterThan(report.validationP95Meters,0.2)
        XCTAssertEqual(report.sourceFrameSHA256.count,64)
        request.validationPairs[2].target.x = 50
        let corrected = try HeadPoseRegistration.inspect(bundle:bundle,request:request)
        XCTAssertEqual(report.targetFromSource,corrected.targetFromSource)
        XCTAssertNotEqual(report.requestSHA256,corrected.requestSHA256)
        XCTAssertEqual(corrected.validationP95Meters,0.01,accuracy:1e-7)
        request.validationPairs[2].source = request.validationPairs[0].source
        XCTAssertThrowsError(try HeadPoseRegistration.inspect(bundle:bundle,request:request))
        let depth = manifest.frames[0].depth!
        try Data([0]).write(to:bundle.appendingPathComponent(depth.path))
        request.validationPairs[2].source = .init(x:50,y:35)
        XCTAssertThrowsError(try HeadPoseRegistration.inspect(bundle:bundle,request:request))
    }
}
