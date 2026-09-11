import XCTest
@testable import HairCore

final class ModelGuideImportTests: XCTestCase {
    func testConditionedArtifactCannotMoveToAnotherBriefOrMapping() throws {
        let (input, data, original) = try fixture()
        var source = try JSONSerialization.jsonObject(with: data) as! [String:Any]
        source["method"] = "personal_envelope_decoder_latents_v1"
        source["implementation"] = "metal_decoder_personal_constraints_v1"
        source["samplingSeed"] = 43
        let hash = String(repeating:"a",count:64)
        source["conditioning"] = ["inputSHA256": try HairArtifactHash.digest(input),
            "mappingGeometrySHA256": try ModelGuideImport.conditioningGeometryHash(original),
            "baseSourceSHA256": hash, "optimizationReportSHA256": hash, "regionalReportSHA256": hash, "decoderSHA256": hash]
        let conditioned = try JSONSerialization.data(withJSONObject: source)
        var request = original; request.sourceArtifactSHA256 = EvidenceHash.sha256(conditioned)
        let result = try ModelGuideImport.apply(sourceData:conditioned,input:input,request:request)
        XCTAssertTrue(result.haircut.generation.method.hasPrefix("personal_decoder_latents:"))
        XCTAssertFalse(result.acceptedForPersonalHaircut)
        var other = input; other.brief.seed += 1
        XCTAssertThrowsError(try ModelGuideImport.apply(sourceData:conditioned,input:other,request:request))
        request.targetCenterMeters.x += 0.001
        XCTAssertThrowsError(try ModelGuideImport.apply(sourceData:conditioned,input:input,request:request))
    }
    func testActualModelSeedIsDistinctFromBriefSeedAndSurvivesEditing() throws {
        let (input, data, originalRequest) = try fixture()
        let legacy = try ModelGuideImport.apply(sourceData: data, input: input, request: originalRequest)
        XCTAssertNil(legacy.haircut.generation.modelSamplingSeed)
        var artifact = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        artifact["samplingSeed"] = 43
        let seeded = try JSONSerialization.data(withJSONObject: artifact)
        var request = originalRequest; request.sourceArtifactSHA256 = EvidenceHash.sha256(seeded)
        let result = try ModelGuideImport.apply(sourceData: seeded, input: input, request: request)
        XCTAssertEqual(result.haircut.generation.seed, input.brief.seed)
        XCTAssertEqual(result.haircut.generation.modelSamplingSeed, 43)
        let roundTrip = try ManifestCoding.decoder().decode(HaircutRevision.self, from: ManifestCoding.encoder().encode(result.haircut))
        XCTAssertEqual(roundTrip.generation.modelSamplingSeed, 43)
        let edited = try HaircutEditor.apply(HairEdit(baseSHA256: HairArtifactHash.digest(result.haircut),
            operation: .shortenToLength, region: .fringe, value: 0.04), to: result.haircut, input: input)
        XCTAssertEqual(edited.haircut.generation.modelSamplingSeed, 43)
    }
    private func fixture() throws -> (HairDesignInput, Data, ModelGuideImportRequest) {
        var (input, base) = try SyntheticHaircut.create()
        input.brief.lengthLimits[0].maximumMeters = 0.055
        let sourceCenter = Point3D(x: 0.1,y: 1.7,z: -0.2)
        let scale = Point3D(x: 2,y: 0.5,z: 1.5)
        let guides: [[String: Any]] = try base.guides.map { guide in
            let root = try HaircutValidator.attachment(guide.root, scalp: input.scalp).position
            let points: [[Double]] = (0..<100).map { index in
                let p = root + Point3D(x: 0.005,y: 0,z: Double(index)*0.001)
                return [sourceCenter.x+p.x/scale.x, sourceCenter.y+p.y/scale.y, sourceCenter.z+p.z/scale.z]
            }
            return ["id":guide.id,"points":points]
        }
        let source: [String: Any] = ["schemaVersion":1,"method":"pinned_haar_flattened_guides_adapter_v1",
            "modelRevision":"766a29a9112d84e0b5d512f9b6d7de4f27d3e857","implementation":"metal_inference_port_v1",
            "runReportSHA256":String(repeating:"a",count:64),"sourcePLYSHA256":String(repeating:"b",count:64),
            "coordinateConvention":"haar_template_coordinates_unresolved","units":"unresolved","pointsPerStrand":100,
            "pointOrder":"root_to_tip_as_emitted_by_texture2strands","strandCount":2,"strands":guides,"acceptedForPersonalHaircut":false]
        let data = try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys])
        let request = ModelGuideImportRequest(id: UUID().uuidString, sourceArtifactSHA256: EvidenceHash.sha256(data),
            scalpSHA256: input.brief.scalpSHA256, sourceCenter: sourceCenter, targetCenterMeters: Point3D(x: 0,y: 0,z: 0),
            metersPerSourceUnit: scale, maximumRootCorrectionMeters: 0.006,
            mappings: base.guides.map { ModelGuideMapping(guideID: $0.id, region: $0.region, binding: $0.root) },
            method: "synthetic mapping, not a model execution")
        return (input,data,request)
    }

    func testMappingPreservesRootsAndCurveOrderWhileApplyingRegionalLimits() throws {
        let (input,data,request) = try fixture()
        let result = try ModelGuideImport.apply(sourceData: data, input: input, request: request)
        XCTAssertEqual(result.haircut.guides.count, 2)
        XCTAssertEqual(result.haircut.generation.origin, .model)
        XCTAssertTrue(result.validation.synthetic)
        XCTAssertFalse(result.acceptedForPersonalHaircut)
        XCTAssertFalse(result.personalizationBeyondFittingVerified)
        XCTAssertFalse(result.validation.publishableAsValidatedDesign)
        XCTAssertEqual(result.decisions.map(\.trimmedByRegionalLimit), [true,false])
        for (index, guide) in result.haircut.guides.enumerated() {
            let attachment = try HaircutValidator.attachment(guide.root, scalp: input.scalp)
            XCTAssertLessThan((guide.points[0]-attachment.position).length, 1e-12)
            XCTAssertEqual(result.decisions[index].rootCorrectionMeters, 0.005, accuracy: 1e-12)
            XCTAssertEqual(try HaircutValidator.arcLength(guide.points), index == 0 ? 0.055 : 0.099, accuracy: 1e-12)
            XCTAssertTrue(zip(guide.points.dropFirst(),guide.points).allSatisfy { $0.z > $1.z })
        }
    }

    func testImportRejectsChangedEvidenceStaleScalpExcessiveCorrectionAndMissingGuides() throws {
        let (input,data,initial) = try fixture()
        XCTAssertThrowsError(try ModelGuideImport.apply(sourceData: data + Data(" ".utf8), input: input, request: initial))
        var request = initial; request.scalpSHA256 = String(repeating:"0",count:64)
        XCTAssertThrowsError(try ModelGuideImport.apply(sourceData:data,input:input,request:request))
        request = initial; request.maximumRootCorrectionMeters = 0.001
        XCTAssertThrowsError(try ModelGuideImport.apply(sourceData:data,input:input,request:request))
        request = initial; request.mappings.removeLast()
        XCTAssertThrowsError(try ModelGuideImport.apply(sourceData:data,input:input,request:request))
        request = initial; request.mappings.reverse()
        XCTAssertThrowsError(try ModelGuideImport.apply(sourceData:data,input:input,request:request))
        request = initial; request.metersPerSourceUnit.x = -1
        XCTAssertThrowsError(try ModelGuideImport.apply(sourceData:data,input:input,request:request))
        var limited = input; limited.brief.lengthLimits[1].minimumMeters = 0.15
        XCTAssertThrowsError(try ModelGuideImport.apply(sourceData:data,input:limited,request:initial))
    }

    func testImportedGuideEditsPersistAndReplayWithModelProvenance() throws {
        let (input,data,request) = try fixture()
        let result = try ModelGuideImport.apply(sourceData:data,input:input,request:request)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let repository = HaircutRepository(root:root)
        let initial = try repository.save(input:input,haircut:result.haircut)
        let edited = try HaircutEditor.apply(HairEdit(baseSHA256:initial,operation:.shortenToLength,region:.fringe,value:0.04),to:result.haircut,input:input)
        let saved = try repository.save(input:input,haircut:edited.haircut)
        let reopened = try repository.load(id:request.id,sha256:saved)
        XCTAssertEqual(reopened.haircut.revision,2)
        XCTAssertEqual(reopened.haircut.generation.method,result.haircut.generation.method)
        XCTAssertEqual(try HairArtifactHash.digest(reopened.haircut.guides[1]),try HairArtifactHash.digest(result.haircut.guides[1]))
        XCTAssertEqual(try HairArtifactHash.digest(repository.load(id:request.id,sha256:initial).haircut),initial)
    }
}
