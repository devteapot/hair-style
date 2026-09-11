import Foundation

/// Vertex selections on the observed surface, never on a mirrored presentation.
/// Eye centers are landmark estimates; this does not measure eyeball centers.
public struct AnatomicalSelection: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var surfaceSHA256: String
    public var anatomicalLeftEyeVertex: Int
    public var anatomicalRightEyeVertex: Int
    public var superiorVertex: Int
    public var anteriorVertex: Int
    public var method: String
}

public struct CanonicalObservedSurface: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var coordinateConvention: String = "eye_midpoint_x_anatomical_left_y_up_z_anterior_meters"
    public var sourceSurfaceSHA256: String
    public var selection: AnatomicalSelection
    public var canonicalFromReference: RigidTransform
    public var referenceFromCanonical: RigidTransform
    public var source: CaptureSource
    public var vertices: [SurfaceVertex]
    public var triangles: [[Int]]
    /// These transforms remain in the original reference camera frame. Compose
    /// canonicalFromReference with referenceFromCamera to obtain canonical poses.
    public var sourceFrameEvidence: [SurfaceFrameEvidence]
    public var eyeLandmarkSeparationMeters: Double
    public var anteriorCheckMeters: Double
    public var completeHead: Bool = false
    public var inferredScalp: Bool = false
    public var notes: [String]
}

public enum AnatomicalFrame {
    public static func canonicalize(_ surface: ObservedSurface, selection: AnatomicalSelection) throws -> CanonicalObservedSurface {
        guard selection.schemaVersion == 1, !selection.method.isEmpty,
              selection.surfaceSHA256 == (try HairArtifactHash.digest(surface)),
              surface.schemaVersion == 1,
              surface.coordinateConvention == "reference_optical_x_right_y_down_z_forward_meters",
              !surface.completeHead, !surface.includesInferredAnatomy,
              (4...250_000).contains(surface.vertices.count), (1...500_000).contains(surface.triangles.count),
              (1...8).contains(surface.frames.count) else { throw CaptureError.invalid("Anatomical selection does not match a partial observed surface.") }
        let selected = [selection.anatomicalLeftEyeVertex, selection.anatomicalRightEyeVertex, selection.superiorVertex, selection.anteriorVertex]
        let expectedSource: CaptureSource = surface.frames.contains(where: { $0.source == .syntheticFixture }) ? .syntheticFixture : .sensor
        guard surface.source == expectedSource,
              surface.frames.allSatisfy({ UUID(uuidString: $0.captureID) != nil && UUID(uuidString: $0.frameID) != nil &&
                  HairArtifactHash.valid($0.frameSHA256) && HairArtifactHash.valid($0.maskSHA256) &&
                  $0.referenceFromCamera.isValid && $0.retainedSamples >= 0 && $0.skippedSamples >= 0 }) else {
            throw CaptureError.invalid("Surface frame evidence or synthetic provenance is inconsistent.")
        }
        guard Set(selected).count == 4, selected.allSatisfy({ surface.vertices.indices.contains($0) }) else {
            throw CaptureError.invalid("Anatomical landmarks must reference four distinct surface vertices.")
        }
        for v in surface.vertices {
            guard v.position.finite, v.position.length <= 10, v.normal.finite, abs(v.normal.length-1) < 1e-5,
                  !v.observations.isEmpty, v.observations.count <= 8,
                  v.observations.allSatisfy({ surface.frames.indices.contains($0.frameIndex) && $0.depthPixelIndex >= 0 && $0.depthPixelIndex < 1_000_000 }) else {
                throw CaptureError.invalid("Invalid observed vertex or source-frame reference.")
            }
        }
        var used = Set<Int>()
        for t in surface.triangles {
            guard t.count == 3, Set(t).count == 3, t.allSatisfy({ surface.vertices.indices.contains($0) }),
                  (surface.vertices[t[1]].position-surface.vertices[t[0]].position)
                    .cross(surface.vertices[t[2]].position-surface.vertices[t[0]].position).length > 1e-10 else {
                throw CaptureError.invalid("Invalid observed triangle.")
            }
            used.formUnion(t)
        }
        guard selected.allSatisfy(used.contains) else { throw CaptureError.invalid("A selected landmark is not part of the observed mesh.") }
        let left = surface.vertices[selected[0]].position, right = surface.vertices[selected[1]].position
        let origin = (left+right)/2
        let separation = (left-right).length
        guard (0.02...0.12).contains(separation) else { throw CaptureError.invalid("Eye-landmark separation is outside the provisional 20–120 mm range. Check units and selection.") }
        let x = (left-right).unit
        let superior = surface.vertices[selected[2]].position-origin
        let orthogonalUp = superior-x*superior.dot(x)
        guard (0.01...0.25).contains(orthogonalUp.length), superior.length <= 0.3 else {
            throw CaptureError.invalid("The superior landmark cannot establish a stable upward direction.")
        }
        let y = orthogonalUp.unit, z = x.cross(y).unit
        let anterior = surface.vertices[selected[3]].position-origin
        let forward = anterior.dot(z)
        guard anterior.length <= 0.2, (0.003...0.1).contains(forward) else {
            throw CaptureError.invalid("Anterior landmark lies behind or too close to the eye/superior plane. Check anatomical left/right and landmark selection.")
        }
        let toCanonical = RigidTransform(rowMajor: [x.x,x.y,x.z,-x.dot(origin), y.x,y.y,y.z,-y.dot(origin), z.x,z.y,z.z,-z.dot(origin), 0,0,0,1])
        let toReference = RigidTransform(rowMajor: [x.x,y.x,z.x,origin.x, x.y,y.y,z.y,origin.y, x.z,y.z,z.z,origin.z, 0,0,0,1])
        guard toCanonical.isValid, toReference.isValid else { throw CaptureError.invalid("Anatomical frame is not a proper rigid transform.") }
        let vertices = surface.vertices.map { vertex in
            var result = vertex
            result.position = toCanonical.apply(vertex.position)
            result.normal = Point3D(x: vertex.normal.dot(x), y: vertex.normal.dot(y), z: vertex.normal.dot(z))
            return result
        }
        return CanonicalObservedSurface(sourceSurfaceSHA256: selection.surfaceSHA256, selection: selection,
            canonicalFromReference: toCanonical, referenceFromCanonical: toReference, source: surface.source,
            vertices: vertices, triangles: surface.triangles, sourceFrameEvidence: surface.frames,
            eyeLandmarkSeparationMeters: separation, anteriorCheckMeters: forward,
            notes: ["Landmark-defined anatomical frame; eye centers and upward direction are estimates from the selected surface.",
                "A superior surface point defines the eye/superior plane. Its anatomical interpretation requires review; the anterior point checks orientation only.",
                "Rigid rotation/translation only. No scale adjustment, deformation, missing-surface filling or scalp completion.",
                "Source-frame transforms retain the original reference camera coordinates. Original pixel observations and topology are preserved.",
                "Thresholds are provisional selection sanity checks, not physical accuracy or repeatability measurements."])
    }
}
