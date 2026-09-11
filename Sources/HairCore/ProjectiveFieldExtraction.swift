import Foundation

struct ProjectiveGridKey: Hashable, Comparable {
    var x: Int; var y: Int; var z: Int
    static func < (a: Self, b: Self) -> Bool {
        if a.z != b.z { return a.z < b.z }
        if a.y != b.y { return a.y < b.y }
        return a.x < b.x
    }
    func plus(_ p: Self) -> Self { Self(x: x+p.x, y: y+p.y, z: z+p.z) }
    func point(_ h: Double) -> Point3D { Point3D(x: Double(x)*h, y: Double(y)*h, z: Double(z)*h) }
}

/// Isolated scalar-field extractor for the projective experiment. Normals come
/// from the extracted triangles, never noisy one-pixel measured derivatives.
enum ProjectiveFieldExtraction {
    struct Mesh {
        var vertices: [RemeshedVertex]
        var triangles: [[Int]]
        var topology: SurfaceTopology
    }
    private struct Edge: Hashable {
        var a: Int; var b: Int
        init(_ a: Int, _ b: Int) { self.a = min(a,b); self.b = max(a,b) }
    }
    static func extract(_ grid: [ProjectiveGridKey: Double], spacing h: Double) throws -> Mesh {
        guard (0.001...0.005).contains(h), grid.count <= 1_000_000,
              grid.values.allSatisfy(\.isFinite) else { throw CaptureError.invalid("Invalid projective scalar field.") }
        let keys = grid.keys.sorted()
        let ids = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element,$0.offset) })
        let offsets = [ProjectiveGridKey(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:1,z:0),.init(x:1,y:1,z:0),
                       .init(x:0,y:0,z:1),.init(x:1,y:0,z:1),.init(x:0,y:1,z:1),.init(x:1,y:1,z:1)]
        let tetrahedra = [[0,1,3,7],[0,3,2,7],[0,2,6,7],[0,6,4,7],[0,4,5,7],[0,5,1,7]]
        var positions: [Point3D] = [], triangles: [[Int]] = [], crossings: [Edge: Int] = [:]
        func scalar(_ key: ProjectiveGridKey) -> Double {
            let value = grid[key]!
            return abs(value) <= 1e-12 ? 1e-12 : value
        }
        func crossing(_ a: Int, _ b: Int, _ cube: [ProjectiveGridKey]) -> Int {
            let ka = cube[a], kb = cube[b], edge = Edge(ids[ka]!,ids[kb]!)
            if let index = crossings[edge] { return index }
            let va = scalar(ka), vb = scalar(kb), t = va/(va-vb)
            let p = ka.point(h)*(1-t)+kb.point(h)*t
            let index = positions.count; positions.append(p); crossings[edge] = index
            return index
        }
        func emit(_ a: Int, _ b: Int, _ c: Int, gradient: Point3D) {
            let normal = (positions[b]-positions[a]).cross(positions[c]-positions[a])
            guard normal.length > 1e-18 else { return }
            triangles.append(normal.dot(gradient) >= 0 ? [a,b,c] : [a,c,b])
        }
        for key in keys {
            let cube = offsets.map { key.plus($0) }
            guard cube.allSatisfy({ grid[$0] != nil }) else { continue }
            for tetra in tetrahedra {
                let p = tetra.map { cube[$0].point(h) }, v = tetra.map { scalar(cube[$0]) }
                let e1 = p[1]-p[0], e2 = p[2]-p[0], e3 = p[3]-p[0]
                let gradient = (e2.cross(e3)*(v[1]-v[0])+e3.cross(e1)*(v[2]-v[0])+e1.cross(e2)*(v[3]-v[0])) / e1.dot(e2.cross(e3))
                let inside = tetra.filter { scalar(cube[$0]) < 0 }, outside = tetra.filter { scalar(cube[$0]) >= 0 }
                if inside.count == 1 || inside.count == 3 {
                    let one = inside.count == 1 ? inside[0] : outside[0], other = inside.count == 1 ? outside : inside
                    emit(crossing(one,other[0],cube),crossing(one,other[1],cube),crossing(one,other[2],cube),gradient:gradient)
                } else if inside.count == 2 {
                    let a = crossing(inside[0],outside[0],cube), b = crossing(inside[0],outside[1],cube)
                    let c = crossing(inside[1],outside[0],cube), d = crossing(inside[1],outside[1],cube)
                    emit(a,b,c,gradient:gradient); emit(b,d,c,gradient:gradient)
                }
            }
            guard positions.count <= 250_000, triangles.count <= 500_000 else { throw CaptureError.invalid("Projective extraction exceeds geometry budget.") }
        }
        guard !triangles.isEmpty else { throw CaptureError.invalid("No supported projective surface crossing.") }
        return try finish(positions: positions, triangles: triangles)
    }

    static func retaining(_ mesh: Mesh, supported: [Bool]) throws -> Mesh {
        guard supported.count == mesh.vertices.count else { throw CaptureError.invalid("Projective support count mismatch.") }
        return try finish(positions: mesh.vertices.map(\.position), triangles: mesh.triangles.filter { $0.allSatisfy { supported[$0] } })
    }

    private static func finish(positions inputPositions: [Point3D], triangles inputTriangles: [[Int]]) throws -> Mesh {
        var positions = inputPositions, triangles = inputTriangles
        guard !triangles.isEmpty else { throw CaptureError.invalid("No triangles retain projective support.") }
        // Only emitted vertices survive, with area-weighted geometric normals.
        let used = Set(triangles.flatMap { $0 }).sorted()
        let remap = Dictionary(uniqueKeysWithValues: used.enumerated().map { ($0.element,$0.offset) })
        positions = used.map { positions[$0] }; triangles = triangles.map { $0.map { remap[$0]! } }
        var normals = [Point3D](repeating: .zero, count: positions.count)
        for t in triangles {
            let n = (positions[t[1]]-positions[t[0]]).cross(positions[t[2]]-positions[t[0]])
            for index in t { normals[index] = normals[index]+n }
        }
        guard normals.allSatisfy({ $0.finite && $0.length > 1e-18 }) else { throw CaptureError.invalid("Unstable projective mesh normals.") }
        let topology = try SurfaceTopology.inspect(triangles: triangles, vertexCount: positions.count)
        guard topology.nonManifoldEdges == 0, topology.inconsistentWindingEdges == 0 else {
            throw CaptureError.invalid("Projective mesh failed edge topology checks.")
        }
        return Mesh(vertices: positions.indices.map { RemeshedVertex(position: positions[$0], normal: normals[$0].unit) },
                    triangles: triangles, topology: topology)
    }
}
