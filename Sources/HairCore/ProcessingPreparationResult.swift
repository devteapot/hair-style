import Foundation

public struct PersonalPreparationInputs: Codable, Sendable {
    public var input: Data
    public var preparedBrief: Data
    public var mapping: Data
    public var anatomy: Data
    public init(input: Data, preparedBrief: Data, mapping: Data, anatomy: Data) {
        self.input=input; self.preparedBrief=preparedBrief; self.mapping=mapping; self.anatomy=anatomy
    }
    public func request() throws -> PersonalPreparationRequest {
        guard [input,preparedBrief,mapping,anatomy].allSatisfy({ !$0.isEmpty && $0.count <= 25_000_000 }) else {
            throw CaptureError.invalid("Personal preparation inputs exceed the size limit.")
        }
        return PersonalPreparationRequest(inputSHA256: EvidenceHash.sha256(input),
            preparedBriefSHA256: EvidenceHash.sha256(preparedBrief), mappingSHA256: EvidenceHash.sha256(mapping),
            anatomySHA256: EvidenceHash.sha256(anatomy))
    }
}

public struct PersonalPreparationRequest: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var kind = "prepare_personal_generation"
    public var inputSHA256: String
    public var preparedBriefSHA256: String
    public var mappingSHA256: String
    public var anatomySHA256: String
    public func validate() throws {
        guard schemaVersion == 1, kind == "prepare_personal_generation",
              [inputSHA256,preparedBriefSHA256,mappingSHA256,anatomySHA256].allSatisfy(HairArtifactHash.valid) else {
            throw CaptureError.invalid("Invalid personal preparation request.")
        }
    }
}

public struct ProcessingPreparationResult: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var request: PersonalPreparationRequest
    public var generationInputData: Data
    public var generationInputFileSHA256: String
    public var rootPreflight: RootClearancePreflight
    public var attachmentsReady: Bool
    public var modelExecuted: Bool
    public var personalStyleVerified: Bool
    public var limitations: [String]

    /// Replays both the brief and every supplied-surface root check. A server's
    /// ready flag alone cannot make a changed personal input eligible for use.
    public static func verify(data: Data, outputSHA256: String, inputs: PersonalPreparationInputs) throws -> Self {
        let expectedRequest = try inputs.request()
        guard data.count <= 100_000_000, HairArtifactHash.valid(outputSHA256),
              EvidenceHash.sha256(data) == outputSHA256 else {
            throw CaptureError.invalid("Personal preparation output bytes do not match their hash.")
        }
        let decoder = ManifestCoding.decoder()
        let result = try decoder.decode(Self.self, from: data)
        guard result.schemaVersion == 1, result.kind == "personal_generation_preparation",
              result.request == expectedRequest, !result.modelExecuted, !result.personalStyleVerified,
              result.generationInputData.count <= 25_000_000,
              EvidenceHash.sha256(result.generationInputData) == result.generationInputFileSHA256 else {
            throw CaptureError.invalid("Personal preparation result differs from the submitted request or input bytes.")
        }
        let source = try decoder.decode(HairDesignInput.self, from: inputs.input)
        let brief = try decoder.decode(PreparedDesignBrief.self, from: inputs.preparedBrief)
        let expected = try brief.validatedInput(source: source)
        let returned = try decoder.decode(HairDesignInput.self, from: result.generationInputData)
        guard try HairArtifactHash.digest(expected) == HairArtifactHash.digest(returned) else {
            throw CaptureError.invalid("Server changed the prepared personal input.")
        }
        let mapping = try decoder.decode(ModelGuideImportRequest.self, from: inputs.mapping)
        let anatomy = try decoder.decode(GuideClearanceInput.self, from: inputs.anatomy)
        guard mapping.scalpSHA256 == expected.brief.scalpSHA256,
              (0.001...0.02).contains(anatomy.clearanceMeters) else {
            throw CaptureError.invalid("Preparation has stale attachments or an unsupported clearance margin.")
        }
        let roots = try GuideClearance.preflightRoots(input: expected, bindings: mapping.mappings,
            materialRadiusMeters: 0.00005, anatomy: anatomy)
        guard try HairArtifactHash.digest(roots) == HairArtifactHash.digest(result.rootPreflight),
              result.attachmentsReady == roots.suppliedSurfacesPassed else {
            throw CaptureError.invalid("Server attachment report does not reproduce from the supplied evidence.")
        }
        return result
    }
}
