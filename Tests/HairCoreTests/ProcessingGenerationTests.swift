import XCTest
@testable import HairCore

final class ProcessingGenerationTests: XCTestCase {
    func testResearchBoundaryRequestBindingAndMalformedGuides() throws {
        let hash = String(repeating: "a", count: 64)
        var guide: [String: Any] = ["id": "haar-00000", "points": (0..<100).map { [0.0, Double($0)/1000, 0.0] }]
        var source: [String: Any] = ["schemaVersion": 1, "method": "pinned_haar_flattened_guides_adapter_v1",
            "modelRevision": "766a29a9112d84e0b5d512f9b6d7de4f27d3e857", "implementation": "metal_inference_port_v1",
            "runReportSHA256": hash, "sourcePLYSHA256": hash, "coordinateConvention": "haar_template_coordinates_unresolved",
            "units": "unresolved", "pointsPerStrand": 100, "pointOrder": "root_to_tip_as_emitted_by_texture2strands",
            "strandCount": 1, "strands": [guide], "acceptedForPersonalHaircut": false, "samplingSeed": 43]
        func verify(_ source: [String: Any], expected: String = "wavy", personal: Bool = false) throws -> ProcessingGenerationResult {
            let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "kind": "generated_research_guides",
                "request": ["schemaVersion": 1, "kind": "generate_haar_template", "description": "wavy", "seed": 43],
                "personalStyleVerified": personal, "guides": source])
            return try ProcessingGenerationResult.verify(data: data, outputSHA256: EvidenceHash.sha256(data), description: expected, seed: 43)
        }
        XCTAssertEqual(try verify(source).strandCount, 1)
        XCTAssertThrowsError(try verify(source, expected: "straight"))
        XCTAssertThrowsError(try verify(source, personal: true))
        source["samplingSeed"] = 42
        XCTAssertThrowsError(try verify(source))
        source["samplingSeed"] = 43
        source["strands"] = [guide, guide]; source["strandCount"] = 2
        XCTAssertThrowsError(try verify(source))
        guide["points"] = Array(repeating: [0.0, 0.0, 0.0], count: 100)
        source["strands"] = [guide]; source["strandCount"] = 1
        XCTAssertThrowsError(try verify(source))
    }
}
