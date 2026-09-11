import Foundation

public struct ConditioningGuideRotation: Codable, Sendable {
    public var guideID: String
    public var axis: Point3D
    public var degrees: Double
}

/// Replayable post-conditioning corrections. Search optimality and physical fit
/// are not claimed; source identity, permitted edits and full clearance are checked.
public struct ConditioningDirectionFit: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var sourceHaircutSHA256: String
    public var originalSampleData: Data
    public var rotations: [ConditioningGuideRotation]

    public func verify(input: HairDesignInput, base: HaircutRevision, candidate: HaircutRevision,
                       mapping: ModelGuideImportRequest, anatomy: GuideClearanceInput,
                       expectedSampleSHA256: String) throws -> ConditioningFitVerification {
        let baseHash = try HairArtifactHash.digest(base)
        guard schemaVersion == 1, sourceHaircutSHA256 == baseHash,
              originalSampleData.count <= 25_000_000,
              EvidenceHash.sha256(originalSampleData) == expectedSampleSHA256,
              mapping.maximumRootFrameRotationRadians == nil,
              (1...128).contains(rotations.count),
              Set(rotations.map(\.guideID)).count == rotations.count,
              candidate.id != base.id, candidate.revision == 1,
              candidate.parentSHA256 == nil, candidate.edit == nil else {
            throw CaptureError.invalid("Direction fitting lost its source, identity or supported mapping.")
        }
        let source = try ManifestCoding.decoder().decode(ResearchStrandArtifact.self, from: originalSampleData)
        guard source.method == "pinned_haar_flattened_guides_adapter_v1", !source.acceptedForPersonalHaircut,
              source.pointsPerStrand == 100, source.strandCount == base.guides.count,
              source.strands.map(\.id) == base.guides.map(\.id),
              mapping.mappings.map(\.guideID) == base.guides.map(\.id) else {
            throw CaptureError.invalid("Direction fitting requires the exact unresampled original model guides.")
        }
        let evaluate = try GuideClearance.preparedEvaluator(input: input, anatomy: anatomy)
        let baseline = try evaluate(base)
        guard baseline.rootViolations?.isEmpty == true else {
            throw CaptureError.invalid("Direction fitting cannot repair a conflicting attachment.")
        }
        let conflicts = Set(baseline.violations.map(\.guideID))
        var expected = base
        expected.id = candidate.id; expected.revision = 1; expected.parentSHA256 = nil; expected.edit = nil
        expected.generation.method = "bounded_fixed_root_rotation_v1:" + baseHash + "; source: " + base.generation.method
        for rotation in rotations {
            guard conflicts.contains(rotation.guideID), rotation.axis.finite,
                  rotation.axis.length > 1e-12, rotation.axis.length <= 2,
                  rotation.degrees.isFinite, abs(rotation.degrees) > 0, abs(rotation.degrees) <= 20,
                  let index = expected.guides.firstIndex(where: { $0.id == rotation.guideID }) else {
                throw CaptureError.invalid("Invalid direction correction or change to an unaffected guide.")
            }
            expected.guides[index].points = GuideRotationProposal.rotated(base.guides[index].points,
                axis: rotation.axis, degrees: rotation.degrees)
            guard zip(expected.guides[index].points, base.guides[index].points).allSatisfy({ ($0-$1).length <= 0.02 }) else {
                throw CaptureError.invalid("Direction correction exceeds its 20 mm movement limit.")
            }
        }
        guard try HairArtifactHash.digest(expected) == HairArtifactHash.digest(candidate) else {
            throw CaptureError.invalid("Fitted revision differs from replaying its declared rotations.")
        }
        let scale = mapping.metersPerSourceUnit
        guard scale.finite, scale.x > 0, scale.y > 0, scale.z > 0 else { throw CaptureError.invalid("Invalid model mapping scale.") }
        var cumulative = 0.0
        for i in candidate.guides.indices {
            let guide = candidate.guides[i], binding = mapping.mappings[i].binding
            guard try HairArtifactHash.digest(binding) == HairArtifactHash.digest(guide.root),
                  source.strands[i].points.count == 100, guide.points.count == 100 else {
                throw CaptureError.invalid("Fitting changed attachment or point correspondence.")
            }
            let raw = try source.strands[i].points.map { values -> Point3D in
                guard values.count == 3, values.allSatisfy(\.isFinite) else { throw CaptureError.invalid("Invalid original model point.") }
                return Point3D(x:values[0],y:values[1],z:values[2])
            }
            let root = try HaircutValidator.attachment(binding, scalp:input.scalp).position
            let delta = raw[0]-mapping.sourceCenter
            let mappedRoot = mapping.targetCenterMeters + Point3D(x:delta.x*scale.x,y:delta.y*scale.y,z:delta.z*scale.z)
            guard mapping.maximumRootCorrectionMeters.isFinite,
                  (root-mappedRoot).length <= mapping.maximumRootCorrectionMeters else {
                throw CaptureError.invalid("Fitting exceeds the source-root correspondence bound.")
            }
            for (point, original) in zip(guide.points,raw) {
                let d = original-raw[0]
                let reference = root + Point3D(x:d.x*scale.x,y:d.y*scale.y,z:d.z*scale.z)
                cumulative = max(cumulative,(point-reference).length)
            }
        }
        guard cumulative <= 0.02 else { throw CaptureError.invalid("Fitting exceeds 20 mm cumulative movement from the model sample.") }
        let validation = try HaircutValidator.validate(input:input,haircut:candidate)
        let clearance = try evaluate(candidate)
        guard clearance.surfaceChecksPassed else { throw CaptureError.invalid("Fitted candidate still conflicts with supplied anatomy.") }
        return ConditioningFitVerification(validation:validation,clearance:clearance,maximumCumulativeMovementMeters:cumulative)
    }
}

public struct ConditioningFitVerification: Codable, Sendable {
    public var validation: HairValidationReport
    public var clearance: GuideClearanceReport
    public var maximumCumulativeMovementMeters: Double
}
