import Foundation

public enum HairMeshRepresentation: String, Codable, Sendable {
    case tube, ribbon
}

/// Untextured, double-sided guide strips for representation experiments.
/// Width is the same diagnostic diameter as the tube; centerlines stay editable.
public enum HairRibbonCompiler {
    public static func compile(input: HairDesignInput, haircut: HaircutRevision,
                               radiusScale: Double = 1) throws -> CompiledHairMesh {
        _ = try HaircutValidator.validate(input: input, haircut: haircut)
        guard radiusScale.isFinite, (1...100).contains(radiusScale) else {
            throw CaptureError.invalid("Invalid ribbon diagnostic radius scale.")
        }
        let count = haircut.guides.reduce(0) { $0 + 2 * $1.points.count }
        guard count <= 250_000 else { throw CaptureError.invalid("Hair ribbon mesh exceeds 250,000 vertices.") }
        let materials = Dictionary(uniqueKeysWithValues: haircut.materials.map { ($0.id,$0) })
        var vertices: [Point3D] = [], normals: [Point3D] = [], batches: [HairMeshBatch] = []
        var keys: [String:Int] = [:]
        vertices.reserveCapacity(count); normals.reserveCapacity(count)
        for guide in haircut.guides {
            try Task.checkCancellation()
            let key = guide.materialID + ":" + guide.region.rawValue
            let batch: Int
            if let existing = keys[key] { batch = existing }
            else {
                batch = batches.count; keys[key] = batch
                batches.append(HairMeshBatch(materialID:guide.materialID,region:guide.region,indices:[]))
            }
            let radius = materials[guide.materialID]!.radiusMeters * radiusScale
            let offset = vertices.count
            var previousWidth: Point3D?
            for i in guide.points.indices {
                let direction: Point3D
                if i == 0 { direction = guide.points[1]-guide.points[0] }
                else if i == guide.points.count-1 { direction = guide.points[i]-guide.points[i-1] }
                else { direction = guide.points[i+1]-guide.points[i-1] }
                guard direction.length > 1e-9 else { throw CaptureError.invalid("A reversing guide has no stable ribbon tangent.") }
                let tangent = direction.unit
                let projected = previousWidth.map { $0-tangent*$0.dot(tangent) }
                let width: Point3D
                if let projected, projected.length > 1e-6 { width = projected.unit }
                else {
                    let axis = abs(tangent.x) < 0.8 ? Point3D(x:1,y:0,z:0) : Point3D(x:0,y:1,z:0)
                    width = (axis-tangent*axis.dot(tangent)).unit
                }
                previousWidth = width
                let normal = tangent.cross(width).unit
                vertices.append(guide.points[i]+width*radius); vertices.append(guide.points[i]-width*radius)
                normals.append(normal); normals.append(normal)
            }
            for i in 0..<(guide.points.count-1) {
                let a=UInt32(offset+2*i), b=a+1, c=a+2, d=a+3
                batches[batch].indices.append(contentsOf:[a,b,c,b,d,c])
            }
        }
        return CompiledHairMesh(method:"guide_ribbon_mesh_v1",haircutID:haircut.id,haircutRevision:haircut.revision,
            haircutSHA256:try HairArtifactHash.digest(haircut),scalpSHA256:haircut.scalpSHA256,
            radiusScale:radiusScale,radialSides:2,vertices:vertices,normals:normals,batches:batches,
            materials:haircut.materials,guideCount:haircut.guides.count)
    }
}
