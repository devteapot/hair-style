import XCTest
@testable import HairCore

final class WorldRegionTests: XCTestCase {
    private var frame: FrameMetadata {
        FrameMetadata(id:"rear",imageTimestamp:1,depthTimestamp:1,imageSize:PixelSize(6,2),depthSize:PixelSize(3,1),
            intrinsics:Intrinsics(fx:10,fy:10,cx:0,cy:0,referenceSize:PixelSize(6,2)),
            depthRectification:"arkit_aligned_scene_depth",worldFromOpticalCamera:.identity,
            poseSource:"arkit_world_tracking",quality:FrameQuality(trackingState:"normal"))
    }
    private var request: WorldRegionRequest {
        .init(center:Point3D(x:0,y:0,z:0.5),radii:Point3D(x:0.06,y:0.06,z:0.06),
              selectionProvenance:.syntheticFixture,selectionMethod:"test spatial selection")
    }
    func testFixedWorldCropFollowsCameraTranslationWithoutChangingRegion() throws {
        let a = try WorldRegionMasks.evaluate(frame:frame,depth:[0.5,0.5,0.5],confidence:Data([2,2,2]),request:request)
        XCTAssertEqual(a.mask!.includedRuns.map(\.start),[0]); XCTAssertEqual(a.includedSamples,1)
        var moved = frame
        moved.worldFromOpticalCamera!.rowMajor[3] = -0.1
        let b = try WorldRegionMasks.evaluate(frame:moved,depth:[0.5,0.5,0.5],confidence:Data([2,2,2]),request:request)
        XCTAssertEqual(b.mask!.includedRuns.map(\.start),[1]); XCTAssertEqual(b.includedSamples,1)
        XCTAssertEqual(b.outsideRegionSamples,2)
        // The same world point projects to a different pixel. No anatomy is inferred.
        XCTAssertEqual(b.mask!.provenance,.syntheticFixture)
    }
    func testAllExclusionReasonsAndEmptyCropAreExplicit() throws {
        let a = try WorldRegionMasks.evaluate(frame:frame,depth:[.nan,0.5,0.5],confidence:Data([2,255,2]),request:request)
        XCTAssertNil(a.mask); XCTAssertEqual(a.invalidDepthSamples,1)
        XCTAssertEqual(a.lowConfidenceSamples,1); XCTAssertEqual(a.outsideRegionSamples,1)
        XCTAssertEqual(a.includedSamples+a.invalidDepthSamples+a.lowConfidenceSamples+a.outsideRegionSamples,3)
    }
    func testLowerPlaneUsesWorldYAndPreservesBoundary() throws {
        var r = request; r.minimumWorldY = 0
        let a = try WorldRegionMasks.evaluate(frame:frame,depth:[0.5,0.5,0.5],confidence:Data([2,2,2]),request:r)
        XCTAssertEqual(a.includedSamples,1)
        var moved = frame; moved.worldFromOpticalCamera!.rowMajor[7] = -0.01
        let b = try WorldRegionMasks.evaluate(frame:moved,depth:[0.5,0.5,0.5],confidence:Data([2,2,2]),request:r)
        XCTAssertNil(b.mask); XCTAssertEqual(b.outsideRegionSamples,3)
        r.minimumWorldY = .nan
        XCTAssertThrowsError(try WorldRegionMasks.evaluate(frame:frame,depth:[0.5,0.5,0.5],confidence:Data([2,2,2]),request:r))
    }
    func testRejectsMissingTrackingTimingAndInvalidRegion() throws {
        var f = frame; f.quality.trackingState = "limited"
        XCTAssertThrowsError(try WorldRegionMasks.evaluate(frame:f,depth:[0.5,0.5,0.5],confidence:Data([2,2,2]),request:request))
        f = frame; f.depthTimestamp = 0.9
        XCTAssertThrowsError(try WorldRegionMasks.evaluate(frame:f,depth:[0.5,0.5,0.5],confidence:Data([2,2,2]),request:request))
        var r = request; r.radii.x = 0
        XCTAssertThrowsError(try WorldRegionMasks.evaluate(frame:frame,depth:[0.5,0.5,0.5],confidence:Data([2,2,2]),request:r))
        f = frame; f.depthRectification = "not_applied"
        XCTAssertThrowsError(try WorldRegionMasks.evaluate(frame:f,depth:[0.5,0.5,0.5],confidence:Data([2,2,2]),request:request))
    }
    func testBundleReplaySkipsTrackingFailureAndRejectsCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let bundle = try SyntheticCapture.create(in:root)
        var manifest = try CaptureBundle.load(bundle)
        // Simulate the rear metadata convention; the source remains explicitly synthetic.
        for i in manifest.frames.indices {
            manifest.frames[i].metadata.depthRectification = "arkit_aligned_scene_depth"
            manifest.frames[i].metadata.poseSource = "arkit_world_tracking"
            manifest.frames[i].metadata.quality.trackingState = i == 0 ? "initializing" : "normal"
        }
        try ManifestCoding.encoder().encode(manifest).write(to:bundle.appendingPathComponent("manifest.json"))
        let report = try WorldRegionMasks.build(bundle:bundle,request:request)
        XCTAssertFalse(report.acceptedForFusion)
        XCTAssertNotNil(report.frames[0].skippedReason); XCTAssertNil(report.frames[0].mask)
        XCTAssertEqual(report.frames[1].frameSHA256.count,64)
        XCTAssertGreaterThan(report.frames[1].includedSamples,0)
        let payload = bundle.appendingPathComponent(manifest.frames[1].depth!.path)
        try Data([0]).write(to:payload)
        XCTAssertThrowsError(try WorldRegionMasks.build(bundle:bundle,request:request))
    }
}
