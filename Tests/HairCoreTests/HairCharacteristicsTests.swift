import XCTest
@testable import HairCore

final class HairCharacteristicsTests: XCTestCase {
    private func sample(_ input: HairDesignInput) throws -> HairCharacteristics {
        let evidence = HairObservationEvidence(origin: .observed, quality: .medium,
            sourceSHA256: input.scalp.sourceSHA256, method: "synthetic evidence", methodVersion: "1", captureCondition: "dry")
        return HairCharacteristics(scalpSHA256: try HairArtifactHash.digest(input.scalp),
            textures: [RegionalTextureObservation(region: .fringe, value: .wavy, evidence: evidence)],
            flow: [HairFlowObservation(region: .fringe, meaning: .visibleArrangement,
                scalpLocation: ScalpBinding(triangleIndex: 0, barycentric: [0.2,0.3,0.5], normalOffsetMeters: 0),
                direction: Point3D(x: 1,y: 0,z: 0), evidence: evidence)],
            hairline: [HairlineObservation(region: .fringe, anchors: [
                ScalpBinding(triangleIndex: 0, barycentric: [0.2,0.3,0.5], normalOffsetMeters: 0),
                ScalpBinding(triangleIndex: 0, barycentric: [0.25,0.3,0.45], normalOffsetMeters: 0)], evidence: evidence)])
    }

    func testCharacteristicsSurviveCompilationAndInvalidateOldDesign() throws {
        var (input, haircut) = try SyntheticHaircut.create()
        let oldHash = try HairArtifactHash.digest(input.hairProfile)
        input.hairProfile.characteristics = try sample(input)
        input.hairProfile.revision += 1
        let result = try DesignBriefCompiler.compile(scalp: input.scalp, profile: input.hairProfile,
            request: DesignBriefRequest(mode: .autonomous, seed: 42))
        XCTAssertNotEqual(oldHash, result.input.brief.hairProfileSHA256)
        XCTAssertEqual(result.input.hairProfile.characteristics?.textures.first?.value, .wavy)
        XCTAssertThrowsError(try HaircutValidator.validate(input: result.input, haircut: haircut))
        let encoded = try ManifestCoding.encoder().encode(result)
        let restored = try ManifestCoding.decoder().decode(CompiledDesignBrief.self, from: encoded)
        XCTAssertEqual(try HairArtifactHash.digest(restored), try HairArtifactHash.digest(result))
    }

    func testRejectsInventedRootsStaleScalpAndNonTangentDirections() throws {
        let (input, _) = try SyntheticHaircut.create()
        var value = try sample(input)
        try HairCharacteristicsValidator.validate(value, scalp: input.scalp)
        value.flow[0].meaning = .estimatedRootGrowth
        XCTAssertThrowsError(try HairCharacteristicsValidator.validate(value, scalp: input.scalp))
        value.flow[0].evidence.origin = .inferred
        try HairCharacteristicsValidator.validate(value, scalp: input.scalp)
        value.flow[0].direction = Point3D(x: 0,y: 1,z: 0)
        XCTAssertThrowsError(try HairCharacteristicsValidator.validate(value, scalp: input.scalp))
        value = try sample(input); value.scalpSHA256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try HairCharacteristicsValidator.validate(value, scalp: input.scalp))
    }

    func testUnknownAndLegacyProfilesDoNotBecomeObservations() throws {
        let (input, _) = try SyntheticHaircut.create()
        let original = try ManifestCoding.encoder().encode(input.hairProfile)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        XCTAssertNil(object["characteristics"])
        var value = try sample(input)
        value.textures[0].value = nil
        XCTAssertThrowsError(try HairCharacteristicsValidator.validate(value, scalp: input.scalp))
        value.textures[0].evidence.origin = .unknown; value.textures[0].evidence.quality = .unknown
        try HairCharacteristicsValidator.validate(value, scalp: input.scalp)
        value.hairline[0].anchors![1] = value.hairline[0].anchors![0]
        XCTAssertThrowsError(try HairCharacteristicsValidator.validate(value, scalp: input.scalp))
        let restored = try ManifestCoding.decoder().decode(HairLengthProfile.self, from: original)
        XCTAssertNil(restored.characteristics)
        XCTAssertEqual(try ManifestCoding.encoder().encode(restored), original)
    }
}
