import XCTest
@testable import HairCore

final class ProcessingPreparationTests: XCTestCase {
    private func fixture(conflicting: Bool = false) throws -> (PersonalPreparationInputs, ProcessingPreparationResult) {
        let (source, hair) = try SyntheticHaircut.create()
        let brief = try PreparedDesignBrief.prepare(source: source,
            request: DesignBriefRequest(mode: .autonomous, seed: source.brief.seed))
        let input = try brief.validatedInput(source: source)
        let zero = Point3D(x:0,y:0,z:0)
        let mapping = ModelGuideImportRequest(id: UUID().uuidString,sourceArtifactSHA256:String(repeating:"a",count:64),
            scalpSHA256:hair.scalpSHA256,sourceCenter:zero,targetCenterMeters:zero,
            metersPerSourceUnit:Point3D(x:1,y:1,z:1),maximumRootCorrectionMeters:0.03,
            mappings:hair.guides.map { ModelGuideMapping(guideID:$0.id,region:$0.region,binding:$0.root) },method:"Synthetic preparation fixture")
        let y = conflicting ? hair.guides[0].points[0].y : -0.3
        let anatomy = GuideClearanceInput(scalpSHA256:hair.scalpSHA256,clearanceMeters:0.001,
            surfaces:[ClearanceSurface(region:.face,origin:.observed,sourceSHA256:String(repeating:"b",count:64),
                vertices:[Point3D(x:-0.3,y:y,z:-0.3),Point3D(x:0.3,y:y,z:-0.3),Point3D(x:0,y:y,z:0.3)],triangles:[[0,1,2]])])
        let encoder = ManifestCoding.encoder()
        let inputs = PersonalPreparationInputs(input:try encoder.encode(source),preparedBrief:try encoder.encode(brief),
            mapping:try encoder.encode(mapping),anatomy:try encoder.encode(anatomy))
        let roots = try GuideClearance.preflightRoots(input:input,bindings:mapping.mappings,materialRadiusMeters:0.00005,anatomy:anatomy)
        let data = try encoder.encode(input)
        let result = ProcessingPreparationResult(schemaVersion:1,kind:"personal_generation_preparation",request:try inputs.request(),
            generationInputData:data,generationInputFileSHA256:EvidenceHash.sha256(data),rootPreflight:roots,
            attachmentsReady:roots.suppliedSurfacesPassed,modelExecuted:false,personalStyleVerified:false,limitations:["Synthetic test"])
        return (inputs,result)
    }
    private func verify(_ inputs: PersonalPreparationInputs, _ result: ProcessingPreparationResult) throws -> ProcessingPreparationResult {
        let data = try ManifestCoding.encoder().encode(result)
        return try ProcessingPreparationResult.verify(data:data,outputSHA256:EvidenceHash.sha256(data),inputs:inputs)
    }
    func testReplaysReadyAndReviewResultsWithoutInventingModelExecution() throws {
        for conflicting in [false,true] {
            let (inputs,result) = try fixture(conflicting:conflicting)
            let checked = try verify(inputs,result)
            XCTAssertEqual(checked.attachmentsReady,!conflicting)
            XCTAssertEqual(checked.rootPreflight.missingRegions.count,2)
            XCTAssertFalse(checked.modelExecuted)
        }
    }
    func testRejectsRehashedFabricatedInputReportAndAcceptanceClaims() throws {
        let (inputs,good) = try fixture(conflicting:true)
        var changed = good;changed.attachmentsReady=true
        XCTAssertThrowsError(try verify(inputs,changed))
        changed=good;changed.rootPreflight.violations=[];changed.rootPreflight.suppliedSurfacesPassed=true
        changed.rootPreflight.requiresAttachmentReview=false;changed.attachmentsReady=true
        XCTAssertThrowsError(try verify(inputs,changed))
        changed=good;changed.rootPreflight.missingRegions=[]
        XCTAssertThrowsError(try verify(inputs,changed))
        changed=good;changed.modelExecuted=true
        XCTAssertThrowsError(try verify(inputs,changed))
        changed=good;changed.personalStyleVerified=true
        XCTAssertThrowsError(try verify(inputs,changed))
        changed=good
        var input=try ManifestCoding.decoder().decode(HairDesignInput.self,from:changed.generationInputData)
        input.brief.seed += 1
        changed.generationInputData=try ManifestCoding.encoder().encode(input)
        changed.generationInputFileSHA256=EvidenceHash.sha256(changed.generationInputData)
        XCTAssertThrowsError(try verify(inputs,changed))
        changed=good;changed.request.mappingSHA256=String(repeating:"0",count:64)
        XCTAssertThrowsError(try verify(inputs,changed))
        let data=try ManifestCoding.encoder().encode(good)
        XCTAssertThrowsError(try ProcessingPreparationResult.verify(data:data,outputSHA256:String(repeating:"0",count:64),inputs:inputs))
    }
}
