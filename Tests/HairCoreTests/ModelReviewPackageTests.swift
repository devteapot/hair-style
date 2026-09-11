import XCTest
@testable import HairCore

final class ModelReviewPackageTests:XCTestCase {
    func testRegenerationUsesOriginalSampleForConditionedSource() throws {
        var package=try fixture()
        XCTAssertEqual(try package.regenerationSampleSHA256(),package.mapping.sourceArtifactSHA256)
        var artifact=try JSONSerialization.jsonObject(with:package.sourceArtifactData) as! [String:Any]
        let base=String(repeating:"a",count:64)
        artifact["method"]="personal_envelope_decoder_latents_v1"
        artifact["implementation"]="metal_decoder_personal_constraints_v1"
        artifact["conditioning"]=["inputSHA256":base,"mappingGeometrySHA256":base,"baseSourceSHA256":base,
            "optimizationReportSHA256":base,"regionalReportSHA256":base,"decoderSHA256":base]
        package.sourceArtifactData=try JSONSerialization.data(withJSONObject:artifact)
        package.mapping.sourceArtifactSHA256=EvidenceHash.sha256(package.sourceArtifactData)
        XCTAssertEqual(try package.regenerationSampleSHA256(),base)
        package.sourceArtifactData.append(32)
        XCTAssertThrowsError(try package.regenerationSampleSHA256())
    }
    func testConditioningHandoffPreservesCandidateAndRejectsChangedEvidence() throws {
        var package=try fixture()
        let sample=package.mapping.sourceArtifactSHA256
        var artifact=try JSONSerialization.jsonObject(with:package.sourceArtifactData) as! [String:Any]
        artifact["method"]="personal_envelope_decoder_latents_v1"
        artifact["implementation"]="metal_decoder_personal_constraints_v1"
        artifact["samplingSeed"]=43
        artifact["conditioning"]=["inputSHA256":try HairArtifactHash.digest(package.input),
            "mappingGeometrySHA256":try ModelGuideImport.conditioningGeometryHash(package.mapping),
            "baseSourceSHA256":sample,"optimizationReportSHA256":sample,
            "regionalReportSHA256":sample,"decoderSHA256":sample]
        package.sourceArtifactData=try JSONSerialization.data(withJSONObject:artifact)
        package.mapping.sourceArtifactSHA256=EvidenceHash.sha256(package.sourceArtifactData)
        let prepared=try package.prepare()
        let anatomy=GuideClearanceInput(scalpSHA256:package.input.brief.scalpSHA256,
            clearanceMeters:0.001,surfaces:[ClearanceSurface(region:.face,origin:.observed,
                sourceSHA256:try HairArtifactHash.digest(prepared.observedFace),
                vertices:prepared.observedFace.vertices.map(\.position),triangles:prepared.observedFace.triangles)])
        let request=PersonalConditioningRequest(inputSHA256:sample,preparedBriefSHA256:sample,
            mappingSHA256:sample,anatomySHA256:sample,preparationSHA256:sample,modelSampleSHA256:sample)
        let result=ProcessingConditioningResult(schemaVersion:1,kind:"conditioned_personal_research",
            request:request,input:package.input,sourceArtifactData:package.sourceArtifactData,mapping:package.mapping,
            haircut:prepared.haircut,validation:prepared.imported.validation,mesh:prepared.mesh,
            clearance:try GuideClearance.check(input:package.input,haircut:prepared.haircut,anatomy:anatomy),
            acceptedForPersonalHaircut:false,personalStyleVerified:false,limitations:["Synthetic packaging test"])
        let handoff=try result.modelReviewPackage(scalpReview:package.scalpReview)
        XCTAssertEqual(try HairArtifactHash.digest(handoff.prepare().haircut),try HairArtifactHash.digest(result.haircut))
        XCTAssertEqual(try handoff.regenerationSampleSHA256(),sample)
        XCTAssertEqual(handoff.sourceArtifactData,package.sourceArtifactData)
        var changed=result;changed.haircut.guides[0].points.removeLast()
        XCTAssertThrowsError(try changed.modelReviewPackage(scalpReview:package.scalpReview))
        changed=result;changed.personalStyleVerified=true
        XCTAssertThrowsError(try changed.modelReviewPackage(scalpReview:package.scalpReview))
        var wrongReview=package.scalpReview;wrongReview.source.frames[0].captureID=UUID().uuidString
        XCTAssertThrowsError(try result.modelReviewPackage(scalpReview:wrongReview))
    }

    private func fixture() throws -> ModelReviewPackage {
        let points=[Point3D(x:0.03,y:0,z:0.5),Point3D(x:-0.03,y:0,z:0.5),
            Point3D(x:0.008,y:0.05,z:0.5),Point3D(x:0,y:-0.015,z:0.475)]
        let vertices=points.enumerated().map { SurfaceVertex(position:$0.element,normal:Point3D(x:0,y:0,z:-1),
            observations:[SurfaceObservation(frameIndex:0,depthPixelIndex:$0.offset)]) }
        let evidence=SurfaceFrameEvidence(captureID:UUID().uuidString,frameID:UUID().uuidString,
            frameSHA256:String(repeating:"a",count:64),maskSHA256:String(repeating:"b",count:64),source:.syntheticFixture,
            referenceFromCamera:.identity,registration:nil,retainedSamples:4,skippedSamples:0)
        let source=ObservedSurface(requestSHA256:String(repeating:"c",count:64),source:.syntheticFixture,
            vertices:vertices,triangles:[[0,1,2],[0,3,1],[0,2,3]],frames:[evidence],notes:["Synthetic package fixture"])
        let selection=AnatomicalSelection(surfaceSHA256:try HairArtifactHash.digest(source),anatomicalLeftEyeVertex:1,
            anatomicalRightEyeVertex:0,superiorVertex:2,anteriorVertex:3,method:"Synthetic frame")
        let envelope=try ScalpCompletion.suggestedEnvelope(surface:source,selection:selection)
        let review=ScalpReviewDocument(source:source,revisions:[ScalpCompletionRequest(selection:selection,subjectSessionID:"package-fixture",
            scalpID:UUID().uuidString,revision:1,envelope:envelope)])
        let completion=try review.latestResult(),scalp=completion.scalp
        let profile=HairLengthProfile(id:UUID().uuidString,revision:1,subjectSessionID:scalp.subjectSessionID,regions:[])
        let guardRequest=EllipsoidGuideGuardRequest(scalpSHA256:try HairArtifactHash.digest(scalp),envelope:envelope,
            permittedInsetMeters:0.0005,maximumPointCorrectionMeters:0.002)
        let brief=HairDesignBrief(id:UUID().uuidString,scalpSHA256:try HairArtifactHash.digest(scalp),hairProfileSHA256:try HairArtifactHash.digest(profile),mode:.autonomous,
            lengthLimits:[RegionalLengthLimit(region:.fringe,minimumMeters:0.001,maximumMeters:0.3,origin:.defaultValue)],allowGrowth:false,stylingAssumptions:[],seed:42,envelopeGuard:guardRequest)
        let root=scalp.vertices[0]
        let curve=(0..<100).map { [root.x,root.y+Double($0)*0.001,root.z] }
        let artifact:[String:Any]=["schemaVersion":1,"method":"pinned_haar_flattened_guides_adapter_v1",
            "modelRevision":"766a29a9112d84e0b5d512f9b6d7de4f27d3e857","implementation":"metal_inference_port_v1",
            "runReportSHA256":String(repeating:"d",count:64),"sourcePLYSHA256":String(repeating:"e",count:64),
            "coordinateConvention":"haar_template_coordinates_unresolved","units":"unresolved","pointsPerStrand":100,
            "pointOrder":"root_to_tip_as_emitted_by_texture2strands","strandCount":1,
            "strands":[["id":"fixture","points":curve]],"acceptedForPersonalHaircut":false]
        let data=try JSONSerialization.data(withJSONObject:artifact,options:.sortedKeys)
        let mapping=ModelGuideImportRequest(id:UUID().uuidString,sourceArtifactSHA256:EvidenceHash.sha256(data),scalpSHA256:brief.scalpSHA256,
            sourceCenter:Point3D(x:0,y:0,z:0),targetCenterMeters:Point3D(x:0,y:0,z:0),metersPerSourceUnit:Point3D(x:1,y:1,z:1),maximumRootCorrectionMeters:0.001,
            mappings:[ModelGuideMapping(guideID:"fixture",region:.fringe,binding:ScalpBinding(triangleIndex:0,barycentric:[1,0,0],normalOffsetMeters:0))],
            method:"Synthetic package test; no model execution",envelopeGuard:guardRequest)
        return ModelReviewPackage(input:HairDesignInput(scalp:scalp,hairProfile:profile,brief:brief),sourceArtifactData:data,mapping:mapping,scalpReview:review)
    }

    func testPackageReplaysImportAndPreservesFaceEvidence() throws {
        let package=try fixture()
        let decoded=try ManifestCoding.decoder().decode(ModelReviewPackage.self,from:ManifestCoding.encoder().encode(package))
        let prepared=try decoded.prepare()
        XCTAssertEqual(prepared.mesh.haircutSHA256,prepared.imported.validation.haircutSHA256)
        XCTAssertEqual(try HairArtifactHash.digest(prepared.observedFace),try HairArtifactHash.digest(package.scalpReview.latestResult().observed))
        XCTAssertEqual(prepared.mesh.guideCount,1)
        XCTAssertFalse(prepared.imported.acceptedForPersonalHaircut)
    }

    func testPackageRejectsWrongSubjectStaleScalpMissingGuardAndChangedSource() throws {
        let original=try fixture()
        var changed=original;changed.input.scalp.subjectSessionID="someone-else"
        XCTAssertThrowsError(try changed.prepare())
        changed=original;changed.input.scalp.vertices[1].x+=0.001
        XCTAssertThrowsError(try changed.prepare())
        changed=original;changed.input.brief.envelopeGuard=nil
        XCTAssertThrowsError(try changed.prepare())
        changed=original;changed.sourceArtifactData.append(Data(" ".utf8))
        XCTAssertThrowsError(try changed.prepare())
        changed=original;changed.scalpReview.source.frames[0].captureID=UUID().uuidString
        XCTAssertThrowsError(try changed.prepare())
    }

    func testResearchRevisionDisplaysExactCandidateAndKeepsOriginalImport() throws {
        var package = try fixture()
        let original = try package.prepare()
        var haircut = original.haircut
        haircut.id = UUID().uuidString
        haircut.generation.method += "; explicit research adjustment"
        haircut.guides[0].points.removeLast()
        package.researchRevision = ResearchReviewRevision(sourceImportSHA256: original.mesh.haircutSHA256,
            haircutSHA256: try HairArtifactHash.digest(haircut), method: "Shortened research curve", haircut: haircut)
        let prepared = try package.prepare()
        XCTAssertEqual(prepared.mesh.haircutSHA256, try HairArtifactHash.digest(haircut))
        XCTAssertEqual(prepared.haircut.guides[0].points.count, 99)
        XCTAssertEqual(prepared.imported.haircut.guides[0].points.count, 100)
        XCTAssertFalse(prepared.imported.acceptedForPersonalHaircut)
        let good = package
        package.researchRevision!.sourceImportSHA256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try package.prepare())
        package = good; package.researchRevision!.haircut.guides[0].points[1].x += 1
        XCTAssertThrowsError(try package.prepare())
        package.researchRevision!.haircutSHA256 = try HairArtifactHash.digest(package.researchRevision!.haircut)
        XCTAssertThrowsError(try package.prepare())
        package = good; package.researchRevision!.haircut.guides[0].id = "unrelated-guide"
        package.researchRevision!.haircutSHA256 = try HairArtifactHash.digest(package.researchRevision!.haircut)
        XCTAssertThrowsError(try package.prepare())
        package = good; package.researchRevision!.method = " "
        XCTAssertThrowsError(try package.prepare())
    }
}
