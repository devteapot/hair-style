import Foundation

/// Transport-checked research output. It does not establish personal fit or model quality.
public struct ProcessingGenerationResult: Sendable {
    public let sourceData: Data
    public let strandCount: Int
    public let outputSHA256: String

    public static func verify(data: Data, outputSHA256: String, description: String, seed: Int) throws -> Self {
        struct Header: Decodable {
            struct Request: Decodable { var schemaVersion: Int; var kind: String; var description: String; var seed: Int }
            var schemaVersion: Int; var kind: String; var personalStyleVerified: Bool; var request: Request
        }
        guard data.count <= 100_000_000, HairArtifactHash.valid(outputSHA256),
              EvidenceHash.sha256(data) == outputSHA256 else {
            throw CaptureError.invalid("Generated research result hash or size is invalid.")
        }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.schemaVersion == 1, header.kind == "generated_research_guides", !header.personalStyleVerified,
              header.request.schemaVersion == 1, header.request.kind == "generate_haar_template",
              header.request.description == description, header.request.seed == seed,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let guides = root["guides"] as? [String: Any] else {
            throw CaptureError.invalid("Generated research result does not match its request or hash.")
        }
        let sourceData = try JSONSerialization.data(withJSONObject: guides, options: [.sortedKeys])
        let artifact = try JSONDecoder().decode(ResearchStrandArtifact.self, from: sourceData)
        guard artifact.schemaVersion == 1, artifact.method == "pinned_haar_flattened_guides_adapter_v1",
              artifact.implementation == "metal_inference_port_v1",
              artifact.modelRevision == "766a29a9112d84e0b5d512f9b6d7de4f27d3e857",
              HairArtifactHash.valid(artifact.runReportSHA256), HairArtifactHash.valid(artifact.sourcePLYSHA256),
              artifact.coordinateConvention == "haar_template_coordinates_unresolved", artifact.units == "unresolved",
              artifact.pointOrder == "root_to_tip_as_emitted_by_texture2strands", artifact.pointsPerStrand == 100,
              !artifact.acceptedForPersonalHaircut, artifact.samplingSeed == UInt64(exactly: seed),
              artifact.samplingSeed != nil, (1...10_000).contains(artifact.strandCount),
              artifact.strandCount == artifact.strands.count else {
            throw CaptureError.invalid("Unsupported generated research guide contract.")
        }
        var ids = Set<String>()
        for guide in artifact.strands {
            guard !guide.id.isEmpty, ids.insert(guide.id).inserted, guide.points.count == 100 else {
                throw CaptureError.invalid("Generated guide identities or point counts are invalid.")
            }
            var first: [Double]?
            var hasExtent = false
            for point in guide.points {
                guard point.count == 3, point.allSatisfy({ $0.isFinite && abs($0) < 10 }) else {
                    throw CaptureError.invalid("Generated guide contains invalid coordinates.")
                }
                if let first { hasExtent = hasExtent || point != first } else { first = point }
            }
            guard hasExtent else { throw CaptureError.invalid("Generated guide has no extent.") }
        }
        return Self(sourceData: sourceData, strandCount: artifact.strandCount, outputSHA256: outputSHA256)
    }
}
