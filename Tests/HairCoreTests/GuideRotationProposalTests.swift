import XCTest
@testable import HairCore

final class GuideRotationProposalTests: XCTestCase {
    func testDiagonalRotationUsesRightHandRuleAndPreservesRoot() {
        let root=Point3D(x:0.2,y:-0.1,z:0.3)
        let points=[root,root+Point3D(x:1,y:0,z:0)]
        let result=GuideRotationProposal.rotated(points,axis:Point3D(x:2,y:2,z:2),degrees:120)
        XCTAssertEqual(result[0],root)
        XCTAssertLessThan((result[1]-(root+Point3D(x:0,y:1,z:0))).length,1e-12)
        let back=GuideRotationProposal.rotated(result,axis:Point3D(x:1,y:1,z:1),degrees:-120)
        XCTAssertLessThan((back[1]-points[1]).length,1e-12)
    }

    func testRotationClearsSyntheticObstacleWithoutChangingRootsOrCurveShape() throws {
        let (input,original) = try SyntheticHaircut.create()
        let edited = try HaircutEditor.apply(HairEdit(baseSHA256:HairArtifactHash.digest(original),
            operation:.scaleLateralVolume,region:.fringe,value:1.5),to:original,input:input).haircut
        let plane = ClearanceSurface(region:.face,origin:.synthetic,sourceSHA256:String(repeating:"a",count:64),
            vertices:[Point3D(x:0.11,y:0,z:-0.2),Point3D(x:0.11,y:0.4,z:-0.2),
                      Point3D(x:0.11,y:0.4,z:0.4),Point3D(x:0.11,y:0,z:0.4)],triangles:[[0,1,2],[0,2,3]])
        let anatomy = GuideClearanceInput(scalpSHA256:edited.scalpSHA256,clearanceMeters:0.001,surfaces:[plane])
        XCTAssertFalse(try GuideClearance.check(input:input,haircut:edited,anatomy:anatomy).surfaceChecksPassed)
        let result = try GuideRotationProposal.propose(input:input,haircut:edited,anatomy:anatomy)
        XCTAssertTrue(result.clearance.surfaceChecksPassed)
        XCTAssertFalse(result.acceptedForPersonalHaircut)
        XCTAssertEqual(result.clearance.missingRegions.count,2)
        XCTAssertEqual(result.decisions.count,1)
        XCTAssertGreaterThan(result.decisions[0].passingCandidates,0)
        XCTAssertEqual(result.sourceHaircutSHA256,try HairArtifactHash.digest(edited))
        XCTAssertEqual(try ManifestCoding.encoder().encode(result.haircut.guides[1]),try ManifestCoding.encoder().encode(edited.guides[1]))
        for (a,b) in zip(edited.guides,result.haircut.guides) {
            XCTAssertEqual(a.points[0],b.points[0])
            XCTAssertEqual(try ManifestCoding.encoder().encode(a.root),try ManifestCoding.encoder().encode(b.root))
            // All pair distances, not only total length, prove rigid curve-shape retention.
            for i in a.points.indices {
                for j in a.points.indices {
                    XCTAssertEqual((a.points[i]-a.points[j]).length,(b.points[i]-b.points[j]).length,accuracy:1e-12)
                }
                XCTAssertLessThanOrEqual((a.points[i]-b.points[i]).length,0.02)
            }
        }
    }

    func testRootConflictRejectsRotationAndUnsolvableCurvesRemainReported() throws {
        let (input,cut) = try SyntheticHaircut.create()
        func anatomy(_ y:Double)->GuideClearanceInput {
            GuideClearanceInput(scalpSHA256:cut.scalpSHA256,clearanceMeters:0.001,surfaces:[
                ClearanceSurface(region:.face,origin:.synthetic,sourceSHA256:String(repeating:"b",count:64),
                    vertices:[Point3D(x:-0.3,y:y,z:-0.3),Point3D(x:0.3,y:y,z:-0.3),Point3D(x:0,y:y,z:0.4)],triangles:[[0,1,2]])])
        }
        XCTAssertThrowsError(try GuideRotationProposal.propose(input:input,haircut:cut,anatomy:anatomy(cut.guides[0].points[0].y)))
        let result = try GuideRotationProposal.propose(input:input,haircut:cut,anatomy:anatomy(0.12),includeDiagonalAxes:true,includeDenseAxes:true)
        XCTAssertFalse(result.clearance.surfaceChecksPassed)
        XCTAssertTrue(result.decisions.allSatisfy { $0.checkedCandidates == 616 })
        XCTAssertFalse(result.acceptedForPersonalHaircut)
        XCTAssertTrue(result.decisions.allSatisfy { $0.passingCandidates == 0 })
        XCTAssertEqual(try ManifestCoding.encoder().encode(result.haircut.guides),try ManifestCoding.encoder().encode(cut.guides))
    }
}
