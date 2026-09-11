import XCTest
@testable import HairCore

final class HaircutTests: XCTestCase {
    func testRepositoryKeepsBranchesReplaysParentsAndRejectsCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = HaircutRepository(root: root)
        let (input, base) = try SyntheticHaircut.create()
        let initial = try repository.save(input: input, haircut: base)
        XCTAssertEqual(try repository.save(input: input, haircut: base), initial)
        var branches: [String] = []
        for length in [0.05,0.07] {
            let edit = HairEdit(baseSHA256: initial, operation: .shortenToLength, region: .fringe, value: length)
            let changed = try HaircutEditor.apply(edit, to: base, input: input)
            let hash = try repository.save(input: input, haircut: changed.haircut)
            branches.append(hash)
            let reopened = try repository.load(id: base.id, sha256: hash)
            XCTAssertEqual(try HairArtifactHash.digest(reopened.haircut), hash)
            XCTAssertEqual(reopened.haircut.revision, 2)
        }
        XCTAssertNotEqual(branches[0], branches[1])
        let original = try repository.load(id: base.id, sha256: initial)
        XCTAssertEqual(original.haircut.revision, 1)
        XCTAssertThrowsError(try repository.load(id: "../outside", sha256: initial))
        let parentFile = root.appendingPathComponent(base.id).appendingPathComponent(initial + ".json")
        var forged = original; forged.haircut.materials[0].roughness += 0.1
        try ManifestCoding.encoder().encode(forged).write(to: parentFile)
        XCTAssertThrowsError(try repository.load(id: base.id, sha256: branches[0]))
        XCTAssertThrowsError(try repository.save(input: input, haircut: base))
    }

    private func rebound(_ input: inout HairDesignInput, _ cut: inout HaircutRevision) throws {
        input.brief.scalpSHA256 = try HairArtifactHash.digest(input.scalp)
        input.brief.hairProfileSHA256 = try HairArtifactHash.digest(input.hairProfile)
        cut.scalpSHA256 = input.brief.scalpSHA256; cut.hairProfileSHA256 = input.brief.hairProfileSHA256
        cut.briefSHA256 = try HairArtifactHash.digest(input.brief)
    }

    func testShorteningPreservesRootCurveAndOtherRegionWithReplayableParent() throws {
        let (input, base) = try SyntheticHaircut.create()
        let bytes = try ManifestCoding.encoder().encode(base)
        let edit = HairEdit(baseSHA256: try HairArtifactHash.digest(base), operation: .shortenToLength, region: .fringe, value: 0.07)
        let result = try HaircutEditor.apply(edit, to: base, input: input)
        XCTAssertEqual(result.haircut.revision, 2); XCTAssertEqual(result.haircut.id, base.id)
        XCTAssertEqual(result.haircut.parentSHA256, edit.baseSHA256)
        XCTAssertEqual(result.changedGuideIDs, ["fringe"])
        XCTAssertEqual(try HaircutValidator.arcLength(result.haircut.guides[0].points), 0.07, accuracy: 1e-10)
        XCTAssertEqual(try ManifestCoding.encoder().encode(result.haircut.guides[1]), try ManifestCoding.encoder().encode(base.guides[1]))
        XCTAssertEqual(try ManifestCoding.encoder().encode(result.haircut.guides[0].root), try ManifestCoding.encoder().encode(base.guides[0].root))
        XCTAssertEqual(result.haircut.guides[0].points[0].components, base.guides[0].points[0].components)
        XCTAssertEqual(result.haircut.guides[0].points[1].components, base.guides[0].points[1].components)
        XCTAssertEqual(try ManifestCoding.encoder().encode(base), bytes)
        try HaircutEditor.verifyTransition(from: base, to: result.haircut, input: input)
        var forged = result.haircut; forged.materials[0].roughness = 0.7
        _ = try HaircutValidator.validate(input: input, haircut: forged)
        XCTAssertThrowsError(try HaircutEditor.verifyTransition(from: base, to: forged, input: input))
        XCTAssertTrue(result.validation.synthetic)
        XCTAssertTrue(result.validation.feasibility.contains(.uncertain))
        XCTAssertFalse(result.validation.publishableAsValidatedDesign)
    }

    func testVolumeEditPreservesRootAndNormalComponentButChangesTangentialShape() throws {
        let (input, base) = try SyntheticHaircut.create()
        let edit = HairEdit(baseSHA256: try HairArtifactHash.digest(base), operation: .scaleLateralVolume, region: .crown, value: 0.6)
        let result = try HaircutEditor.apply(edit, to: base, input: input)
        let root = base.guides[1].points[0]
        for (p,q) in zip(base.guides[1].points,result.haircut.guides[1].points) {
            XCTAssertEqual(q.y, p.y, accuracy: 1e-12)
            XCTAssertEqual(q.x-root.x, (p.x-root.x)*0.6, accuracy: 1e-12)
            XCTAssertEqual(q.z-root.z, (p.z-root.z)*0.6, accuracy: 1e-12)
        }
        XCTAssertEqual(try HairArtifactHash.digest(base.guides[0]), try HairArtifactHash.digest(result.haircut.guides[0]))
        var noChange = edit; noChange.value = 1
        XCTAssertThrowsError(try HaircutEditor.apply(noChange, to: base, input: input))
        var stale = edit; stale.baseSHA256 = String(repeating: "0",count: 64)
        XCTAssertThrowsError(try HaircutEditor.apply(stale, to: base, input: input))
    }

    func testDirectionPreservesRootsLengthsOtherRegionAndReplays() throws {
        let (input,base)=try SyntheticHaircut.create()
        let hash=try HairArtifactHash.digest(base)
        let edit=HairEdit(baseSHA256:hash,operation:.rotateAroundRootNormal,region:.fringe,value:30)
        let result=try HaircutEditor.apply(edit,to:base,input:input)
        let before=base.guides[0],after=result.haircut.guides[0]
        XCTAssertEqual(result.changedGuideIDs,["fringe"])
        XCTAssertEqual(try HairArtifactHash.digest(before.root),try HairArtifactHash.digest(after.root))
        XCTAssertEqual(before.points[0].components,after.points[0].components)
        XCTAssertEqual(try HairArtifactHash.digest(base.guides[1]),try HairArtifactHash.digest(result.haircut.guides[1]))
        for i in before.points.indices {
            for j in before.points.indices {
                XCTAssertEqual((before.points[i]-before.points[j]).length,(after.points[i]-after.points[j]).length,accuracy:1e-12)
            }
        }
        // Independent known-axis check: the fixture normal is +Y.
        let delta=before.points[1]-before.points[0], moved=after.points[1]-after.points[0]
        XCTAssertEqual(moved.x,delta.x*sqrt(3)/2+delta.z/2,accuracy:1e-12)
        XCTAssertEqual(moved.y,delta.y,accuracy:1e-12)
        XCTAssertEqual(moved.z,delta.z*sqrt(3)/2-delta.x/2,accuracy:1e-12)
        XCTAssertEqual(try HairArtifactHash.digest(base),hash)
        try HaircutEditor.verifyTransition(from:base,to:result.haircut,input:input)
        for value in [0,46,-46,Double.infinity] {
            var invalid=edit;invalid.value=value
            XCTAssertThrowsError(try HaircutEditor.apply(invalid,to:base,input:input))
        }
        // A supplied plane intersects the rotated fringe: reject rather than save it.
        let anatomy=GuideClearanceInput(scalpSHA256:base.scalpSHA256,clearanceMeters:0.001,
            surfaces:[ClearanceSurface(region:.face,origin:.observed,sourceSHA256:hash,
                vertices:[Point3D(x:-0.4,y:0.12,z:-0.4),Point3D(x:0.4,y:0.12,z:-0.4),Point3D(x:0,y:0.12,z:0.4)],triangles:[[0,1,2]])])
        XCTAssertFalse(try GuideClearance.check(input:input,haircut:result.haircut,anatomy:anatomy).violations.isEmpty)
        XCTAssertThrowsError(try HaircutEditor.apply(edit,to:base,input:input,anatomy:anatomy))
    }

    func testLengthEvidenceChangesFeasibilityWithoutPromotingUnknownToSupported() throws {
        var (input, cut) = try SyntheticHaircut.create()
        let uncertain = try HaircutValidator.validate(input: input, haircut: cut)
        XCTAssertEqual(uncertain.uncertainLengthRegions, [.fringe])
        input.hairProfile.regions[0] = RegionalLengthObservation(region: .fringe, maximumAvailableMeters: 0.03,
            origin: .observed, quality: .high, evidenceReferences: ["fixture-only"], method: "test observation")
        try rebound(&input,&cut)
        XCTAssertThrowsError(try HaircutValidator.validate(input: input, haircut: cut))
        input.brief.allowGrowth = true; try rebound(&input,&cut)
        let growth = try HaircutValidator.validate(input: input, haircut: cut)
        XCTAssertEqual(growth.growthRegions, [.fringe]); XCTAssertTrue(growth.feasibility.contains(.requiresGrowth))
        XCTAssertTrue(growth.feasibility.contains(.uncertain)) // other physical checks remain outstanding
        input.hairProfile.regions[0].origin = .inferred; input.brief.allowGrowth = false; try rebound(&input,&cut)
        let inferred = try HaircutValidator.validate(input: input, haircut: cut)
        XCTAssertTrue(inferred.growthRegions.isEmpty); XCTAssertEqual(inferred.uncertainLengthRegions, [.fringe])
    }

    func testRejectsBrokenBindingsStaleProfilesAndInvalidGuideGeometry() throws {
        let (input, base) = try SyntheticHaircut.create()
        var cut = base; cut.guides[0].root.barycentric = [0.5,0.5,0.5]
        XCTAssertThrowsError(try HaircutValidator.validate(input: input, haircut: cut))
        cut = base; cut.guides[0].root.triangleIndex = Int.max
        XCTAssertThrowsError(try HaircutValidator.validate(input: input, haircut: cut))
        cut = base; cut.guides[0].points[0].x += 0.002
        XCTAssertThrowsError(try HaircutValidator.validate(input: input, haircut: cut))
        cut = base; cut.guides[0].points[1] = cut.guides[0].points[0]
        XCTAssertThrowsError(try HaircutValidator.validate(input: input, haircut: cut))
        cut = base; cut.guides[0].points[1].x = .nan
        XCTAssertThrowsError(try HaircutValidator.validate(input: input, haircut: cut))
        cut = base; cut.guides[0].materialID = "missing"
        XCTAssertThrowsError(try HaircutValidator.validate(input: input, haircut: cut))
        var changed = input; changed.hairProfile.revision += 1
        XCTAssertThrowsError(try HaircutValidator.validate(input: changed, haircut: base))
        changed = input; changed.scalp.coordinateConvention = "mirrored_camera"
        XCTAssertThrowsError(try HaircutValidator.validate(input: changed, haircut: base))
        let extend = HairEdit(baseSHA256: try HairArtifactHash.digest(base), operation: .shortenToLength, region: .fringe, value: 0.25)
        XCTAssertThrowsError(try HaircutEditor.apply(extend, to: base, input: input))
    }

    func testExactVertexTrimRoundtripAndEditConstraintRejection() throws {
        var (input, base) = try SyntheticHaircut.create()
        let target = (base.guides[0].points[1]-base.guides[0].points[0]).length
        let edit = HairEdit(baseSHA256: try HairArtifactHash.digest(base), operation: .shortenToLength, region: .fringe, value: target)
        let result = try HaircutEditor.apply(edit, to: base, input: input)
        XCTAssertEqual(result.haircut.guides[0].points.count, 2)
        let decoded = try ManifestCoding.decoder().decode(HairEditResult.self, from: ManifestCoding.encoder().encode(result))
        XCTAssertEqual(try HairArtifactHash.digest(decoded.haircut), result.validation.haircutSHA256)
        input.brief.lengthLimits[0].maximumMeters = try HaircutValidator.arcLength(base.guides[0].points) + 0.001
        try rebound(&input,&base)
        let volume = HairEdit(baseSHA256: try HairArtifactHash.digest(base), operation: .scaleLateralVolume, region: .fringe, value: 1.5)
        XCTAssertThrowsError(try HaircutEditor.apply(volume, to: base, input: input))
    }
}
