import XCTest
@testable import HairCore

final class ProjectiveFusionTests: XCTestCase {
    func testDenoisingCannotHideRawFreeSpaceContradiction() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        var request=try fixture(root:root,freeSpaceOutlier:true)
        request.truncationMeters=0.01;request.maximumSignedDistanceSpreadMeters=0.012
        let raw=try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:request)
        request.depthDenoising = .init()
        let filtered=try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:request)
        XCTAssertGreaterThan(filtered.counts["disagreementNodes"]!,0)
        XCTAssertEqual(filtered.counts["disagreementNodes"],raw.counts["disagreementNodes"])
        XCTAssertEqual(filtered.counts["retainedNodes"],raw.counts["retainedNodes"])
        XCTAssertEqual(filtered.vertices.map(\.position),raw.vertices.map(\.position))
    }
    func testOptionalDenoisingPreservesRawEvidenceAndMissingHole() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        var request=try fixture(root:root,hole:true)
        let raw=try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:request)
        request.depthDenoising = .init()
        let filtered=try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:request)
        XCTAssertEqual(filtered.method,"masked_denoised_projective_tsdf_v1")
        XCTAssertEqual(filtered.sourceSurfaceSHA256,raw.sourceSurfaceSHA256)
        XCTAssertEqual(filtered.triangles,raw.triangles)
        XCTAssertEqual(filtered.vertices.map(\.position),raw.vertices.map(\.position))
        XCTAssertEqual(filtered.counts["denoisingAdjustedPixels"],0)
        XCTAssertNotEqual(filtered.requestSHA256,raw.requestSHA256)
        XCTAssertFalse(filtered.suitableForHaircutFitting)
    }
    private func fixture(root: URL, hole: Bool = false, conflict: Bool = false, freeSpaceOutlier: Bool = false) throws -> ProjectiveFusionRequest {
        let seed = try SyntheticCapture.create(in:root)
        let seedManifest = try CaptureBundle.load(seed)
        let jpeg = try CaptureBundle.payload(seedManifest.frames[0].image,in:seed)
        let writer = try CaptureBundleWriter(root:root,subjectSessionID:"tsdf-fixture",kind:.frontFace,
            source:.syntheticFixture,device:seedManifest.device,consentVersion:"synthetic-no-person")
        let size = PixelSize(64,48)
        for i in 0..<(freeSpaceOutlier ? 3 : 2) {
            let frame = FrameMetadata(imageTimestamp:Double(i+1),depthTimestamp:Double(i+1),imageSize:size,depthSize:size,
                intrinsics:Intrinsics(fx:60,fy:60,cx:31.5,cy:23.5,referenceSize:size),depthRectification:"synthetic_pinhole")
            var depth = [Float](repeating:0.5,count:64*48)
            if (conflict || freeSpaceOutlier) && i == 1 { for y in 23...29 { for x in 37...43 { depth[y*64+x] = freeSpaceOutlier ? 0.54 : 0.52 } } }
            try writer.append(metadata:frame,imageJPEG:jpeg,depth:DepthGeometry.encode(depth),confidence:Data(repeating:2,count:depth.count))
        }
        try writer.finish()
        let manifest = try CaptureBundle.load(writer.url)
        var runs:[MaskRun] = []
        for y in 8...42 { for x in 24...56 {
            if hole && (23...29).contains(y) && (37...43).contains(x) { continue }
            let pixel=y*64+x
            if let last = runs.last, last.start+last.count == pixel { runs[runs.count-1].count += 1 }
            else { runs.append(MaskRun(start:pixel,count:1)) }
        } }
        let mask=SurfaceMask(size:size,provenance:.syntheticFixture,method:"Synthetic plane support",includedRuns:runs)
        var frames=manifest.frames.map { SurfaceFrameRequest(captureID:manifest.id,frameID:$0.metadata.id,mask:mask) }
        func pair(_ id:String,_ x:Double,_ y:Double)->PixelLandmarkPair {
            PixelLandmarkPair(id:id,source:PixelPoint(x:x,y:y),target:PixelPoint(x:x,y:y))
        }
        for i in 1..<frames.count {
        frames[i].registrationToReference=CaptureLandmarkSelection(sourceFrameID:frames[i].frameID,targetFrameID:frames[0].frameID,
            fitPairs:[pair("a",28,12),pair("b",52,12),pair("c",28,38),pair("d",52,38)],
            validationPairs:[pair("e",32,18),pair("f",48,18),pair("g",38,35)])
        }
        var surface=SurfaceRequest(frames:frames);surface.samplingStride=1;surface.maximumEdgeMeters=0.03
        var request=ProjectiveFusionRequest(surfaceRequest:surface);request.voxelMeters=0.005;request.truncationMeters=0.015
        return request
    }
    func testCaptureBackedPlaneRemainsMetricAndDoesNotCloseExcludedHole() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let request=try fixture(root:root,hole:true)
        let result=try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:request)
        XCTAssertGreaterThan(result.triangles.count,500)
        XCTAssertEqual(result.topology.nonManifoldEdges,0);XCTAssertEqual(result.topology.inconsistentWindingEdges,0)
        XCTAssertFalse(result.completeHead);XCTAssertFalse(result.suitableForHaircutFitting)
        XCTAssertEqual(result.source,.syntheticFixture)
        XCTAssertTrue(result.frames[1].registration!.registration.accepted)
        for v in result.vertices {
            XCTAssertEqual(v.position.z,0.5,accuracy:1e-8);XCTAssertLessThan(v.normal.z,-0.99)
        }
        for t in result.triangles {
            let c=t.map{result.vertices[$0].position}.reduce(.zero,+)/3
            XCTAssertFalse(abs(c.x-0.07083333)<0.015 && abs(c.y-0.02083333)<0.015,"The known missing interior must remain open")
        }
        XCTAssertGreaterThan(result.counts["maskedOrInvalidSamples"]!,0)
    }
    func testConflictingDepthDoesNotProduceAnAverageGhostSurface() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let request=try fixture(root:root,conflict:true)
        let result=try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:request)
        XCTAssertGreaterThan(result.counts["disagreementNodes"]!,0)
        XCTAssertGreaterThan(result.counts["occludedSamples"]!,0)
        XCTAssertGreaterThan(result.counts["farFreeSpaceSamples"]!,0)
        for t in result.triangles {
            let c=t.map{result.vertices[$0].position}.reduce(.zero,+)/3
            XCTAssertFalse(abs(c.x-0.07083333)<0.012 && abs(c.y-0.02083333)<0.012)
        }
    }
    func testFarFreeSpaceCannotHideBehindTruncation() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        var request=try fixture(root:root,freeSpaceOutlier:true)
        request.truncationMeters=0.01;request.maximumSignedDistanceSpreadMeters=0.012
        let result=try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:request)
        XCTAssertGreaterThan(result.counts["disagreementNodes"]!,0)
        for t in result.triangles {
            let c=t.map{result.vertices[$0].position}.reduce(.zero,+)/3
            XCTAssertFalse(abs(c.x-0.07083333)<0.012 && abs(c.y-0.02083333)<0.012,
                           "Two agreeing views must not hide a third view's 40 mm contradiction by truncating it to 10 mm")
        }
    }
    func testRejectsInvalidBoundsMissingRegistrationAndChangedCapture() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let request=try fixture(root:root)
        var bad=request;bad.surfaceRequest.frames=[]
        XCTAssertThrowsError(try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:bad))
        bad=request;bad.minimumNearSurfaceViews=3
        XCTAssertThrowsError(try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:bad))
        bad=request;bad.voxelMeters = .nan
        XCTAssertThrowsError(try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:bad))
        bad=request;bad.surfaceRequest.frames[1].registrationToReference=nil
        XCTAssertThrowsError(try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:bad))
        let bundle=root.appendingPathComponent(request.surfaceRequest.frames[0].captureID)
        let manifest=try CaptureBundle.load(bundle)
        try Data([0]).write(to:bundle.appendingPathComponent(manifest.frames[0].depth!.path))
        XCTAssertThrowsError(try ProjectiveSurfaceFusion.rebuild(captureRoot:root,request:request))
    }
}
