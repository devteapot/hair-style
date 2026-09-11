import XCTest
@testable import HairCore

final class HairRibbonTests: XCTestCase {
    func testStripCentersWidthWindingIdentityAndReducedGeometry() throws {
        let (input,cut)=try SyntheticHaircut.create()
        let mesh=try HairRibbonCompiler.compile(input:input,haircut:cut,radiusScale:8)
        let tube=try HairMeshCompiler.compile(input:input,haircut:cut,radialSides:3,radiusScale:8)
        XCTAssertEqual(mesh.haircutSHA256,tube.haircutSHA256);XCTAssertEqual(mesh.method,"guide_ribbon_mesh_v1")
        XCTAssertLessThan(mesh.vertices.count,tube.vertices.count)
        XCTAssertLessThan(mesh.batches.flatMap(\.indices).count,tube.batches.flatMap(\.indices).count)
        var offset=0
        for g in cut.guides {
            let radius=cut.materials.first { $0.id==g.materialID }!.radiusMeters*8
            for p in g.points {
                let a=mesh.vertices[offset],b=mesh.vertices[offset+1]
                XCTAssertLessThan(((a+b)/2-p).length,1e-12)
                XCTAssertEqual((a-b).length,2*radius,accuracy:1e-12)
                XCTAssertEqual(mesh.normals[offset].length,1,accuracy:1e-12);offset+=2
            }
        }
        for batch in mesh.batches {
            for j in stride(from:0,to:batch.indices.count,by:3) {
                let i=batch.indices[j..<(j+3)].map(Int.init)
                let face=(mesh.vertices[i[1]]-mesh.vertices[i[0]]).cross(mesh.vertices[i[2]]-mesh.vertices[i[0]])
                XCTAssertGreaterThan(face.length,1e-12)
                XCTAssertGreaterThan(face.dot(mesh.normals[i[0]]),0)
            }
        }
        XCTAssertEqual(try HairArtifactHash.digest(mesh),try HairArtifactHash.digest(HairRibbonCompiler.compile(input:input,haircut:cut,radiusScale:8)))
    }
    func testRejectsInvalidScaleAndStaleSource() throws {
        let (input,cut)=try SyntheticHaircut.create()
        XCTAssertThrowsError(try HairRibbonCompiler.compile(input:input,haircut:cut,radiusScale:.nan))
        var stale=cut;stale.briefSHA256=String(repeating:"0",count:64)
        XCTAssertThrowsError(try HairRibbonCompiler.compile(input:input,haircut:stale))
    }
}
