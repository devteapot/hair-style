import XCTest
@testable import HairCore

final class ProceduralBaselineTests: XCTestCase {
    private func inputs() throws -> (HairDesignInput, BaselineGenerationRequest) {
        let (fixture, cut) = try SyntheticHaircut.create()
        let compiled = try DesignBriefCompiler.compile(scalp: fixture.scalp, profile: fixture.hairProfile,
            request: DesignBriefRequest(mode: .autonomous, seed: 42))
        return (compiled.input, BaselineGenerationRequest(id: UUID().uuidString,
            roots: cut.guides.map { BaselineRoot(region: $0.region, binding: $0.root) }, preferredLengthMeters: 0.12))
    }
    func testDeterministicRootBoundEditableOutputAndLengthBounds() throws {
        let (input, request) = try inputs()
        let result = try ProceduralHairBaseline.generate(input: input, request: request)
        let repeated = try ProceduralHairBaseline.generate(input: input, request: request)
        XCTAssertEqual(try HairArtifactHash.digest(result), try HairArtifactHash.digest(repeated))
        XCTAssertEqual(result.haircut.generation.origin, .proceduralBaseline)
        XCTAssertFalse(result.validation.publishableAsValidatedDesign)
        for guide in result.haircut.guides {
            XCTAssertEqual(try HaircutValidator.arcLength(guide.points), 0.12, accuracy: 1e-10)
            XCTAssertEqual(guide.points[0], try HaircutValidator.attachment(guide.root, scalp: input.scalp).position)
        }
        let edit = HairEdit(baseSHA256: try HairArtifactHash.digest(result.haircut), operation: .shortenToLength,
                            region: .fringe, value: 0.07)
        let edited = try HaircutEditor.apply(edit, to: result.haircut, input: input)
        try HaircutEditor.verifyTransition(from: result.haircut, to: edited.haircut, input: input)
        XCTAssertEqual(try HaircutValidator.arcLength(edited.haircut.guides[0].points), 0.07, accuracy: 1e-10)
    }

    func testFlowAndTextureChangeShapeAtFixedIntentSeedAndLength() throws {
        var (input, request) = try inputs()
        let base = try ProceduralHairBaseline.generate(input: input, request: request)
        let evidence = HairObservationEvidence(origin: .observed, quality: .medium,
            sourceSHA256: input.scalp.sourceSHA256, method: "fixture", methodVersion: "1", captureCondition: "dry")
        input.hairProfile.characteristics = HairCharacteristics(scalpSHA256: input.brief.scalpSHA256,
            textures: [.init(region: .fringe, value: .wavy, evidence: evidence)],
            flow: [.init(region: .fringe, meaning: .visibleArrangement, scalpLocation: request.roots[0].binding,
                         direction: Point3D(x: 1,y: 0,z: 0), evidence: evidence)], hairline: [])
        input.hairProfile.revision += 1
        input.brief.hairProfileSHA256 = try HairArtifactHash.digest(input.hairProfile)
        let changed = try ProceduralHairBaseline.generate(input: input, request: request)
        XCTAssertNotEqual(base.haircut.guides[0].points, changed.haircut.guides[0].points)
        XCTAssertEqual(base.haircut.guides[1].points, changed.haircut.guides[1].points)
        XCTAssertFalse(changed.decisions[0].fallbackDirectionUsed)
        XCTAssertEqual(changed.decisions[0].texture, .wavy)
        XCTAssertEqual(try HaircutValidator.arcLength(changed.haircut.guides[0].points), 0.12, accuracy: 1e-10)
        XCTAssertGreaterThan(changed.haircut.guides[0].points.last!.x, changed.haircut.guides[0].points.first!.x)
    }

    func testRejectsDuplicateRootsAndSuppliedIntersection() throws {
        let (input, request) = try inputs()
        var duplicate = request; duplicate.roots.append(duplicate.roots[0])
        XCTAssertThrowsError(try ProceduralHairBaseline.generate(input: input, request: duplicate))
        let p = try HaircutValidator.attachment(request.roots[0].binding, scalp: input.scalp).position
        let anatomy = GuideClearanceInput(scalpSHA256: input.brief.scalpSHA256, clearanceMeters: 0.001,
            surfaces: [ClearanceSurface(region: .face, origin: .synthetic, sourceSHA256: input.scalp.sourceSHA256[0],
                vertices: [p + Point3D(x: -0.2,y: 0,z: -0.2), p + Point3D(x: 0.2,y: 0,z: -0.2),
                           p + Point3D(x: 0,y: 0,z: 0.2)], triangles: [[0,1,2]])])
        XCTAssertThrowsError(try ProceduralHairBaseline.generate(input: input, request: request, anatomy: anatomy))
    }
}
