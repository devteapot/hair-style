import Foundation

public enum HairRegion: String, Codable, CaseIterable, Sendable {
    case fringe, top, crown, anatomicalLeft = "anatomical_left", anatomicalRight = "anatomical_right", nape
}
public enum ObservationOrigin: String, Codable, Sendable {
    case observed, inferred, userSupplied = "user_supplied", defaultValue = "default", unknown
}
public enum EvidenceQuality: String, Codable, Sendable { case high, medium, low, unknown }
public enum ScalpSurfaceOrigin: String, Codable, Sendable { case observed, inferred, synthetic }

/// This is a scalp binding surface in anatomical coordinates, not an assertion
/// that hidden anatomy has been measured or that completion has succeeded.
public struct ScalpProfile: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var id: String
    public var revision: Int
    public var subjectSessionID: String
    public var coordinateConvention: String = "eye_midpoint_x_anatomical_left_y_up_z_anterior_meters"
    public var vertices: [Point3D]
    public var triangles: [[Int]]
    public var triangleOrigins: [ScalpSurfaceOrigin]
    public var sourceSHA256: [String]
    public var method: String
}

public struct RegionalLengthObservation: Codable, Sendable {
    public var region: HairRegion
    public var maximumAvailableMeters: Double?
    public var origin: ObservationOrigin
    public var quality: EvidenceQuality
    public var evidenceReferences: [String]
    public var method: String
}

/// Length profile with optional scalp-bound appearance observations.
/// Missing characteristics or regions are not positive evidence.
public struct HairLengthProfile: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var id: String
    public var revision: Int
    public var subjectSessionID: String
    public var regions: [RegionalLengthObservation]
    public var characteristics: HairCharacteristics? = nil
}

public enum DesignMode: String, Codable, Sendable { case autonomous, guided }
public struct RegionalLengthLimit: Codable, Sendable {
    public var region: HairRegion
    public var minimumMeters: Double
    public var maximumMeters: Double
    public var origin: ObservationOrigin
}
public struct HairDesignBrief: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var id: String
    public var scalpSHA256: String
    public var hairProfileSHA256: String
    public var mode: DesignMode
    public var lengthLimits: [RegionalLengthLimit]
    public var allowGrowth: Bool
    public var stylingAssumptions: [String]
    public var seed: UInt64
    /// Optional inferred-envelope constraint, bound into the brief hash so
    /// edits and repository replay retain the same geometric requirement.
    public var envelopeGuard: EllipsoidGuideGuardRequest? = nil
    public var stylingPreferences: StylingPreferences? = nil
}
public struct HairDesignInput: Codable, Sendable {
    public var scalp: ScalpProfile
    public var hairProfile: HairLengthProfile
    public var brief: HairDesignBrief
}

public struct ScalpBinding: Codable, Sendable {
    public var triangleIndex: Int
    public var barycentric: [Double]
    public var normalOffsetMeters: Double
}
public struct HairGuide: Codable, Sendable {
    public var id: String
    public var region: HairRegion
    public var materialID: String
    public var root: ScalpBinding
    /// Ordered from the scalp root to the tip, in the canonical head frame.
    public var points: [Point3D]
}
public struct HairMaterial: Codable, Sendable {
    public var id: String
    public var linearRGB: [Double]
    public var roughness: Double
    public var radiusMeters: Double
}
public enum HairGenerationOrigin: String, Codable, Sendable {
    case model, proceduralBaseline = "procedural_baseline", syntheticFixture = "synthetic_fixture"
}
public struct HairGenerationRecord: Codable, Sendable {
    public var origin: HairGenerationOrigin
    public var method: String
    public var version: String
    public var seed: UInt64
    /// Actual neural sampler seed, independent of the design brief's seed. Nil for unknown legacy provenance.
    public var modelSamplingSeed: UInt64? = nil
}
public enum HairEditOperation: String, Codable, Sendable {
    case shortenToLength = "shorten_to_length", scaleLateralVolume = "scale_lateral_volume"
    case rotateAroundRootNormal = "rotate_around_root_normal"
}
public struct HairEdit: Codable, Sendable {
    public var baseSHA256: String
    public var operation: HairEditOperation
    public var region: HairRegion
    /// Meters for shortening; dimensionless factor for lateral volume; degrees
    /// for right-handed rotation about each attachment's outward scalp normal.
    public var value: Double
    public init(baseSHA256: String, operation: HairEditOperation, region: HairRegion, value: Double) {
        self.baseSHA256 = baseSHA256; self.operation = operation; self.region = region; self.value = value
    }
}
public struct HaircutRevision: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var id: String
    public var revision: Int
    public var scalpSHA256: String
    public var hairProfileSHA256: String
    public var briefSHA256: String
    public var parentSHA256: String?
    public var edit: HairEdit?
    public var generation: HairGenerationRecord
    public var materials: [HairMaterial]
    public var guides: [HairGuide]
}
public enum HairFeasibility: String, Codable, Sendable {
    case uncertain, requiresGrowth = "requires_growth", requiresStyling = "requires_styling"
}
public struct HairValidationReport: Codable, Sendable {
    public var method: String = "scalp_binding_and_length_v1"
    public var haircutSHA256: String
    public var guideCount: Int
    public var minimumLengthMeters: Double
    public var maximumLengthMeters: Double
    public var feasibility: [HairFeasibility]
    public var growthRegions: [HairRegion]
    public var uncertainLengthRegions: [HairRegion]
    public var synthetic: Bool
    public var checksCompleted: [String]
    public var checksOutstanding: [String]
    public var publishableAsValidatedDesign: Bool = false
}

public enum HairArtifactHash {
    /// Canonical encoding within this Swift schema/version. Persist exact bytes
    /// for transport; do not assume another JSON encoder hashes identically.
    public static func digest<T: Encodable>(_ value: T) throws -> String {
        EvidenceHash.sha256(try ManifestCoding.encoder().encode(value))
    }
    static func valid(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

public enum HaircutValidator {
    public static func validate(input: HairDesignInput, haircut: HaircutRevision) throws -> HairValidationReport {
        try validateInput(input)
        let scalpHash = try HairArtifactHash.digest(input.scalp)
        let profileHash = try HairArtifactHash.digest(input.hairProfile)
        let briefHash = try HairArtifactHash.digest(input.brief)
        guard haircut.schemaVersion == 1, UUID(uuidString: haircut.id) != nil, (1...1_000_000).contains(haircut.revision),
              haircut.scalpSHA256 == scalpHash, haircut.hairProfileSHA256 == profileHash, haircut.briefSHA256 == briefHash,
              !haircut.generation.method.isEmpty, !haircut.generation.version.isEmpty,
              haircut.generation.seed == input.brief.seed else { throw CaptureError.invalid("Haircut schema or source revision binding is invalid.") }
        if haircut.revision == 1 {
            guard haircut.parentSHA256 == nil, haircut.edit == nil else { throw CaptureError.invalid("Initial haircut cannot declare a parent or edit.") }
        } else {
            guard let parent = haircut.parentSHA256, HairArtifactHash.valid(parent),
                  let edit = haircut.edit, edit.baseSHA256 == parent, edit.value.isFinite else {
                throw CaptureError.invalid("Edited haircut must retain its parent hash and operation.")
            }
        }
        guard (1...64).contains(haircut.materials.count), (1...20_000).contains(haircut.guides.count) else {
            throw CaptureError.invalid("Haircut exceeds material/guide processing limits.")
        }
        var materialIDs = Set<String>()
        for m in haircut.materials {
            guard identifier(m.id), materialIDs.insert(m.id).inserted, m.linearRGB.count == 3,
                  m.linearRGB.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  m.roughness.isFinite, (0...1).contains(m.roughness),
                  m.radiusMeters.isFinite, (0.000001...0.005).contains(m.radiusMeters) else {
                throw CaptureError.invalid("Invalid or duplicate hair material.")
            }
        }
        let limits = Dictionary(uniqueKeysWithValues: input.brief.lengthLimits.map { ($0.region, $0) })
        let observed = Dictionary(uniqueKeysWithValues: input.hairProfile.regions.map { ($0.region, $0) })
        var ids = Set<String>(), lengths: [Double] = [], growth = Set<HairRegion>(), uncertain = Set<HairRegion>()
        var pointCount = 0
        for guide in haircut.guides {
            pointCount += guide.points.count
            guard pointCount <= 1_000_000, identifier(guide.id), ids.insert(guide.id).inserted,
                  materialIDs.contains(guide.materialID), (2...512).contains(guide.points.count),
                  guide.points.allSatisfy({ $0.finite && $0.length <= 3 }), let limit = limits[guide.region] else {
                throw CaptureError.invalid("Invalid guide, material reference, region or point budget.")
            }
            let attachment = try attachment(guide.root, scalp: input.scalp)
            guard (guide.points[0] - attachment.position).length <= 0.00001 else {
                throw CaptureError.invalid("Guide root is detached from its declared scalp binding.")
            }
            let length = try arcLength(guide.points)
            guard length >= limit.minimumMeters - 1e-8, length <= limit.maximumMeters + 1e-8 else {
                throw CaptureError.invalid("Guide violates its regional design length limits.")
            }
            lengths.append(length)
            if let observation = observed[guide.region], let available = observation.maximumAvailableMeters,
               [.observed, .userSupplied].contains(observation.origin), [.high, .medium].contains(observation.quality) {
                if length > available + 1e-8 { growth.insert(guide.region) }
            } else { uncertain.insert(guide.region) }
        }
        guard growth.isEmpty || input.brief.allowGrowth else { throw CaptureError.invalid("Target exceeds recorded current lengths and growth is not allowed.") }
        if let guardRequest=input.brief.envelopeGuard {
            _ = try EllipsoidGuideGuard.check(guides:haircut.guides,scalp:input.scalp,request:guardRequest)
        }
        var feasibility: [HairFeasibility] = [.uncertain]
        if !growth.isEmpty { feasibility.append(.requiresGrowth) }
        if !input.brief.stylingAssumptions.isEmpty { feasibility.append(.requiresStyling) }
        return HairValidationReport(haircutSHA256: try HairArtifactHash.digest(haircut), guideCount: lengths.count,
            minimumLengthMeters: lengths.min()!, maximumLengthMeters: lengths.max()!, feasibility: feasibility,
            growthRegions: growth.sorted { $0.rawValue < $1.rawValue },
            uncertainLengthRegions: uncertain.sorted { $0.rawValue < $1.rawValue },
            synthetic: haircut.generation.origin == .syntheticFixture || input.scalp.triangleOrigins.contains(.synthetic),
            checksCompleted: ["source_revision_hashes", "finite_geometry", "scalp_root_bindings", "regional_arc_lengths", "recorded_length_conflicts"] + (input.brief.envelopeGuard == nil ? [] : ["continuous_inferred_envelope_centerline"]),
            checksOutstanding: ["face_ear_scalp_clearance", "regional_continuity", "hairline_flow_texture_constraints", "physical_and_personalization_review"])
    }

    public static func attachment(_ binding: ScalpBinding, scalp: ScalpProfile) throws -> (position: Point3D, normal: Point3D) {
        guard scalp.triangles.indices.contains(binding.triangleIndex), binding.barycentric.count == 3,
              binding.barycentric.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              abs(binding.barycentric.reduce(0,+) - 1) <= 1e-8,
              binding.normalOffsetMeters.isFinite, (0...0.01).contains(binding.normalOffsetMeters) else {
            throw CaptureError.invalid("Invalid scalp triangle, barycentric coordinates or root offset.")
        }
        let t = scalp.triangles[binding.triangleIndex]
        guard t.count == 3, t.allSatisfy({ scalp.vertices.indices.contains($0) }) else { throw CaptureError.invalid("Scalp triangle indices are invalid.") }
        let a = scalp.vertices[t[0]], b = scalp.vertices[t[1]], c = scalp.vertices[t[2]]
        let cross = (b-a).cross(c-a)
        guard a.finite, b.finite, c.finite, cross.length.isFinite, cross.length > 1e-10 else { throw CaptureError.invalid("Degenerate scalp binding triangle.") }
        let normal = cross.unit
        return (a * binding.barycentric[0] + b * binding.barycentric[1] + c * binding.barycentric[2] + normal * binding.normalOffsetMeters, normal)
    }

    public static func arcLength(_ points: [Point3D]) throws -> Double {
        guard points.count >= 2, points.allSatisfy(\.finite) else { throw CaptureError.invalid("Invalid guide curve.") }
        var length = 0.0
        for i in 1..<points.count {
            let segment = (points[i]-points[i-1]).length
            guard segment.isFinite, segment > 1e-9 else { throw CaptureError.invalid("Guide contains a zero-length or invalid segment.") }
            length += segment
        }
        guard length.isFinite else { throw CaptureError.invalid("Guide length overflow.") }
        return length
    }

    public static func validateInput(_ input: HairDesignInput) throws {
        try input.brief.stylingPreferences?.validate()
        guard input.brief.stylingPreferences == nil || input.brief.mode == .guided else {
            throw CaptureError.invalid("Explicit styling preferences require guided mode.")
        }
        let s = input.scalp, h = input.hairProfile, b = input.brief
        guard s.schemaVersion == 1, h.schemaVersion == 1, b.schemaVersion == 1,
              [s.id,h.id,b.id].allSatisfy({ UUID(uuidString: $0) != nil }), s.revision > 0, h.revision > 0,
              !s.subjectSessionID.isEmpty, s.subjectSessionID == h.subjectSessionID,
              s.coordinateConvention == "eye_midpoint_x_anatomical_left_y_up_z_anterior_meters",
              (3...100_000).contains(s.vertices.count), (1...200_000).contains(s.triangles.count),
              s.vertices.allSatisfy({ $0.finite && $0.length <= 1 }), s.triangleOrigins.count == s.triangles.count,
              !s.method.isEmpty, !s.sourceSHA256.isEmpty, s.sourceSHA256.allSatisfy(HairArtifactHash.valid),
              b.scalpSHA256 == (try HairArtifactHash.digest(s)), b.hairProfileSHA256 == (try HairArtifactHash.digest(h)) else {
            throw CaptureError.invalid("Invalid scalp/profile/brief identity, geometry, provenance or hash binding.")
        }
        if let guardRequest=b.envelopeGuard { try EllipsoidGuideGuard.validateScalp(s,request:guardRequest) }
        var triangles = Set<String>()
        for t in s.triangles {
            guard t.count == 3, Set(t).count == 3, t.allSatisfy({ s.vertices.indices.contains($0) }),
                  triangles.insert(t.sorted().map(String.init).joined(separator: ",")).inserted,
                  (s.vertices[t[1]]-s.vertices[t[0]]).cross(s.vertices[t[2]]-s.vertices[t[0]]).length > 1e-10 else {
                throw CaptureError.invalid("Invalid, duplicate or degenerate scalp triangle.")
            }
        }
        var regions = Set<HairRegion>()
        guard !b.lengthLimits.isEmpty, b.lengthLimits.count <= HairRegion.allCases.count else { throw CaptureError.invalid("Missing regional limits.") }
        for limit in b.lengthLimits {
            guard regions.insert(limit.region).inserted, limit.minimumMeters.isFinite, limit.maximumMeters.isFinite,
                  limit.minimumMeters >= 0.001, limit.maximumMeters <= 1.5, limit.maximumMeters >= limit.minimumMeters,
                  limit.origin != .unknown else { throw CaptureError.invalid("Invalid regional length limits.") }
        }
        regions.removeAll()
        guard h.regions.count <= HairRegion.allCases.count else { throw CaptureError.invalid("Invalid hair profile regions.") }
        for observation in h.regions {
            guard regions.insert(observation.region).inserted, !observation.method.isEmpty else { throw CaptureError.invalid("Duplicate or unspecified length observation.") }
            if let length = observation.maximumAvailableMeters {
                guard length.isFinite, (0...1.5).contains(length), observation.origin != .unknown,
                      observation.quality != .unknown, !observation.evidenceReferences.isEmpty,
                      observation.evidenceReferences.allSatisfy({ !$0.isEmpty }) else { throw CaptureError.invalid("A length observation needs valid value, provenance and evidence references.") }
            } else {
                guard observation.origin == .unknown, observation.quality == .unknown else { throw CaptureError.invalid("Missing length must be explicitly unknown.") }
            }
        }
        if let characteristics = h.characteristics {
            try HairCharacteristicsValidator.validate(characteristics, scalp: s)
        }
    }
    private static func identifier(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 128 }
}

extension Point3D {
    static func * (p: Self, value: Double) -> Self { Self(x: p.x*value, y: p.y*value, z: p.z*value) }
}
