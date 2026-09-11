import XCTest
@testable import HairCore

final class ProcessingConditioningTests: XCTestCase {
    private func fixture(curveConflict:Bool=false) throws -> (PersonalConditioningInputs,ProcessingConditioningResult) {
        let (original,hair)=try SyntheticHaircut.create()
        let brief=try PreparedDesignBrief.prepare(source:original,request:DesignBriefRequest(mode:.autonomous,seed:42))
        let input=try brief.validatedInput(source:original), sample=String(repeating:"a",count:64)
        let zero=Point3D(x:0,y:0,z:0)
        let mapping=ModelGuideImportRequest(id:UUID().uuidString,sourceArtifactSHA256:sample,scalpSHA256:hair.scalpSHA256,
            sourceCenter:zero,targetCenterMeters:zero,metersPerSourceUnit:Point3D(x:1,y:1,z:1),maximumRootCorrectionMeters:0.03,
            mappings:hair.guides.map { ModelGuideMapping(guideID:$0.id,region:$0.region,binding:$0.root) },method:"Synthetic conditioning fixture")
        let face = curveConflict
            ? [Point3D(x:-0.3,y:-0.3,z:0.025),Point3D(x:0.3,y:-0.3,z:0.025),Point3D(x:0,y:0.3,z:0.025)]
            : [Point3D(x:-0.3,y:-0.3,z:-0.3),Point3D(x:0.3,y:-0.3,z:-0.3),Point3D(x:0,y:-0.3,z:0.3)]
        let anatomy=GuideClearanceInput(scalpSHA256:hair.scalpSHA256,clearanceMeters:0.001,
            surfaces:[ClearanceSurface(region:.face,origin:.observed,sourceSHA256:sample,
                vertices:face,triangles:[[0,1,2]])])
        let encoder=ManifestCoding.encoder()
        let prepInputs=PersonalPreparationInputs(input:try encoder.encode(original),preparedBrief:try encoder.encode(brief),
            mapping:try encoder.encode(mapping),anatomy:try encoder.encode(anatomy))
        let preparedData=try encoder.encode(input)
        let roots=try GuideClearance.preflightRoots(input:input,bindings:mapping.mappings,materialRadiusMeters:0.00005,anatomy:anatomy)
        let preparation=ProcessingPreparationResult(schemaVersion:1,kind:"personal_generation_preparation",request:try prepInputs.request(),
            generationInputData:preparedData,generationInputFileSHA256:EvidenceHash.sha256(preparedData),rootPreflight:roots,
            attachmentsReady:true,modelExecuted:false,personalStyleVerified:false,limitations:[])
        let prepData=try encoder.encode(preparation)
        let context=PersonalConditioningInputs(preparationInputs:prepInputs,preparationData:prepData,
            preparationSHA256:EvidenceHash.sha256(prepData),modelSampleSHA256:sample)
        let guides:[[String:Any]]=try hair.guides.map { guide in
            let root=try HaircutValidator.attachment(guide.root,scalp:input.scalp).position
            let points=(0..<100).map { [root.x,root.y,root.z+Double($0)*0.001] }
            return ["id":guide.id,"points":points]
        }
        let source:[String:Any]=["schemaVersion":1,"method":"personal_envelope_decoder_latents_v1",
            "modelRevision":"766a29a9112d84e0b5d512f9b6d7de4f27d3e857","implementation":"metal_decoder_personal_constraints_v1",
            "runReportSHA256":sample,"sourcePLYSHA256":sample,"coordinateConvention":"haar_template_coordinates_unresolved",
            "units":"unresolved","pointsPerStrand":100,"pointOrder":"root_to_tip_as_emitted_by_texture2strands",
            "strandCount":guides.count,"strands":guides,"acceptedForPersonalHaircut":false,"samplingSeed":43,
            "conditioning":["inputSHA256":try HairArtifactHash.digest(input),
                "mappingGeometrySHA256":try ModelGuideImport.conditioningGeometryHash(mapping),"baseSourceSHA256":sample,
                "optimizationReportSHA256":sample,"regionalReportSHA256":sample,"decoderSHA256":sample]]
        let sourceData=try JSONSerialization.data(withJSONObject:source)
        var exported=mapping;exported.id=UUID().uuidString;exported.sourceArtifactSHA256=EvidenceHash.sha256(sourceData)
        let imported=try ModelGuideImport.apply(sourceData:sourceData,input:input,request:exported)
        let result=ProcessingConditioningResult(schemaVersion:1,kind:"conditioned_personal_research",request:try context.request(),input:input,
            sourceArtifactData:sourceData,mapping:exported,haircut:imported.haircut,validation:imported.validation,
            mesh:try HairMeshCompiler.compile(input:input,haircut:imported.haircut,radialSides:3,radiusScale:1),
            clearance:try GuideClearance.check(input:input,haircut:imported.haircut,anatomy:anatomy),
            acceptedForPersonalHaircut:false,personalStyleVerified:false,limitations:["Synthetic contract test; no model executed"])
        return (context,result)
    }
    private func verify(_ context:PersonalConditioningInputs,_ result:ProcessingConditioningResult) throws -> ProcessingConditioningResult {
        let data=try ManifestCoding.encoder().encode(result)
        return try ProcessingConditioningResult.verify(data:data,outputSHA256:EvidenceHash.sha256(data),inputs:context)
    }
    func testReplaysExactConditionedGeometryAndMissingAnatomy() throws {
        let (context,result)=try fixture();let checked=try verify(context,result)
        XCTAssertEqual(checked.clearance.missingRegions.count,2)
        XCTAssertEqual(checked.mesh.haircutSHA256,checked.validation.haircutSHA256)
        XCTAssertEqual(checked.haircut.generation.modelSamplingSeed,43)
        XCTAssertFalse(checked.acceptedForPersonalHaircut)
    }
    func testRejectsRehashedChangedMeshMappingClearanceAndAcceptance() throws {
        let (context,result)=try fixture()
        var altered=result;altered.mesh.vertices[0].x += 0.001
        XCTAssertThrowsError(try verify(context,altered))
        altered=result;altered.clearance.missingRegions=[]
        XCTAssertThrowsError(try verify(context,altered))
        altered=result;altered.mapping.maximumRootCorrectionMeters=0.029
        XCTAssertThrowsError(try verify(context,altered))
        altered=result;altered.input.brief.seed += 1
        XCTAssertThrowsError(try verify(context,altered))
        altered=result;altered.acceptedForPersonalHaircut=true
        XCTAssertThrowsError(try verify(context,altered))
        altered=result;altered.personalStyleVerified=true
        XCTAssertThrowsError(try verify(context,altered))
        altered=result;altered.sourceArtifactData.append(32)
        XCTAssertThrowsError(try verify(context,altered))
        var wrong=context;wrong.modelSampleSHA256=String(repeating:"b",count:64)
        XCTAssertThrowsError(try wrong.request())
        wrong=context;wrong.preparationSHA256=String(repeating:"b",count:64)
        XCTAssertThrowsError(try wrong.request())
    }
    func testRetainsRealCurveFailureAndRejectsFabricatedClearance() throws {
        let (context,result)=try fixture(curveConflict:true)
        XCTAssertGreaterThan(result.clearance.violations.count,0)
        let checked=try verify(context,result)
        XCTAssertFalse(checked.clearance.surfaceChecksPassed)
        var altered=result;altered.clearance.violations=[];altered.clearance.surfaceChecksPassed=true
        XCTAssertThrowsError(try verify(context,altered))
    }
}
