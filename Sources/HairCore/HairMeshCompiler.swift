import Foundation

public struct HairMeshBatch: Codable, Sendable {
    public var materialID: String
    public var region: HairRegion
    public var indices: [UInt32]
}
public struct CompiledHairMesh: Codable, Sendable {
    public var method: String = "guide_tube_mesh_v1"
    public var haircutID: String
    public var haircutRevision: Int
    public var haircutSHA256: String
    public var scalpSHA256: String
    public var radiusScale: Double
    public var radialSides: Int
    public var vertices: [Point3D]
    public var normals: [Point3D]
    public var batches: [HairMeshBatch]
    public var materials: [HairMaterial]
    public var guideCount: Int
}

/// Batched, capped tube geometry preserving the exact input guide centerlines.
/// This is a render derivative, never the editable source or a physical simulation.
public enum HairMeshCompiler {
    public static func compile(input: HairDesignInput, haircut: HaircutRevision,
                               radialSides: Int = 6, radiusScale: Double = 1) throws -> CompiledHairMesh {
        _ = try HaircutValidator.validate(input: input, haircut: haircut)
        guard (3...12).contains(radialSides), radiusScale.isFinite, (1...100).contains(radiusScale) else {
            throw CaptureError.invalid("Invalid hair mesh resolution or diagnostic radius scale.")
        }
        let count = haircut.guides.reduce(0) { $0 + $1.points.count * radialSides + 2 }
        guard count <= 250_000 else { throw CaptureError.invalid("Hair mesh exceeds 250,000 vertices; explicit LOD generation is required.") }
        let materials = Dictionary(uniqueKeysWithValues: haircut.materials.map { ($0.id,$0) })
        var vertices: [Point3D] = [], normals: [Point3D] = [], batches: [HairMeshBatch] = []
        vertices.reserveCapacity(count); normals.reserveCapacity(count)
        var keys: [String: Int] = [:]
        for guide in haircut.guides {
            let key = guide.materialID + ":" + guide.region.rawValue
            let batchIndex: Int
            if let existing = keys[key] { batchIndex = existing }
            else {
                batchIndex = batches.count; keys[key] = batchIndex
                batches.append(HairMeshBatch(materialID: guide.materialID, region: guide.region, indices: []))
            }
            let radius = materials[guide.materialID]!.radiusMeters * radiusScale
            let offset = vertices.count
            var previousNormal: Point3D?
            var tangents: [Point3D] = []
            for i in guide.points.indices {
                let direction: Point3D
                if i == 0 { direction = guide.points[1] - guide.points[0] }
                else if i == guide.points.count - 1 { direction = guide.points[i] - guide.points[i-1] }
                else {
                    let centered = guide.points[i+1] - guide.points[i-1]
                    guard centered.length > 1e-9 else { throw CaptureError.invalid("A reversing guide has no stable tube tangent.") }
                    direction = centered
                }
                let tangent = direction.unit
                tangents.append(tangent)
                let projected = previousNormal.map { $0 - tangent * $0.dot(tangent) }
                let normal: Point3D
                if let projected, projected.length > 1e-6 { normal = projected.unit }
                else {
                    let axis = abs(tangent.x) < 0.8 ? Point3D(x: 1,y: 0,z: 0) : Point3D(x: 0,y: 1,z: 0)
                    normal = (axis - tangent * axis.dot(tangent)).unit
                }
                let bitangent = tangent.cross(normal).unit
                previousNormal = normal
                for side in 0..<radialSides {
                    let angle = 2 * Double.pi * Double(side) / Double(radialSides)
                    let radial = normal * cos(angle) + bitangent * sin(angle)
                    vertices.append(guide.points[i] + radial * radius); normals.append(radial)
                }
            }
            for ring in 0..<(guide.points.count-1) {
                for side in 0..<radialSides {
                    let next = (side+1) % radialSides
                    let a = UInt32(offset + ring * radialSides + side)
                    let b = UInt32(offset + ring * radialSides + next)
                    let c = UInt32(offset + (ring+1) * radialSides + side)
                    let d = UInt32(offset + (ring+1) * radialSides + next)
                    batches[batchIndex].indices.append(contentsOf: [a,b,c,b,d,c])
                }
            }
            let rootCenter = UInt32(vertices.count)
            vertices.append(guide.points[0]); normals.append(tangents[0] * -1)
            let tipCenter = UInt32(vertices.count)
            vertices.append(guide.points.last!); normals.append(tangents.last!)
            for side in 0..<radialSides {
                let next = (side+1) % radialSides
                let a = UInt32(offset+side), b = UInt32(offset+next)
                let c = UInt32(offset+(guide.points.count-1)*radialSides+side)
                let d = UInt32(offset+(guide.points.count-1)*radialSides+next)
                batches[batchIndex].indices.append(contentsOf: [rootCenter,b,a,tipCenter,c,d])
            }
        }
        return CompiledHairMesh(haircutID: haircut.id, haircutRevision: haircut.revision,
            haircutSHA256: try HairArtifactHash.digest(haircut), scalpSHA256: haircut.scalpSHA256,
            radiusScale: radiusScale, radialSides: radialSides, vertices: vertices, normals: normals,
            batches: batches, materials: haircut.materials, guideCount: haircut.guides.count)
    }
}
