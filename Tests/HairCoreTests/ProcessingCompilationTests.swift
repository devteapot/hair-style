import XCTest
@testable import HairCore

final class ProcessingCompilationTests: XCTestCase {
    func testLocalReplayRejectsGeometryTamperingEvenWithUpdatedTransportHash() throws {
        let (input, haircut) = try SyntheticHaircut.create()
        let inputData = try ManifestCoding.encoder().encode(input), haircutData = try ManifestCoding.encoder().encode(haircut)
        func object<T: Encodable>(_ value: T) throws -> Any {
            try JSONSerialization.jsonObject(with: ManifestCoding.encoder().encode(value))
        }
        var result: [String: Any] = ["schemaVersion": 1, "kind": "compiled_hair", "personalStyleVerified": false,
            "request": ["schemaVersion": 1, "kind": "compile_hair", "inputSHA256": EvidenceHash.sha256(inputData), "haircutSHA256": EvidenceHash.sha256(haircutData)],
            "validation": try object(HaircutValidator.validate(input: input, haircut: haircut)),
            "mesh": try object(HairMeshCompiler.compile(input: input, haircut: haircut, radialSides: 3, radiusScale: 1))]
        func verify(_ result: [String: Any]) throws -> ProcessingCompilationResult {
            let data = try JSONSerialization.data(withJSONObject: result)
            return try ProcessingCompilationResult.verify(data: data, outputSHA256: EvidenceHash.sha256(data), inputData: inputData, haircutData: haircutData)
        }
        XCTAssertEqual(try verify(result).mesh.guideCount, 2)
        let validMesh = result["mesh"]
        var mesh = result["mesh"] as! [String: Any]
        var vertices = mesh["vertices"] as! [[String: Any]]
        vertices[0]["x"] = 0.4; mesh["vertices"] = vertices; result["mesh"] = mesh
        XCTAssertThrowsError(try verify(result))
        result["mesh"] = validMesh
        result["personalStyleVerified"] = true
        XCTAssertThrowsError(try verify(result))
    }
}
