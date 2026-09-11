import Foundation

public struct SurfaceRemeshOptions: Codable, Sendable {
    public var voxelMeters: Double = 0.002
    public var supportRadiusMeters: Double = 0.006
    public var minimumNormalAgreement: Double = 0.8
    public init() {}
}

public struct RemeshedVertex: Codable, Sendable {
    public var position: Point3D
    public var normal: Point3D
}

public struct SurfaceTopology: Codable, Sendable {
    public var boundaryEdges: Int
    public var nonManifoldEdges: Int
    public var inconsistentWindingEdges: Int

    public static func inspect(triangles: [[Int]], vertexCount: Int) throws -> Self {
        var incidence: [Edge: (count: Int, direction: Int)] = [:]
        var unique = Set<[Int]>()
        for triangle in triangles {
            guard triangle.count == 3, Set(triangle).count == 3,
                  triangle.allSatisfy({ $0 >= 0 && $0 < vertexCount }),
                  unique.insert(triangle.sorted()).inserted else {
                throw CaptureError.invalid("Invalid or duplicate surface triangle.")
            }
            for i in 0..<3 {
                let a = triangle[i], b = triangle[(i+1)%3], key = Edge(a,b)
                let old = incidence[key] ?? (0,0)
                incidence[key] = (old.count+1, old.direction + (a < b ? 1 : -1))
            }
        }
        return Self(boundaryEdges: incidence.values.filter { $0.count == 1 }.count,
                    nonManifoldEdges: incidence.values.filter { $0.count > 2 }.count,
                    inconsistentWindingEdges: incidence.values.filter { $0.count == 2 && $0.direction != 0 }.count)
    }
}

public struct RemeshedSurface: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var method = "local_oriented_point_field_marching_tetrahedra_v1"
    public var sourceSurfaceSHA256: String
    public var options: SurfaceRemeshOptions
    public var source: CaptureSource
    public var frames: [SurfaceFrameEvidence]
    public var coordinateConvention: String
    public var vertices: [RemeshedVertex]
    public var triangles: [[Int]]
    public var topology: SurfaceTopology
    public var completeHead = false
    public var suitableForHaircutFitting = false
    public var notes: [String]
}

private struct Edge: Hashable {
    var a: Int; var b: Int
    init(_ a: Int, _ b: Int) { self.a = min(a,b); self.b = max(a,b) }
}

/// Experimental local reconstruction from an already registered oriented cloud.
/// This is NOT projective TSDF integration: no camera-ray visibility model is
/// assumed. Unknown grid nodes remain unknown; no global Poisson closure occurs.
public enum SurfaceRemesher {
    private struct Key: Hashable, Comparable {
        var x: Int; var y: Int; var z: Int
        static func < (a: Self, b: Self) -> Bool {
            if a.z != b.z { return a.z < b.z }
            if a.y != b.y { return a.y < b.y }
            return a.x < b.x
        }
        func plus(_ p: Self) -> Self { Self(x:x+p.x,y:y+p.y,z:z+p.z) }
        func point(_ h: Double) -> Point3D { Point3D(x:Double(x)*h,y:Double(y)*h,z:Double(z)*h) }
    }
    private struct Field {
        var weight = 0.0
        var distance = 0.0
        var normal = Point3D.zero
        var value: Double { distance / weight }
    }

    public static func rebuild(_ source: ObservedSurface, options: SurfaceRemeshOptions = .init()) throws -> RemeshedSurface {
        let h = options.voxelMeters, radius = options.supportRadiusMeters
        guard (0.001...0.005).contains(h), radius.isFinite,
              radius >= 2*h, radius <= min(4*h,0.015),
              (0.5...0.99).contains(options.minimumNormalAgreement),
              !source.vertices.isEmpty, source.vertices.count <= 250_000,
              !source.frames.isEmpty, source.frames.count <= 8,
              !source.completeHead, !source.includesInferredAnatomy else {
            throw CaptureError.invalid("Remeshing requires a bounded partial observed cloud and valid local support options.")
        }
        var grid: [Key: Field] = [:]
        let extent = Int(ceil(radius/h))
        // The local signed distance is an average of nearby tangent planes.
        // Opposing/incoherent normals invalidate support rather than create a cap.
        for vertex in source.vertices {
            let p = vertex.position, n = vertex.normal
            guard p.finite, p.length <= 10, n.finite, abs(n.length-1) < 0.01,
                  !vertex.observations.isEmpty,
                  vertex.observations.allSatisfy({ $0.frameIndex >= 0 && $0.frameIndex < source.frames.count && $0.depthPixelIndex >= 0 }) else {
                throw CaptureError.invalid("Invalid oriented observation in remesh source.")
            }
            let center = Key(x:Int(floor(p.x/h)),y:Int(floor(p.y/h)),z:Int(floor(p.z/h)))
            for z in -extent...extent { for y in -extent...extent { for x in -extent...extent {
                let key = center.plus(Key(x:x,y:y,z:z)), delta = key.point(h)-p
                let d2 = delta.dot(delta)
                guard d2 < radius*radius else { continue }
                let distance = delta.dot(n)
                // Compact support, tapering to zero at its boundary.
                let weight = pow(1-d2/(radius*radius),2)
                var field = grid[key] ?? Field()
                field.weight += weight; field.distance += weight*distance
                field.normal = field.normal + n*weight
                grid[key] = field
            } } }
            guard grid.count <= 1_000_000 else { throw CaptureError.invalid("Remesh exceeds one million supported grid nodes. Increase voxel size or reduce capture extent.") }
        }
        grid = grid.filter { $0.value.weight >= 0.05 && $0.value.normal.length / $0.value.weight >= options.minimumNormalAgreement }
        let keys = grid.keys.sorted()
        let ids = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element,$0.offset) })
        let offsets = [Key(x:0,y:0,z:0),Key(x:1,y:0,z:0),Key(x:0,y:1,z:0),Key(x:1,y:1,z:0),
                       Key(x:0,y:0,z:1),Key(x:1,y:0,z:1),Key(x:0,y:1,z:1),Key(x:1,y:1,z:1)]
        // Six consistently tiled tetrahedra around cube diagonal 0--7.
        let tetrahedra = [[0,1,3,7],[0,3,2,7],[0,2,6,7],[0,6,4,7],[0,4,5,7],[0,5,1,7]]
        var vertices: [RemeshedVertex] = [], triangles: [[Int]] = [], edgeVertices: [Edge:Int] = [:]
        func scalar(_ key: Key) -> Double {
            let value = grid[key]!.value
            return abs(value) <= 1e-12 ? 1e-12 : value
        }
        func crossing(_ a: Int, _ b: Int, _ cube: [Key]) -> Int {
            let ka = cube[a], kb = cube[b], edge = Edge(ids[ka]!,ids[kb]!)
            if let index = edgeVertices[edge] { return index }
            let fa = grid[ka]!, fb = grid[kb]!
            // Tiny positive tie break avoids duplicate vertices on exact-zero
            // grid corners without moving measured surfaces by a useful amount.
            let va = scalar(ka), vb = scalar(kb)
            let t = va/(va-vb)
            let p = ka.point(h)*(1-t)+kb.point(h)*t
            let n = (fa.normal.unit*(1-t)+fb.normal.unit*t).unit
            let index = vertices.count
            vertices.append(RemeshedVertex(position:p,normal:n)); edgeVertices[edge] = index
            return index
        }
        func emit(_ a: Int, _ b: Int, _ c: Int, toward gradient: Point3D) {
            let p = vertices[a], q = vertices[b], r = vertices[c]
            let normal = (q.position-p.position).cross(r.position-p.position)
            guard normal.length > 1e-18 else { return }
            triangles.append(normal.dot(gradient) >= 0 ? [a,b,c] : [a,c,b])
        }
        for key in keys {
            let cube = offsets.map { key.plus($0) }
            // All corners must have actual local support. Do not treat unknown
            // space as positive/free space and close missing anatomy.
            guard cube.allSatisfy({ grid[$0] != nil }) else { continue }
            for tetra in tetrahedra {
                let points = tetra.map { cube[$0].point(h) }
                let values = tetra.map { scalar(cube[$0]) }
                let e1 = points[1]-points[0], e2 = points[2]-points[0], e3 = points[3]-points[0]
                // Orient against this tetrahedron's scalar-field gradient. The
                // averaged measured normals can disagree on adjacent tiny faces.
                let gradient = (e2.cross(e3)*(values[1]-values[0]) + e3.cross(e1)*(values[2]-values[0]) + e1.cross(e2)*(values[3]-values[0])) / e1.dot(e2.cross(e3))
                let inside = tetra.filter { scalar(cube[$0]) < 0 }
                let outside = tetra.filter { !inside.contains($0) }
                if inside.count == 1 || inside.count == 3 {
                    let singleton = inside.count == 1 ? inside[0] : outside[0]
                    let other = inside.count == 1 ? outside : inside
                    emit(crossing(singleton,other[0],cube),crossing(singleton,other[1],cube),crossing(singleton,other[2],cube),toward:gradient)
                } else if inside.count == 2 {
                    let a = crossing(inside[0],outside[0],cube), b = crossing(inside[0],outside[1],cube)
                    let c = crossing(inside[1],outside[0],cube), d = crossing(inside[1],outside[1],cube)
                    emit(a,b,c,toward:gradient); emit(b,d,c,toward:gradient)
                }
            }
            guard vertices.count <= 250_000, triangles.count <= 500_000 else {
                throw CaptureError.invalid("Remesh exceeds output geometry budget.")
            }
        }
        guard !triangles.isEmpty else { throw CaptureError.invalid("No supported surface crossing survived remeshing.") }
        let topology = try SurfaceTopology.inspect(triangles:triangles,vertexCount:vertices.count)
        guard topology.nonManifoldEdges == 0, topology.inconsistentWindingEdges == 0 else {
            throw CaptureError.invalid("Remeshed topology failed: \(topology.nonManifoldEdges) nonmanifold edges, \(topology.inconsistentWindingEdges) inconsistent winding edges. Inspect registration and local normal consistency.")
        }
        return RemeshedSurface(sourceSurfaceSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(source)),
            options:options,source:source.source,frames:source.frames,coordinateConvention:source.coordinateConvention,
            vertices:vertices,triangles:triangles,topology:topology,
            notes:["Locally interpolated surface from registered oriented measurements; vertices are not direct sensor samples.",
                   "Local tangent-plane field, not projective TSDF; camera visibility and dense overlap remain unvalidated.",
                   "Only the local support neighborhood is sampled. Interpolation may bridge small holes or extend mask boundaries by up to the support radius; this is not measured anatomy.",
                   "Boundary edges are allowed. Edge checks do not prove vertex-manifoldness, absence of self-intersections, or anatomical accuracy.",
                   "Not complete head geometry and not approved for haircut fitting."])
    }
}
