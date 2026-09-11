import Foundation

public struct BaselineRoot: Codable, Sendable {
    public var region: HairRegion
    public var binding: ScalpBinding
}
public struct BaselineGenerationRequest: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var id: String
    public var roots: [BaselineRoot]
    /// Explicit experiment target; compiler limits still take precedence.
    public var preferredLengthMeters: Double
}
public struct BaselineGuideDecision: Codable, Sendable {
    public var guideID: String
    public var targetLengthMeters: Double
    public var texture: HairTexture?
    public var textureEvidenceUsed: Bool
    public var flowObservationIndex: Int?
    public var fallbackDirectionUsed: Bool
}
public struct BaselineGenerationResult: Codable, Sendable {
    public var request: BaselineGenerationRequest
    public var requestSHA256: String
    public var haircut: HaircutRevision
    public var validation: HairValidationReport
    public var decisions: [BaselineGuideDecision]
    public var clearance: GuideClearanceReport?
    public var limitations: [String]
}

/// Controlled baseline for the plan's model comparison. Does not choose a style,
/// infer roots, reconstruct hair or claim a physical prediction.
public enum ProceduralHairBaseline {
    public static func generate(input: HairDesignInput, request: BaselineGenerationRequest,
                                anatomy: GuideClearanceInput? = nil) throws -> BaselineGenerationResult {
        try HaircutValidator.validateInput(input)
        guard request.schemaVersion == 1, UUID(uuidString: request.id) != nil,
              (1...2048).contains(request.roots.count), request.preferredLengthMeters.isFinite,
              (0.001...1.5).contains(request.preferredLengthMeters) else {
            throw CaptureError.invalid("Invalid baseline request identity, roots or preferred length.")
        }
        let limits = Dictionary(uniqueKeysWithValues: input.brief.lengthLimits.map { ($0.region,$0) })
        let traits = input.hairProfile.characteristics
        let textures = Dictionary(uniqueKeysWithValues: (traits?.textures ?? []).map { ($0.region,$0) })
        let flows = try (traits?.flow ?? []).enumerated().map { index, flow in
            (index, flow, try HaircutValidator.attachment(flow.scalpLocation, scalp: input.scalp).position)
        }
        var guides: [HairGuide] = [], decisions: [BaselineGuideDecision] = []
        var seen = Set<String>()
        for (index, root) in request.roots.enumerated() {
            guard let limit = limits[root.region],
                  seen.insert(try HairArtifactHash.digest(root.binding)).inserted else {
                throw CaptureError.invalid("A baseline root has no regional limits or duplicates another root.")
            }
            let attachment = try HaircutValidator.attachment(root.binding, scalp: input.scalp)
            let p = attachment.position, n = attachment.normal
            let target = min(limit.maximumMeters, max(limit.minimumMeters, request.preferredLengthMeters))
            var nearest: (Int, Point3D, Double)?
            for (flowIndex, flow, location) in flows where flow.region == root.region {
                guard [.high,.medium].contains(flow.evidence.quality), let direction = flow.direction else { continue }
                let tangent = direction - n * direction.dot(n)
                let distance = (location - p).length
                // Avoid applying a distant local observation across an entire region.
                guard tangent.length > 0.1, distance <= 0.05 else { continue }
                if nearest == nil || distance < nearest!.2 { nearest = (flowIndex, tangent.unit, distance) }
            }
            let axis = abs(n.z) < 0.9 ? Point3D(x: 0,y: 0,z: -1) : Point3D(x: 1,y: 0,z: 0)
            let tangent = nearest?.1 ?? (axis - n * axis.dot(n)).unit
            let lateral = n.cross(tangent).unit
            let observation = textures[root.region]
            let texture = observation.flatMap { [.high,.medium].contains($0.evidence.quality) ? $0.value : nil }
            let cycles: Double, amplitude: Double
            switch texture {
            case .wavy: cycles = 2; amplitude = 0.08
            case .curly: cycles = 4; amplitude = 0.12
            case .coily: cycles = 8; amplitude = 0.1
            default: cycles = 0; amplitude = 0
            }
            // Stable per-guide phase; no process-global randomness or nondeterministic hash.
            let phase = Double((input.brief.seed &+ UInt64(index) &* 2654435761) % 10000) / 10000 * 2 * Double.pi
            let local: [Point3D] = (0..<97).map { sample in
                let t = Double(sample) / 96
                let envelope = sin(t * Double.pi / 2)
                let wave = amplitude * envelope * sin(2 * Double.pi * cycles * t + phase)
                return tangent * t + n * (0.5 * t - 0.25 * t * t) + lateral * wave
            }
            let scale = target / (try HaircutValidator.arcLength(local))
            let id = "baseline_\(index)"
            guides.append(HairGuide(id: id, region: root.region, materialID: "diagnostic_neutral",
                root: root.binding, points: local.map { p + $0 * scale }))
            decisions.append(BaselineGuideDecision(guideID: id, targetLengthMeters: target, texture: texture,
                textureEvidenceUsed: texture != nil, flowObservationIndex: nearest?.0, fallbackDirectionUsed: nearest == nil))
        }
        let requestHash = try HairArtifactHash.digest(request)
        let haircut = HaircutRevision(id: request.id, revision: 1,
            scalpSHA256: input.brief.scalpSHA256, hairProfileSHA256: input.brief.hairProfileSHA256,
            briefSHA256: try HairArtifactHash.digest(input.brief),
            generation: HairGenerationRecord(origin: .proceduralBaseline,
                method: "scalp_flow_texture_baseline:" + requestHash, version: "1", seed: input.brief.seed),
            materials: [HairMaterial(id: "diagnostic_neutral", linearRGB: [0.15,0.15,0.15], roughness: 0.6, radiusMeters: 0.00005)],
            guides: guides)
        let validation = try HaircutValidator.validate(input: input, haircut: haircut)
        let clearance = try anatomy.map { try GuideClearance.check(input: input, haircut: haircut, anatomy: $0) }
        if let clearance, !clearance.surfaceChecksPassed {
            throw CaptureError.invalid("Generated baseline intersects supplied anatomical surfaces.")
        }
        return BaselineGenerationResult(request: request, requestSHA256: requestHash, haircut: haircut,
            validation: validation, decisions: decisions, clearance: clearance,
            limitations: ["procedural_comparison_baseline_not_AI_stylist", "explicit_roots_not_inferred_follicles",
                "diagnostic_color_not_observed_color", "texture_wave_approximation_not_physics",
                "hairline_and_regional_continuity_not_enforced", "scalp_interior_and_self_collision_unverified"])
    }
}
