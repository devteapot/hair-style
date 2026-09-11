import Foundation

public struct PersonalConditioningInputs: Codable, Sendable {
    public var preparationInputs: PersonalPreparationInputs
    public var preparationData: Data
    public var preparationSHA256: String
    public var modelSampleSHA256: String
    public init(preparationInputs: PersonalPreparationInputs, preparationData: Data,
                preparationSHA256: String, modelSampleSHA256: String) {
        self.preparationInputs=preparationInputs; self.preparationData=preparationData
        self.preparationSHA256=preparationSHA256; self.modelSampleSHA256=modelSampleSHA256
    }
    public func request() throws -> PersonalConditioningRequest {
        let preparation = try ProcessingPreparationResult.verify(data:preparationData,
            outputSHA256:preparationSHA256,inputs:preparationInputs)
        let mapping = try ManifestCoding.decoder().decode(ModelGuideImportRequest.self,from:preparationInputs.mapping)
        guard preparation.attachmentsReady, mapping.sourceArtifactSHA256 == modelSampleSHA256 else {
            throw CaptureError.invalid("Conditioning requires verified attachments and the selected model sample's mapping.")
        }
        let source = try preparationInputs.request()
        let result = PersonalConditioningRequest(inputSHA256:source.inputSHA256,
            preparedBriefSHA256:source.preparedBriefSHA256,mappingSHA256:source.mappingSHA256,
            anatomySHA256:source.anatomySHA256,preparationSHA256:preparationSHA256,modelSampleSHA256:modelSampleSHA256)
        try result.validate()
        return result
    }
}

public struct PersonalConditioningRequest: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var kind = "condition_personal_sample"
    public var inputSHA256: String
    public var preparedBriefSHA256: String
    public var mappingSHA256: String
    public var anatomySHA256: String
    public var preparationSHA256: String
    public var modelSampleSHA256: String
    public func validate() throws {
        guard schemaVersion == 1, kind == "condition_personal_sample",
              [inputSHA256,preparedBriefSHA256,mappingSHA256,anatomySHA256,preparationSHA256,modelSampleSHA256].allSatisfy(HairArtifactHash.valid) else {
            throw CaptureError.invalid("Invalid personal conditioning request.")
        }
    }
}

public struct ProcessingConditioningResult: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var request: PersonalConditioningRequest
    public var input: HairDesignInput
    public var sourceArtifactData: Data
    public var mapping: ModelGuideImportRequest
    public var haircut: HaircutRevision
    public var validation: HairValidationReport
    public var mesh: CompiledHairMesh
    public var clearance: GuideClearanceReport
    public var acceptedForPersonalHaircut: Bool
    public var personalStyleVerified: Bool
    public var limitations: [String]
    public var directionFit: ConditioningDirectionFit? = nil

    /// Create a self-contained editing-studio handoff after result verification.
    /// The retained scalp review must reproduce this candidate's geometry.
    /// Packaging does not promote a research result to physical/style acceptance.
    public func modelReviewPackage(scalpReview: ScalpReviewDocument) throws -> ModelReviewPackage {
        try request.validate()
        guard schemaVersion == 1,kind == "conditioned_personal_research",
              !acceptedForPersonalHaircut,!personalStyleVerified else {
            throw CaptureError.invalid("Only an unaccepted research conditioning result can enter this review handoff.")
        }
        let source=try ManifestCoding.decoder().decode(ResearchStrandArtifact.self,from:sourceArtifactData)
        guard source.method == "personal_envelope_decoder_latents_v1",
              source.conditioning?.baseSourceSHA256 == request.modelSampleSHA256 else {
            throw CaptureError.invalid("Review handoff lost the conditioning sample reference.")
        }
        var package=ModelReviewPackage(input:input,sourceArtifactData:sourceArtifactData,mapping:mapping,scalpReview:scalpReview)
        if let fit = directionFit {
            let imported = try ModelGuideImport.apply(sourceData:sourceArtifactData,input:input,request:mapping)
            guard fit.sourceHaircutSHA256 == imported.validation.haircutSHA256 else {
                throw CaptureError.invalid("Fitted review lost its original conditioned import.")
            }
            package.researchRevision = ResearchReviewRevision(sourceImportSHA256:fit.sourceHaircutSHA256,
                haircutSHA256:try HairArtifactHash.digest(haircut),
                method:"Declared bounded root-fixed direction fitting after conditioning. Root offsets remain inferred; physical fit and style are unverified.",haircut:haircut)
        }
        let prepared=try package.prepare()
        guard try HairArtifactHash.digest(prepared.haircut) == HairArtifactHash.digest(haircut),
              prepared.mesh.haircutSHA256 == validation.haircutSHA256 else {
            throw CaptureError.invalid("Review handoff does not reproduce the conditioning revision.")
        }
        return package
    }

    /// Replays geometry and supplied-anatomy checks; this does not prove model
    /// computation, styling quality, or completeness of the captured anatomy.
    public static func verify(data: Data, outputSHA256: String, inputs: PersonalConditioningInputs) throws -> Self {
        guard data.count <= 100_000_000, HairArtifactHash.valid(outputSHA256),
              EvidenceHash.sha256(data) == outputSHA256 else {
            throw CaptureError.invalid("Conditioning output bytes do not match their hash.")
        }
        let expectedRequest = try inputs.request()
        let decoder = ManifestCoding.decoder()
        let result = try decoder.decode(Self.self,from:data)
        guard result.schemaVersion == 1, result.kind == "conditioned_personal_research",
              result.request == expectedRequest, !result.acceptedForPersonalHaircut, !result.personalStyleVerified else {
            throw CaptureError.invalid("Conditioning result differs from its request or claims unverified acceptance.")
        }
        let original = try decoder.decode(HairDesignInput.self,from:inputs.preparationInputs.input)
        let brief = try decoder.decode(PreparedDesignBrief.self,from:inputs.preparationInputs.preparedBrief)
        let prepared = try brief.validatedInput(source:original)
        let originalMapping = try decoder.decode(ModelGuideImportRequest.self,from:inputs.preparationInputs.mapping)
        guard try HairArtifactHash.digest(prepared) == HairArtifactHash.digest(result.input),
              try ModelGuideImport.conditioningGeometryHash(originalMapping) == ModelGuideImport.conditioningGeometryHash(result.mapping) else {
            throw CaptureError.invalid("Conditioning changed the prepared input, attachments or mapping bounds.")
        }
        let source = try decoder.decode(ResearchStrandArtifact.self,from:result.sourceArtifactData)
        guard source.method == "personal_envelope_decoder_latents_v1",
              source.conditioning?.baseSourceSHA256 == inputs.modelSampleSHA256 else {
            throw CaptureError.invalid("Conditioned source is not bound to the selected model sample.")
        }
        let imported = try ModelGuideImport.apply(sourceData:result.sourceArtifactData,input:prepared,request:result.mapping)
        let anatomy = try decoder.decode(GuideClearanceInput.self,from:inputs.preparationInputs.anatomy)
        let selected: HaircutRevision, validation: HairValidationReport, clearance: GuideClearanceReport
        if let fit = result.directionFit {
            let verified = try fit.verify(input:prepared,base:imported.haircut,candidate:result.haircut,
                mapping:originalMapping,anatomy:anatomy,expectedSampleSHA256:inputs.modelSampleSHA256)
            selected = result.haircut; validation = verified.validation; clearance = verified.clearance
        } else {
            selected = imported.haircut; validation = imported.validation
            clearance = try GuideClearance.check(input:prepared,haircut:selected,anatomy:anatomy)
        }
        let mesh = try HairMeshCompiler.compile(input:prepared,haircut:selected,radialSides:3,radiusScale:1)
        for (name, actual, supplied) in [
            ("haircut", try HairArtifactHash.digest(selected), try HairArtifactHash.digest(result.haircut)),
            ("validation", try HairArtifactHash.digest(validation), try HairArtifactHash.digest(result.validation)),
            ("mesh", try HairArtifactHash.digest(mesh), try HairArtifactHash.digest(result.mesh)),
            ("clearance", try HairArtifactHash.digest(clearance), try HairArtifactHash.digest(result.clearance))
        ] {
            guard actual == supplied else {
                throw CaptureError.invalid("Conditioning \(name) does not replay locally.")
            }
        }
        return result
    }
}
