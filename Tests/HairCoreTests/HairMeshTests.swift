import XCTest
@testable import HairCore

final class HairMeshTests: XCTestCase {
    func testTubeRingsPreserveCenterlineRadiusIdentityAndOutwardFaces() throws {
        let (input, haircut) = try SyntheticHaircut.create()
        let mesh = try HairMeshCompiler.compile(input: input, haircut: haircut)
        XCTAssertEqual(mesh.haircutSHA256, try HairArtifactHash.digest(haircut))
        XCTAssertEqual(mesh.batches.count, 2)
        XCTAssertEqual(mesh.normals.count, mesh.vertices.count)
        var offset = 0
        for guide in haircut.guides {
            for point in guide.points {
                let ring = Array(mesh.vertices[offset..<(offset+6)])
                XCTAssertLessThan((ring.reduce(.zero,+) / 6 - point).length, 1e-10)
                for vertex in ring { XCTAssertEqual((vertex-point).length, 0.00005, accuracy: 1e-10) }
                offset += 6
            }
            offset += 2
        }
        for normal in mesh.normals { XCTAssertEqual(normal.length, 1, accuracy: 1e-8) }
        for batch in mesh.batches {
            for index in stride(from: 0, to: batch.indices.count, by: 3) {
                let ids = batch.indices[index..<(index+3)].map(Int.init)
                XCTAssertTrue(ids.allSatisfy { mesh.vertices.indices.contains($0) })
                let a = mesh.vertices[ids[0]], b = mesh.vertices[ids[1]], c = mesh.vertices[ids[2]]
                XCTAssertGreaterThan((b-a).cross(c-a).length, 1e-12)
            }
        }
        XCTAssertEqual(try HairArtifactHash.digest(mesh), try HairArtifactHash.digest(HairMeshCompiler.compile(input: input, haircut: haircut)))
    }
    func testBudgetAndStaleRevisionAreRejectedAndEditChangesDerivativeIdentity() throws {
        let (input, cut) = try SyntheticHaircut.create()
        let old = try HairMeshCompiler.compile(input: input, haircut: cut)
        let edited = try HaircutEditor.apply(.init(baseSHA256: old.haircutSHA256, operation: .shortenToLength,
            region: .fringe, value: 0.07), to: cut, input: input)
        let new = try HairMeshCompiler.compile(input: input, haircut: edited.haircut)
        XCTAssertNotEqual(old.haircutSHA256, new.haircutSHA256)
        XCTAssertEqual(new.haircutRevision, 2)
        var stale = cut; stale.briefSHA256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try HairMeshCompiler.compile(input: input, haircut: stale))
        var large = cut
        large.guides = (0..<10_000).map { i in var guide = cut.guides[0]; guide.id = "g\(i)"; return guide }
        XCTAssertThrowsError(try HairMeshCompiler.compile(input: input, haircut: large))
    }
}
