import XCTest
@testable import HairCore

final class LiveReviewCorrespondencesTests: XCTestCase {
    private struct Fixture {
        var input: HairDesignInput
        var haircut: HaircutRevision
        var observed: CanonicalObservedSurface
        var reference: LiveFaceReference
        var pairs: [LiveReviewPointPair]
        func prepare() throws -> LiveReviewAlignmentResult {
            try LiveReviewCorrespondences.prepare(input: input, haircut: haircut, observed: observed, reference: reference, pairs: pairs)
        }
    }
    private func fixture() throws -> Fixture {
        // Eight synthetic points; no measured anatomical accuracy is asserted.
        let points = [Point3D(x: 0, y: -0.01, z: 0.025), Point3D(x: 0, y: -0.09, z: 0.005),
                      Point3D(x: 0.03, y: 0, z: 0), Point3D(x: -0.03, y: 0, z: 0),
                      Point3D(x: 0.02, y: -0.05, z: 0.015), Point3D(x: -0.02, y: -0.05, z: 0.015),
                      Point3D(x: 0, y: 0.005, z: 0.01), Point3D(x: 0, y: 0.05, z: 0)]
        let triangles = [[0,1,4], [0,5,1], [0,2,4], [0,5,3], [0,3,6], [0,6,2], [6,3,7], [6,7,2]]
        let vertices = points.enumerated().map { SurfaceVertex(position: $0.element + Point3D(x: 0, y: 0, z: 0.5),
            normal: Point3D(x: 0, y: 0, z: 1), observations: [SurfaceObservation(frameIndex: 0, depthPixelIndex: $0.offset)]) }
        let evidence = SurfaceFrameEvidence(captureID: UUID().uuidString, frameID: UUID().uuidString,
            frameSHA256: String(repeating: "a", count: 64), maskSHA256: String(repeating: "b", count: 64),
            source: .syntheticFixture, referenceFromCamera: .identity, registration: nil, retainedSamples: 8, skippedSamples: 0)
        let source = ObservedSurface(requestSHA256: String(repeating: "c", count: 64), source: .syntheticFixture,
            vertices: vertices, triangles: triangles, frames: [evidence], notes: ["Synthetic alignment test"])
        let selection = AnatomicalSelection(surfaceSHA256: try HairArtifactHash.digest(source), anatomicalLeftEyeVertex: 2,
            anatomicalRightEyeVertex: 3, superiorVertex: 7, anteriorVertex: 0, method: "Synthetic selection")
        let observed = try AnatomicalFrame.canonicalize(source, selection: selection)
        var (input, haircut) = try SyntheticHaircut.create()
        input.scalp.sourceSHA256.append(try HairArtifactHash.digest(observed))
        input.brief.scalpSHA256 = try HairArtifactHash.digest(input.scalp)
        haircut.scalpSHA256 = input.brief.scalpSHA256
        haircut.briefSHA256 = try HairArtifactHash.digest(input.brief)
        // Independently specified rigid rotation and translation, not a fit.
        let target = observed.vertices.map { vertex in
            let p = vertex.position
            return Point3D(x: -p.y + 0.012, y: p.x - 0.02, z: p.z + 0.003)
        }
        return Fixture(input: input, haircut: haircut, observed: observed,
            reference: LiveFaceReference(vertices: target, triangles: triangles),
            pairs: (0..<7).map { LiveReviewPointPair(observedVertex: $0, faceVertex: $0) })
    }

    func testSelectedEditedRevisionHasIdenticalMeshInReviewAndLive() throws {
        var value = try fixture()
        let original = value.haircut
        let edit = HairEdit(baseSHA256: try HairArtifactHash.digest(original), operation: .shortenToLength, region: .fringe, value: 0.04)
        value.haircut = try HaircutEditor.apply(edit, to: original, input: value.input).haircut
        let result = try value.prepare()
        XCTAssertEqual(result.package.haircut.revision, 2)
        XCTAssertEqual(try HairArtifactHash.digest(result.package.haircut), try HairArtifactHash.digest(value.haircut))
        XCTAssertEqual(result.referenceRegistration.validationResiduals.count, 3)
        XCTAssertLessThan(result.referenceRegistration.validationP95Meters, 1e-10)
        let expected = try HairMeshCompiler.compile(input: value.input, haircut: value.haircut, radialSides: 3, radiusScale: 8)
        let decoded = try ManifestCoding.decoder().decode(LivePreviewPackage.self, from: ManifestCoding.encoder().encode(result.package))
        XCTAssertEqual(try HairArtifactHash.digest(decoded.prepareMesh()), try HairArtifactHash.digest(expected))
        XCTAssertEqual(decoded.faceVertexCount, value.reference.vertices.count)
        try decoded.validateTrackerTopology(vertexCount: value.reference.vertices.count, triangles: value.reference.triangles)
    }

    func testHeldOutPointMismatchCannotBeHiddenByFittingOrScaling() throws {
        var value = try fixture()
        value.reference.vertices[4].x += 0.03
        XCTAssertThrowsError(try value.prepare())
        value = try fixture()
        value.reference.vertices = value.reference.vertices.map { $0 * 1.5 }
        XCTAssertThrowsError(try value.prepare())
    }

    func testRejectsOtherFaceDuplicateOutOfRangeAndUnobservedPoints() throws {
        var value = try fixture()
        value.observed.vertices[0].position.x += 0.001
        XCTAssertThrowsError(try value.prepare())
        value = try fixture(); value.pairs[6] = value.pairs[0]
        XCTAssertThrowsError(try value.prepare())
        value = try fixture(); value.pairs[0].observedVertex = Int.max
        XCTAssertThrowsError(try value.prepare())
        value = try fixture(); value.pairs[0].faceVertex = -1
        XCTAssertThrowsError(try value.prepare())
        value = try fixture(); value.pairs.removeLast()
        XCTAssertThrowsError(try value.prepare())
        value = try fixture(); value.reference.triangles[0][0] = Int.max
        XCTAssertThrowsError(try value.prepare())
    }

    func testChangedTrackerTopologyAndOversizeMeshSettingsFailClosed() throws {
        let value = try fixture()
        var package = try value.prepare().package
        var triangles = value.reference.triangles
        triangles[0].swapAt(0, 1)
        XCTAssertThrowsError(try package.validateTrackerTopology(vertexCount: value.reference.vertices.count, triangles: triangles))
        XCTAssertThrowsError(try package.validateTrackerTopology(vertexCount: value.reference.vertices.count + 1, triangles: value.reference.triangles))
        package.faceVertexCount = nil
        XCTAssertThrowsError(try package.prepareMesh())
        package = try value.prepare().package
        package.meshSettings = LiveMeshSettings(radialSides: 200, radiusScale: 8)
        XCTAssertThrowsError(try package.prepareMesh())
        package = try value.prepare().package
        package.meshSettings = LiveMeshSettings(radialSides: 3, radiusScale: .nan)
        XCTAssertThrowsError(try package.prepareMesh())
    }
}
