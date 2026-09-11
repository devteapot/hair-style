import XCTest
@testable import HairCore

final class ConditioningDirectionFitTests: XCTestCase {
    private func fixture() throws -> (HairDesignInput, HaircutRevision, ModelGuideImportRequest, GuideClearanceInput, ConditioningDirectionFit, HaircutRevision) {
        let (input, original) = try SyntheticHaircut.create()
        var base = try HaircutEditor.apply(HairEdit(baseSHA256:HairArtifactHash.digest(original),operation:.scaleLateralVolume,region:.fringe,value:1.5),to:original,input:input).haircut
        for i in base.guides.indices {
            let p = base.guides[i].points
            base.guides[i].points = [p[0]] + (0..<3).flatMap { segment in (1...33).map { step in p[segment]+(p[segment+1]-p[segment])*(Double(step)/33) } }
        }
        let anatomy=GuideClearanceInput(scalpSHA256:base.scalpSHA256,clearanceMeters:0.001,surfaces:[
            ClearanceSurface(region:.face,origin:.synthetic,sourceSHA256:String(repeating:"a",count:64),
                vertices:[Point3D(x:0.11,y:0,z:-0.2),Point3D(x:0.11,y:0.4,z:-0.2),Point3D(x:0.11,y:0.4,z:0.4),Point3D(x:0.11,y:0,z:0.4)],triangles:[[0,1,2],[0,2,3]])])
        let proposal=try GuideRotationProposal.propose(input:input,haircut:base,anatomy:anatomy)
        let raw:[String:Any] = ["schemaVersion":1,"method":"pinned_haar_flattened_guides_adapter_v1","modelRevision":"synthetic",
            "implementation":"synthetic","runReportSHA256":String(repeating:"a",count:64),"sourcePLYSHA256":String(repeating:"b",count:64),
            "coordinateConvention":"synthetic","units":"meters","pointsPerStrand":100,"pointOrder":"root_to_tip_as_emitted_by_texture2strands",
            "strandCount":base.guides.count,"strands":base.guides.map { ["id":$0.id,"points":$0.points.map { [$0.x,$0.y,$0.z] }] },"acceptedForPersonalHaircut":false]
        let data=try JSONSerialization.data(withJSONObject:raw), zero=Point3D(x:0,y:0,z:0)
        let mapping=ModelGuideImportRequest(id:UUID().uuidString,sourceArtifactSHA256:EvidenceHash.sha256(data),scalpSHA256:base.scalpSHA256,
            sourceCenter:zero,targetCenterMeters:zero,metersPerSourceUnit:Point3D(x:1,y:1,z:1),maximumRootCorrectionMeters:0.03,
            mappings:base.guides.map { ModelGuideMapping(guideID:$0.id,region:$0.region,binding:$0.root) },method:"Synthetic test mapping")
        let axes=["x":Point3D(x:1,y:0,z:0),"y":Point3D(x:0,y:1,z:0),"z":Point3D(x:0,y:0,z:1)]
        let fit=ConditioningDirectionFit(sourceHaircutSHA256:proposal.sourceHaircutSHA256,originalSampleData:data,
            rotations:proposal.decisions.map { ConditioningGuideRotation(guideID:$0.guideID,axis:axes[$0.axis!]!,degrees:$0.degrees!) })
        return (input,base,mapping,anatomy,fit,proposal.haircut)
    }

    func testReplaysExactFitAndRejectsChangedInstructionsOrGeometry() throws {
        let (input,base,mapping,anatomy,fit,candidate)=try fixture()
        func verify(_ value:ConditioningDirectionFit,_ haircut:HaircutRevision) throws -> ConditioningFitVerification {
            try value.verify(input:input,base:base,candidate:haircut,mapping:mapping,anatomy:anatomy,expectedSampleSHA256:mapping.sourceArtifactSHA256)
        }
        let result=try verify(fit,candidate)
        XCTAssertTrue(result.clearance.surfaceChecksPassed)
        XCTAssertLessThanOrEqual(result.maximumCumulativeMovementMeters,0.02)
        XCTAssertFalse(result.clearance.publishableAsValidatedDesign)
        var changed=fit;changed.rotations[0].degrees += 1
        XCTAssertThrowsError(try verify(changed,candidate))
        changed=fit;changed.originalSampleData.append(32)
        XCTAssertThrowsError(try verify(changed,candidate))
        changed=fit;changed.rotations.append(changed.rotations[0])
        XCTAssertThrowsError(try verify(changed,candidate))
        var wrong=candidate;wrong.guides[1].points[1].x += 0.001
        XCTAssertThrowsError(try verify(fit,wrong))
        wrong=candidate;wrong.guides[0].root.normalOffsetMeters += 0.001
        XCTAssertThrowsError(try verify(fit,wrong))
    }

    func testCumulativeBudgetUsesOriginalSampleNotOnlyConditionedCurve() throws {
        let (input,base,mapping,anatomy,fit,candidate)=try fixture()
        var raw=try JSONSerialization.jsonObject(with:fit.originalSampleData) as! [String:Any]
        var strands=raw["strands"] as! [[String:Any]], points=strands[0]["points"] as! [[Double]]
        for i in 1..<points.count { points[i][1] += 0.1*Double(i)/99 }
        strands[0]["points"]=points;raw["strands"]=strands
        var changed=fit;changed.originalSampleData=try JSONSerialization.data(withJSONObject:raw)
        XCTAssertThrowsError(try changed.verify(input:input,base:base,candidate:candidate,mapping:mapping,anatomy:anatomy,
            expectedSampleSHA256:EvidenceHash.sha256(changed.originalSampleData)))
    }
}
