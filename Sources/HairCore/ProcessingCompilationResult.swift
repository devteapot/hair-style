import Foundation

public struct ProcessingCompilationResult: Decodable, Sendable {
    public struct Request: Decodable, Sendable {
        public var schemaVersion: Int
        public var kind: String
        public var inputSHA256: String
        public var haircutSHA256: String
    }
    public var schemaVersion: Int
    public var kind: String
    public var request: Request
    public var validation: HairValidationReport
    public var mesh: CompiledHairMesh
    public var personalStyleVerified: Bool

    /// Replays local geometry checks and mesh construction. Server flags alone never authorize rendering.
    public static func verify(data: Data, outputSHA256: String, inputData: Data, haircutData: Data) throws -> Self {
        guard data.count <= 100_000_000, inputData.count <= 100_000_000, haircutData.count <= 100_000_000,
              HairArtifactHash.valid(outputSHA256), EvidenceHash.sha256(data) == outputSHA256 else {
            throw CaptureError.invalid("Compiled result byte hash or size is invalid.")
        }
        let result = try ManifestCoding.decoder().decode(Self.self, from: data)
        guard result.schemaVersion == 1, result.kind == "compiled_hair", result.request.schemaVersion == 1,
              result.request.kind == "compile_hair", !result.personalStyleVerified,
              result.request.inputSHA256 == EvidenceHash.sha256(inputData),
              result.request.haircutSHA256 == EvidenceHash.sha256(haircutData) else {
            throw CaptureError.invalid("Compiled result does not match the submitted artifacts.")
        }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: inputData)
        let haircut = try ManifestCoding.decoder().decode(HaircutRevision.self, from: haircutData)
        let validation = try HaircutValidator.validate(input: input, haircut: haircut)
        let mesh = try HairMeshCompiler.compile(input: input, haircut: haircut, radialSides: 3, radiusScale: 1)
        guard try HairArtifactHash.digest(result.validation) == HairArtifactHash.digest(validation),
              try HairArtifactHash.digest(result.mesh) == HairArtifactHash.digest(mesh) else {
            throw CaptureError.invalid("Server validation or geometry differs from the local compilation.")
        }
        return result
    }
}
