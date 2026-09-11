import XCTest
@testable import HairCore

final class SurfaceRemesherTests: XCTestCase {
    private func plane(hole: Bool = false) -> ObservedSurface {
        var vertices: [SurfaceVertex] = []
        // Two offset samples of one plane, with a large unsupported center.
        for view in 0..<2 { for y in -12...12 { for x in -12...12 {
            if hole && abs(x) < 5 && abs(y) < 5 { continue }
            vertices.append(SurfaceVertex(position:Point3D(x:Double(x)*0.002+Double(view)*0.0005,
                y:Double(y)*0.002,z:0.2+Double(view)*0.0002),normal:Point3D(x:0,y:0,z:-1),
                observations:[SurfaceObservation(frameIndex:view,depthPixelIndex:vertices.count)]))
        } } }
        let frames = (0..<2).map { i in SurfaceFrameEvidence(captureID:"fixture",frameID:"\(i)",
            frameSHA256:String(repeating:"a",count:64),maskSHA256:String(repeating:"b",count:64),
            source:.syntheticFixture,referenceFromCamera:.identity,registration:nil,retainedSamples:625,skippedSamples:0) }
        return ObservedSurface(requestSHA256:String(repeating:"c",count:64),source:.syntheticFixture,
            vertices:vertices,triangles:[],frames:frames,notes:["Oriented plane test fixture"])
    }
    func testOffsetViewsProduceSinglePlaneWithOpenBoundary() throws {
        let source = plane(), result = try SurfaceRemesher.rebuild(source)
        XCTAssertGreaterThan(result.triangles.count,100)
        XCTAssertEqual(result.topology.nonManifoldEdges,0)
        XCTAssertEqual(result.topology.inconsistentWindingEdges,0)
        XCTAssertGreaterThan(result.topology.boundaryEdges,0)
        XCTAssertFalse(result.completeHead); XCTAssertFalse(result.suitableForHaircutFitting)
        XCTAssertEqual(result.sourceSurfaceSHA256,EvidenceHash.sha256(try ManifestCoding.encoder().encode(source)))
        for v in result.vertices {
            XCTAssertEqual(v.position.z,0.2001,accuracy:0.00011)
            XCTAssertLessThan(v.normal.z,-0.99)
        }
        for f in result.triangles {
            let p = f.map { result.vertices[$0].position }
            XCTAssertLessThan((p[1]-p[0]).cross(p[2]-p[0]).z,0)
        }
    }
    func testUnsupportedLargeHoleIsNotClosed() throws {
        let result = try SurfaceRemesher.rebuild(plane(hole:true))
        for f in result.triangles {
            let center = f.map { result.vertices[$0].position }.reduce(.zero,+)/3
            XCTAssertFalse(abs(center.x)<0.003 && abs(center.y)<0.003)
        }
    }
    func testCurvedFieldHasConsistentWindingAcrossTetrahedra() throws {
        var source = plane()
        for i in source.vertices.indices {
            let p = source.vertices[i].position
            source.vertices[i].position.z += 0.003*sin(p.x*220)*cos(p.y*160)
            source.vertices[i].normal = Point3D(x:0.66*cos(p.x*220)*cos(p.y*160),
                y:-0.48*sin(p.x*220)*sin(p.y*160),z:-1).unit
        }
        let result = try SurfaceRemesher.rebuild(source)
        XCTAssertGreaterThan(result.triangles.count,100)
        XCTAssertEqual(result.topology.nonManifoldEdges,0)
        XCTAssertEqual(result.topology.inconsistentWindingEdges,0)
        XCTAssertGreaterThan(result.vertices.map(\.position.z).max()! - result.vertices.map(\.position.z).min()!,0.002)
    }
    func testRejectsInvalidCloudAndUnboundedOptions() throws {
        var source = plane(); source.vertices[0].normal = .zero
        XCTAssertThrowsError(try SurfaceRemesher.rebuild(source))
        source = plane(); source.completeHead = true
        XCTAssertThrowsError(try SurfaceRemesher.rebuild(source))
        var options = SurfaceRemeshOptions(); options.voxelMeters = .nan
        XCTAssertThrowsError(try SurfaceRemesher.rebuild(plane(),options:options))
    }
    func testTopologyFindsOverlappingSheetsAndWinding() throws {
        let bad = try SurfaceTopology.inspect(triangles:[[0,1,2],[1,0,3],[0,1,4]],vertexCount:5)
        XCTAssertEqual(bad.nonManifoldEdges,1)
        let flipped = try SurfaceTopology.inspect(triangles:[[0,1,2],[0,1,3]],vertexCount:4)
        XCTAssertEqual(flipped.inconsistentWindingEdges,1)
        XCTAssertThrowsError(try SurfaceTopology.inspect(triangles:[[0,1,2],[2,1,0]],vertexCount:3))
    }
}
