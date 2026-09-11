import XCTest
@testable import HairCore

final class ObservedSurfaceTests: XCTestCase {
    private func mask(excluding: Set<Int> = []) -> SurfaceMask {
        var runs: [MaskRun] = []
        for i in 0..<(64*48) where !excluding.contains(i) {
            if let last = runs.last, last.start + last.count == i { runs[runs.count-1].count += 1 }
            else { runs.append(MaskRun(start: i, count: 1)) }
        }
        return SurfaceMask(size: PixelSize(64,48), provenance: .syntheticFixture,
                           method: "test inclusion mask", includedRuns: runs)
    }
    private func item(_ url: URL, mask: SurfaceMask) throws -> SurfaceFrameRequest {
        let m = try CaptureBundle.load(url)
        return SurfaceFrameRequest(captureID: m.id, frameID: m.frames[0].metadata.id, mask: mask)
    }
    private func selection(source: String, target: String) -> CaptureLandmarkSelection {
        func p(_ x: Double, _ y: Double, _ id: String) -> PixelLandmarkPair {
            PixelLandmarkPair(id: id, source: PixelPoint(x:x,y:y), target: PixelPoint(x:x,y:y))
        }
        return CaptureLandmarkSelection(sourceFrameID: source, targetFrameID: target,
            fitPairs: [p(10,10,"a"), p(40,10,"b"), p(10,35,"c"), p(40,35,"d")],
            validationPairs: [p(15,12,"e"), p(50,12,"f"), p(30,40,"g")])
    }

    func testPreservesHolesAndDepthDiscontinuitiesWithFiniteOrientedMesh() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try SyntheticCapture.create(in: root)
        let hole = 31*64+31 // intentionally between coarse samples
        var request = SurfaceRequest(frames: [try item(bundle, mask: mask(excluding: [hole]))])
        request.maximumEdgeMeters = 0.03
        let result = try ObservedSurfaceBuilder.build(captureRoot: root, request: request)
        XCTAssertGreaterThan(result.triangles.count, 500)
        XCTAssertFalse(result.completeHead); XCTAssertFalse(result.includesInferredAnatomy)
        XCTAssertEqual(result.source, .syntheticFixture)
        for v in result.vertices {
            XCTAssertTrue(v.position.finite); XCTAssertTrue(v.normal.finite)
            XCTAssertEqual(v.normal.z, -1, accuracy: 1e-8)
            XCTAssertNotEqual(v.observations[0].depthPixelIndex % 64, 0)
            XCTAssertNotEqual(v.observations[0].depthPixelIndex, hole)
        }
        for face in result.triangles {
            let points = face.map { result.vertices[$0].position }
            XCTAssertLessThan(points.map(\.z).max()! - points.map(\.z).min()!, 0.001)
            let pixels = face.map { result.vertices[$0].observations[0].depthPixelIndex }
            let xs = pixels.map { $0 % 64 }, ys = pixels.map { $0 / 64 }
            XCTAssertFalse(xs.min()! <= 31 && xs.max()! >= 31 && ys.min()! <= 31 && ys.max()! >= 31,
                           "Coarse triangles must not cover an excluded interior sample")
        }
        let text = String(decoding: result.ply(), as: UTF8.self)
        XCTAssertTrue(text.contains("element face \(result.triangles.count)"))
        XCTAssertEqual(result.frames[0].maskSHA256.count, 64)
    }

    func testRegisteredDuplicateViewsFuseAndKeepBothObservations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let front = try SyntheticCapture.create(in: root, kind: .frontFace)
        let rear = try SyntheticCapture.create(in: root, kind: .rearHead)
        let reference = try item(front, mask: mask())
        var contributor = try item(rear, mask: mask())
        contributor.registrationToReference = selection(source: contributor.frameID, target: reference.frameID)
        var request = SurfaceRequest(frames: [reference]); request.samplingStride = 1
        let single = try ObservedSurfaceBuilder.build(captureRoot: root, request: request)
        request.frames.append(contributor)
        let fused = try ObservedSurfaceBuilder.build(captureRoot: root, request: request)
        XCTAssertEqual(fused.vertices.count, single.vertices.count)
        XCTAssertEqual(fused.triangles.count, single.triangles.count)
        XCTAssertTrue(fused.vertices.allSatisfy { Set($0.observations.map(\.frameIndex)) == [0,1] })
        XCTAssertTrue(fused.frames[1].registration!.registration.accepted)
        XCTAssertEqual(fused.frames[1].registration!.targetFrameSHA256, fused.frames[0].frameSHA256)
        XCTAssertNotEqual(fused.requestSHA256, single.requestSHA256)
        request.frames[1].registrationToReference = nil
        XCTAssertThrowsError(try ObservedSurfaceBuilder.build(captureRoot: root, request: request))
        request.frames[1] = contributor
        request.frames[1].registrationToReference!.validationPairs[0].target.x += 5
        XCTAssertThrowsError(try ObservedSurfaceBuilder.build(captureRoot: root, request: request))
        request.frames[1] = contributor
        request.frames[0].mask = mask(excluding: [10*64+10])
        XCTAssertThrowsError(try ObservedSurfaceBuilder.build(captureRoot: root, request: request))
        request.frames[0] = reference
        var foreign = try CaptureBundle.load(rear); foreign.subjectSessionID = "another-subject"
        try ManifestCoding.encoder().encode(foreign).write(to: rear.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try ObservedSurfaceBuilder.build(captureRoot: root, request: request))
    }

    func testRejectsMalformedMasksAndTamperedEvidence() throws {
        var bad = mask(); bad.includedRuns = [MaskRun(start: 0,count: 10), MaskRun(start: 9,count: 2)]
        XCTAssertThrowsError(try bad.decode())
        bad.includedRuns = [MaskRun(start: 64*48-1,count: Int.max)]
        XCTAssertThrowsError(try bad.decode())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try SyntheticCapture.create(in: root)
        var request = SurfaceRequest(frames: [try item(bundle, mask: mask())])
        request.frames[0].captureID = "../outside"
        XCTAssertThrowsError(try ObservedSurfaceBuilder.build(captureRoot: root, request: request))
        request.frames[0] = try item(bundle, mask: mask())
        let manifest = try CaptureBundle.load(bundle)
        try Data([0]).write(to: bundle.appendingPathComponent(manifest.frames[0].depth!.path))
        XCTAssertThrowsError(try ObservedSurfaceBuilder.build(captureRoot: root, request: request))
    }

    func testExtremeCalibrationFailsWithoutQuantizationCrash() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try SyntheticCapture.create(in: root)
        let request = SurfaceRequest(frames: [try item(bundle, mask: mask())])
        var m = try CaptureBundle.load(bundle)
        m.frames[0].metadata.intrinsics!.fx = Double.leastNormalMagnitude
        try ManifestCoding.encoder().encode(m).write(to: bundle.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try ObservedSurfaceBuilder.build(captureRoot: root, request: request))
    }
}
