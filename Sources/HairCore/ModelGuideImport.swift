import Foundation

public struct ModelGuideMapping: Codable, Sendable {
    public var guideID: String
    public var region: HairRegion
    public var binding: ScalpBinding
}

public struct ModelGuideImportRequest: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var id: String
    public var sourceArtifactSHA256: String
    public var scalpSHA256: String
    /// Explicit axis-aligned research correspondence. Source units need not be meters.
    public var sourceCenter: Point3D
    public var targetCenterMeters: Point3D
    public var metersPerSourceUnit: Point3D
    public var maximumRootCorrectionMeters: Double
    public var mappings: [ModelGuideMapping]
    public var method: String
    public var envelopeGuard: EllipsoidGuideGuardRequest? = nil
    /// Opt-in minimal rotation between inferred envelope normals at old/new roots.
    public var maximumRootFrameRotationRadians: Double? = nil
}

public struct ImportedGuideDecision: Codable, Sendable {
    public var guideID: String
    public var region: HairRegion
    public var rootCorrectionMeters: Double
    public var transformedLengthMeters: Double
    public var constrainedLengthMeters: Double
    public var trimmedByRegionalLimit: Bool
    public var rootFrameRotationRadians: Double? = nil
}

public struct ModelGuideImportResult: Codable, Sendable {
    public var request: ModelGuideImportRequest
    public var requestSHA256: String
    public var haircut: HaircutRevision
    public var validation: HairValidationReport
    public var decisions: [ImportedGuideDecision]
    public var envelopeGuard: EllipsoidGuideGuardReport? = nil
    public var acceptedForPersonalHaircut: Bool = false
    public var personalizationBeyondFittingVerified: Bool = false
    public var limitations: [String]
}

public struct ConditionedGuideEvidence: Codable, Sendable {
    public var inputSHA256: String
    public var mappingGeometrySHA256: String
    public var baseSourceSHA256: String
    public var optimizationReportSHA256: String
    public var regionalReportSHA256: String
    public var decoderSHA256: String
}

struct ResearchStrandArtifact: Decodable {
    struct Guide: Decodable { var id: String; var points: [[Double]] }
    var schemaVersion: Int
    var method: String
    var modelRevision: String
    var implementation: String
    var runReportSHA256: String
    var sourcePLYSHA256: String
    var coordinateConvention: String
    var units: String
    var pointsPerStrand: Int
    var pointOrder: String
    var strandCount: Int
    var strands: [Guide]
    var acceptedForPersonalHaircut: Bool
    var samplingSeed: UInt64?
    var conditioning: ConditionedGuideEvidence?
}

/// Converts verified research curves into editable canonical geometry. Fitting
/// and length constraints do not establish a personalized styling decision.
public enum ModelGuideImport {
    /// Excludes artifact identity to avoid a circular hash; all mapping geometry and bounds remain bound.
    public static func conditioningGeometryHash(_ request: ModelGuideImportRequest) throws -> String {
        var geometry = request
        geometry.id = "00000000-0000-0000-0000-000000000000"
        geometry.sourceArtifactSHA256 = String(repeating: "0", count: 64)
        geometry.method = "conditioning_geometry_v1"
        return try HairArtifactHash.digest(geometry)
    }
    public static func apply(sourceData: Data, input: HairDesignInput,
                             request: ModelGuideImportRequest) throws -> ModelGuideImportResult {
        try HaircutValidator.validateInput(input)
        if let maximum = request.maximumRootFrameRotationRadians {
            guard maximum.isFinite, (0...Double.pi/2).contains(maximum), let envelope = request.envelopeGuard else {
                throw CaptureError.invalid("Root-frame rotation requires a bounded angle and an explicit inferred envelope.")
            }
            try EllipsoidGuideGuard.validateScalp(input.scalp, request: envelope)
        }
        guard try HairArtifactHash.digest(input.brief.envelopeGuard) == HairArtifactHash.digest(request.envelopeGuard) else {
            throw CaptureError.invalid("Import guard must match the constraint retained in the design brief.")
        }
        guard sourceData.count <= 64_000_000,
              EvidenceHash.sha256(sourceData) == request.sourceArtifactSHA256,
              request.schemaVersion == 1, UUID(uuidString: request.id) != nil,
              request.scalpSHA256 == input.brief.scalpSHA256,
              request.sourceCenter.finite, request.sourceCenter.length < 10,
              request.targetCenterMeters.finite, request.targetCenterMeters.length <= 1,
              request.metersPerSourceUnit.finite,
              [request.metersPerSourceUnit.x, request.metersPerSourceUnit.y, request.metersPerSourceUnit.z].allSatisfy({ (0.0001...100).contains($0) }),
              request.maximumRootCorrectionMeters.isFinite,
              (0...0.03).contains(request.maximumRootCorrectionMeters), !request.method.isEmpty else {
            throw CaptureError.invalid("Model import source, scalp binding or coordinate mapping is invalid.")
        }
        let source = try ManifestCoding.decoder().decode(ResearchStrandArtifact.self, from: sourceData)
        let conditioned = source.method == "personal_envelope_decoder_latents_v1"
        if conditioned {
            guard source.implementation == "metal_decoder_personal_constraints_v1", let evidence = source.conditioning,
                  source.samplingSeed != nil,
                  evidence.inputSHA256 == (try HairArtifactHash.digest(input)),
                  evidence.mappingGeometrySHA256 == (try conditioningGeometryHash(request)),
                  [evidence.baseSourceSHA256, evidence.optimizationReportSHA256, evidence.regionalReportSHA256,
                   evidence.decoderSHA256].allSatisfy(HairArtifactHash.valid) else {
                throw CaptureError.invalid("Conditioned model output does not match its personal input, mapping or evidence.")
            }
        } else {
            guard source.method == "pinned_haar_flattened_guides_adapter_v1", source.conditioning == nil,
                  ["upstream_cli", "metal_inference_port_v1"].contains(source.implementation) else {
                throw CaptureError.invalid("Unsupported model implementation or conditioning claim.")
            }
        }
        guard source.schemaVersion == 1,
              source.modelRevision == "766a29a9112d84e0b5d512f9b6d7de4f27d3e857",
              HairArtifactHash.valid(source.runReportSHA256), HairArtifactHash.valid(source.sourcePLYSHA256),
              source.coordinateConvention == "haar_template_coordinates_unresolved", source.units == "unresolved",
              source.pointsPerStrand == 100, source.pointOrder == "root_to_tip_as_emitted_by_texture2strands",
              !source.acceptedForPersonalHaircut, source.strandCount == source.strands.count,
              (1...10_000).contains(source.strandCount), request.mappings.count == source.strandCount else {
            throw CaptureError.invalid("Unsupported or incomplete ordered research guide artifact.")
        }
        let limits = Dictionary(uniqueKeysWithValues: input.brief.lengthLimits.map { ($0.region, $0) })
        var guides: [HairGuide] = [], decisions: [ImportedGuideDecision] = []
        var seen = Set<String>()
        func transform(_ p: Point3D) -> Point3D {
            let d = p - request.sourceCenter, s = request.metersPerSourceUnit
            return request.targetCenterMeters + Point3D(x: d.x*s.x, y: d.y*s.y, z: d.z*s.z)
        }
        for (curve, mapping) in zip(source.strands, request.mappings) {
            guard curve.id == mapping.guideID, seen.insert(curve.id).inserted,
                  curve.points.count == 100, let limit = limits[mapping.region] else {
                throw CaptureError.invalid("Guide mapping must preserve every unique source ID and its order.")
            }
            let points = try curve.points.map { values -> Point3D in
                guard values.count == 3, values.allSatisfy(\.isFinite) else { throw CaptureError.invalid("Invalid source guide point.") }
                let p = Point3D(x: values[0], y: values[1], z: values[2])
                guard p.length < 10 else { throw CaptureError.invalid("Unbounded source point.") }
                return transform(p)
            }
            let attachment = try HaircutValidator.attachment(mapping.binding, scalp: input.scalp)
            let correction = attachment.position - points[0]
            guard correction.length <= request.maximumRootCorrectionMeters + 1e-9 else {
                throw CaptureError.invalid("Guide \(curve.id) exceeds permitted root correction; revise correspondence.")
            }
            var attached = points.map { $0 + correction }
            var rotationAngle: Double?
            if let maximum = request.maximumRootFrameRotationRadians, let guardRequest = request.envelopeGuard {
                let rotated = try RootFrameRotation.attach(points: points, to: attachment.position,
                    envelope: guardRequest.envelope, maximumAngle: maximum)
                attached = rotated.points; rotationAngle = rotated.angle
            }
            let length = try HaircutValidator.arcLength(attached)
            guard length >= limit.minimumMeters - 1e-8 else {
                throw CaptureError.invalid("Guide \(curve.id) is shorter than its regional minimum; regeneration is required.")
            }
            let constrained = length > limit.maximumMeters ? trim(attached, at: limit.maximumMeters) : attached
            let constrainedLength = try HaircutValidator.arcLength(constrained)
            guides.append(HairGuide(id: curve.id, region: mapping.region, materialID: "research_neutral",
                root: mapping.binding, points: constrained))
            decisions.append(ImportedGuideDecision(guideID: curve.id, region: mapping.region,
                rootCorrectionMeters: correction.length, transformedLengthMeters: length,
                constrainedLengthMeters: constrainedLength, trimmedByRegionalLimit: length > limit.maximumMeters,
                rootFrameRotationRadians: rotationAngle))
        }
        var envelopeReport: EllipsoidGuideGuardReport?
        if let guardRequest=request.envelopeGuard {
            let corrected=try EllipsoidGuideGuard.apply(guides:guides,scalp:input.scalp,request:guardRequest)
            guides=corrected.guides;envelopeReport=corrected.report
            // Corrections can change arc length. Do not silently override the
            // brief to accommodate them; the final validator must still pass.
            for index in guides.indices { decisions[index].constrainedLengthMeters=try HaircutValidator.arcLength(guides[index].points) }
        }
        let hash = try HairArtifactHash.digest(request)
        let haircut = HaircutRevision(id: request.id, revision: 1, scalpSHA256: input.brief.scalpSHA256,
            hairProfileSHA256: input.brief.hairProfileSHA256, briefSHA256: try HairArtifactHash.digest(input.brief),
            generation: HairGenerationRecord(origin: .model, method: (conditioned ? "personal_decoder_latents:" : "haar_research_retargeting:") + hash,
                version: "1", seed: input.brief.seed, modelSamplingSeed: source.samplingSeed),
            materials: [HairMaterial(id: "research_neutral", linearRGB: [0.08,0.05,0.035], roughness: 0.6, radiusMeters: 0.00005)],
            guides: guides)
        return ModelGuideImportResult(request: request, requestSHA256: hash, haircut: haircut,
            validation: try HaircutValidator.validate(input: input, haircut: haircut), decisions: decisions, envelopeGuard:envelopeReport,
            limitations: ["template_correspondence_requires_review", "scalp_and_hairline_are_not_validated",
                "global_fitting_is_not_personalized_styling", "regional_labels_are_mapping_assertions",
                "current_length_flow_and_texture_may_be_unknown", "diagnostic_material_not_observed_color",
                "face_ear_scalp_and_self_clearance_unverified", "physical_feasibility_unverified"])
    }

    private static func trim(_ points: [Point3D], at target: Double) -> [Point3D] {
        var result = [points[0]], total = 0.0
        for index in 1..<points.count {
            let distance = (points[index] - points[index-1]).length
            if total + distance >= target {
                let remaining = target - total
                if remaining > 1e-9 { result.append(points[index-1] + (points[index]-points[index-1]) * (remaining/distance)) }
                break
            }
            result.append(points[index]); total += distance
        }
        return result
    }
}

/// Rigid root-relative transport; inferred surface normals are not measured growth directions.
enum RootFrameRotation {
    static func attach(points: [Point3D], to target: Point3D, envelope: ScalpEnvelope,
                       maximumAngle: Double) throws -> (points: [Point3D], angle: Double) {
        guard let root = points.first, points.count >= 2, points.allSatisfy(\.finite), target.finite,
              envelope.center.finite, envelope.radii.finite,
              [envelope.radii.x, envelope.radii.y, envelope.radii.z].allSatisfy({ $0 > 0 }),
              maximumAngle.isFinite, (0...Double.pi/2).contains(maximumAngle) else {
            throw CaptureError.invalid("Invalid root-frame transport.")
        }
        func normal(_ p: Point3D) throws -> Point3D {
            let q = p-envelope.center, r = envelope.radii
            let n = Point3D(x: q.x/(r.x*r.x), y: q.y/(r.y*r.y), z: q.z/(r.z*r.z))
            guard n.finite, n.length > 1e-12 else { throw CaptureError.invalid("Undefined envelope normal at root.") }
            return n.unit
        }
        let a = try normal(root), b = try normal(target), v = a.cross(b)
        let cosine = min(1, max(-1, a.dot(b))), angle = acos(cosine)
        guard angle <= maximumAngle+1e-12, cosine > -1+1e-12 else {
            throw CaptureError.invalid("Root-frame rotation exceeds the declared mapping limit.")
        }
        let rotated = points.map { point -> Point3D in
            let p = point-root
            return target+p+v.cross(p)+v.cross(v.cross(p))/(1+cosine)
        }
        return (rotated, angle)
    }
}
