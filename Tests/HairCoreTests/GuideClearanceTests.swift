import XCTest
@testable import HairCore

final class GuideClearanceTests: XCTestCase {
    func testBatchMatchesIndividualReportsAndRejectsInvalidCandidates() throws {
        let (input, cut) = try SyntheticHaircut.create()
        let anatomy = GuideClearanceInput(scalpSHA256: cut.scalpSHA256, clearanceMeters: 0.001,
            surfaces: [obstacle(y: 0.12)])
        var shorter = try HaircutEditor.apply(HairEdit(baseSHA256: try HairArtifactHash.digest(cut),
            operation: .shortenToLength, region: .fringe, value: 0.07), to: cut, input: input).haircut
        shorter.guides = Array(shorter.guides.prefix(1))
        let cuts = [cut, shorter]
        let batch = try GuideClearance.checkBatch(input: input, haircuts: cuts, anatomy: anatomy)
        for (candidate, report) in zip(cuts, batch) {
            XCTAssertEqual(try HairArtifactHash.digest(report),
                try HairArtifactHash.digest(GuideClearance.check(input: input, haircut: candidate, anatomy: anatomy)))
        }
        XCTAssertNotEqual(batch[0].violations.count, batch[1].violations.count)
        XCTAssertFalse(batch[0].publishableAsValidatedDesign)
        XCTAssertThrowsError(try GuideClearance.checkBatch(input: input, haircuts: [], anatomy: anatomy))
        XCTAssertThrowsError(try GuideClearance.checkBatch(input: input, haircuts: Array(repeating: cut, count: 257), anatomy: anatomy))
        var invalid = shorter; invalid.guides[0].points[1].x = .nan
        XCTAssertThrowsError(try GuideClearance.checkBatch(input: input, haircuts: [cut, invalid], anatomy: anatomy))
    }
    func testProposedRootPreflightRequiresNoHaircutAndPreservesMissingAnatomy() throws {
        let (input,cut) = try SyntheticHaircut.create()
        let bindings = cut.guides.map { ModelGuideMapping(guideID:$0.id,region:$0.region,binding:$0.root) }
        let anatomy = GuideClearanceInput(scalpSHA256:input.brief.scalpSHA256,clearanceMeters:0.001,
            surfaces:[obstacle(y:cut.guides[0].points[0].y)])
        let report = try GuideClearance.preflightRoots(input:input,bindings:bindings,materialRadiusMeters:0.00005,anatomy:anatomy)
        XCTAssertTrue(report.requiresAttachmentReview)
        XCTAssertEqual(report.violations.count,2)
        XCTAssertTrue(report.violations.allSatisfy { $0.distanceMeters < 1e-12 })
        XCTAssertEqual(report.missingRegions,[.anatomicalLeftEar,.anatomicalRightEar])
        var far=anatomy;far.surfaces=[obstacle(y:0.3)]
        let clear=try GuideClearance.preflightRoots(input:input,bindings:bindings,materialRadiusMeters:0.00005,anatomy:far)
        XCTAssertFalse(clear.requiresAttachmentReview);XCTAssertFalse(clear.physicalFitVerified)
        XCTAssertEqual(clear.bindingsSHA256,try HairArtifactHash.digest(bindings))
        XCTAssertThrowsError(try GuideClearance.preflightRoots(input:input,bindings:[bindings[0],bindings[0]],materialRadiusMeters:0.00005,anatomy:far))
    }
    func testRootCollisionsAreDistinguishedFromCurveOnlyCollisions() throws {
        let (input,cut) = try SyntheticHaircut.create()
        let rootY = cut.guides[0].points[0].y
        let blocked = GuideClearanceInput(scalpSHA256:cut.scalpSHA256,clearanceMeters:0.001,surfaces:[obstacle(y:rootY)])
        let report = try GuideClearance.check(input:input,haircut:cut,anatomy:blocked)
        XCTAssertEqual(Set(report.rootViolations!.map(\.guideID)), Set(cut.guides.map(\.id)))
        XCTAssertTrue(report.rootViolations!.allSatisfy { $0.distanceMeters < 1e-12 })
        let curveOnly = GuideClearanceInput(scalpSHA256:cut.scalpSHA256,clearanceMeters:0.001,surfaces:[obstacle(y:0.12)])
        let curveReport = try GuideClearance.check(input:input,haircut:cut,anatomy:curveOnly)
        XCTAssertFalse(curveReport.violations.isEmpty)
        XCTAssertEqual(curveReport.rootViolations?.count, 0)
        var legacy = try JSONSerialization.jsonObject(with: ManifestCoding.encoder().encode(report)) as! [String:Any]
        legacy.removeValue(forKey: "rootViolations")
        let restored = try ManifestCoding.decoder().decode(GuideClearanceReport.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.rootViolations)
    }
    func testUnsafeVolumeEditIsRejectedBeforeCreatingASavedRevision() throws {
        let (input,cut) = try SyntheticHaircut.create()
        let plane = ClearanceSurface(region:.face,origin:.synthetic,sourceSHA256:String(repeating:"a",count:64),
            vertices:[Point3D(x:0.11,y:0,z:-0.2),Point3D(x:0.11,y:0.4,z:-0.2),
                      Point3D(x:0.11,y:0.4,z:0.4),Point3D(x:0.11,y:0,z:0.4)],triangles:[[0,1,2],[0,2,3]])
        let anatomy = GuideClearanceInput(scalpSHA256:cut.scalpSHA256,clearanceMeters:0.001,surfaces:[plane])
        XCTAssertTrue(try GuideClearance.check(input:input,haircut:cut,anatomy:anatomy).surfaceChecksPassed)
        let hash = try HairArtifactHash.digest(cut)
        let edit = HairEdit(baseSHA256:hash,operation:.scaleLateralVolume,region:.fringe,value:1.5)
        // The normal length validator accepts this edit; anatomy adds a real constraint.
        XCTAssertNoThrow(try HaircutEditor.apply(edit,to:cut,input:input))
        XCTAssertThrowsError(try HaircutEditor.apply(edit,to:cut,input:input,anatomy:anatomy))
        XCTAssertEqual(try HairArtifactHash.digest(cut),hash)
        let safe = HairEdit(baseSHA256:hash,operation:.shortenToLength,region:.fringe,value:0.07)
        let result = try HaircutEditor.apply(safe,to:cut,input:input,anatomy:anatomy)
        XCTAssertTrue(result.clearance!.surfaceChecksPassed)
        XCTAssertFalse(result.clearance!.publishableAsValidatedDesign)
    }
    func testSegmentTriangleCrossingParallelEdgeAndVertexDistances() {
        let p = Point3D(x: 0,y: 0,z: 0), q = Point3D(x: 0.1,y: 0,z: 0), r = Point3D(x: 0,y: 0.1,z: 0)
        func d(_ a: Point3D,_ b: Point3D) -> Double { GuideClearance.segmentTriangleDistance(a,b,p,q,r) }
        XCTAssertEqual(d(Point3D(x:0.02,y:0.02,z:-0.1),Point3D(x:0.02,y:0.02,z:0.1)),0,accuracy:1e-12)
        XCTAssertEqual(d(Point3D(x:0.01,y:0.01,z:0.02),Point3D(x:0.04,y:0.01,z:0.02)),0.02,accuracy:1e-12)
        XCTAssertEqual(d(Point3D(x:-0.02,y:0.02,z:0),Point3D(x:-0.02,y:0.06,z:0)),0.02,accuracy:1e-12)
        XCTAssertEqual(d(Point3D(x:-0.03,y:-0.04,z:0),Point3D(x:-0.03,y:-0.04,z:0)),0.05,accuracy:1e-12)
        // Coplanar segment crossing the triangle while both endpoints are outside.
        XCTAssertEqual(d(Point3D(x:-0.05,y:0.02,z:0),Point3D(x:0.2,y:0.02,z:0)),0,accuracy:1e-12)
    }

    private func obstacle(y: Double) -> ClearanceSurface {
        ClearanceSurface(region:.face,origin:.synthetic,sourceSHA256:String(repeating:"a",count:64),
            vertices:[Point3D(x:-0.3,y:y,z:-0.3),Point3D(x:0.3,y:y,z:-0.3),Point3D(x:0,y:y,z:0.4)],triangles:[[0,1,2]])
    }

    func testReportsCrossingsAndMissingAnatomyWithoutClaimingPhysicalValidity() throws {
        let (input,cut) = try SyntheticHaircut.create()
        let anatomy = GuideClearanceInput(scalpSHA256:cut.scalpSHA256,clearanceMeters:0.001,surfaces:[obstacle(y:0.12)])
        let report = try GuideClearance.check(input:input,haircut:cut,anatomy:anatomy)
        XCTAssertFalse(report.surfaceChecksPassed)
        XCTAssertEqual(Set(report.violations.map(\.guideID)),["fringe","crown"])
        XCTAssertTrue(report.violations.contains { $0.distanceMeters < 1e-10 })
        XCTAssertEqual(report.missingRegions,[.anatomicalLeftEar,.anatomicalRightEar])
        XCTAssertFalse(report.publishableAsValidatedDesign)
        XCTAssertTrue(report.synthetic)
        XCTAssertEqual(report.haircutSHA256,try HairArtifactHash.digest(cut))
        var far = anatomy; far.surfaces = [obstacle(y:0.3)]
        let clear = try GuideClearance.check(input:input,haircut:cut,anatomy:far)
        XCTAssertTrue(clear.surfaceChecksPassed); XCTAssertEqual(clear.triangleComparisons,0)
    }

    func testMaterialRadiusAndMarginDetectNearMissWithoutCenterlineIntersection() throws {
        let (input,cut) = try SyntheticHaircut.create()
        // Guides end at y=0.1701. A plane 0.5 mm farther away is a capsule hit
        // with 1 mm clearance even though neither centerline crosses it.
        var anatomy = GuideClearanceInput(scalpSHA256:cut.scalpSHA256,clearanceMeters:0,surfaces:[obstacle(y:0.1706)])
        XCTAssertTrue(try GuideClearance.check(input:input,haircut:cut,anatomy:anatomy).surfaceChecksPassed)
        anatomy.clearanceMeters = 0.001
        let result = try GuideClearance.check(input:input,haircut:cut,anatomy:anatomy)
        XCTAssertFalse(result.surfaceChecksPassed)
        XCTAssertEqual(result.violations[0].distanceMeters,0.0005,accuracy:1e-10)
        var thick = cut; thick.materials[0].radiusMeters = 0.001
        anatomy.clearanceMeters = 0
        XCTAssertFalse(try GuideClearance.check(input:input,haircut:thick,anatomy:anatomy).surfaceChecksPassed)
    }

    func testBVHMatchesBruteForceAndRejectsWrongScalpOrInvalidMesh() throws {
        let (input,cut) = try SyntheticHaircut.create()
        var surface = obstacle(y:0.12)
        // Separate triangles force a hierarchy, including many clear far patches.
        for i in 0..<32 {
            let x = -0.25+Double(i)*0.015, start = surface.vertices.count
            surface.vertices += [Point3D(x:x,y:0.4,z:0),Point3D(x:x+0.005,y:0.4,z:0),Point3D(x:x,y:0.4,z:0.005)]
            surface.triangles.append([start,start+1,start+2])
        }
        var anatomy = GuideClearanceInput(scalpSHA256:cut.scalpSHA256,clearanceMeters:0.001,surfaces:[surface])
        let result = try GuideClearance.check(input:input,haircut:cut,anatomy:anatomy)
        var count = 0
        for guide in cut.guides {
            for (a,b) in zip(guide.points,guide.points.dropFirst()) {
                let nearest = surface.triangles.map { t in
                    GuideClearance.segmentTriangleDistance(a,b,surface.vertices[t[0]],surface.vertices[t[1]],surface.vertices[t[2]])
                }.min()!
                if nearest <= 0.00105 { count += 1 }
            }
        }
        XCTAssertEqual(result.violations.count,count)
        XCTAssertLessThan(result.triangleComparisons,33*6)
        anatomy.scalpSHA256 = String(repeating:"0",count:64)
        XCTAssertThrowsError(try GuideClearance.check(input:input,haircut:cut,anatomy:anatomy))
        anatomy.scalpSHA256 = cut.scalpSHA256; anatomy.surfaces[0].triangles[0][0] = Int.max
        XCTAssertThrowsError(try GuideClearance.check(input:input,haircut:cut,anatomy:anatomy))
    }
}
