import Foundation

public struct HairEditResult: Codable, Sendable {
    public var haircut: HaircutRevision
    public var validation: HairValidationReport
    public var changedGuideIDs: [String]
    public var clearance: GuideClearanceReport?
}

public enum HaircutEditor {
    /// Replays a claimed transition against its exact parent. A valid standalone
    /// mesh alone cannot prove that an edit preserved unrelated regions.
    public static func verifyTransition(from base: HaircutRevision, to result: HaircutRevision, input: HairDesignInput) throws {
        guard let edit = result.edit else { throw CaptureError.invalid("Edited revision has no operation.") }
        let expected = try apply(edit, to: base, input: input)
        guard try HairArtifactHash.digest(expected.haircut) == HairArtifactHash.digest(result) else {
            throw CaptureError.invalid("Saved revision differs from replaying its declared edit.")
        }
    }
    /// Pure revision operation: the caller retains the base asset. No saved
    /// selection is changed here, so a delayed result cannot replace it implicitly.
    public static func apply(_ edit: HairEdit, to base: HaircutRevision, input: HairDesignInput,
                             anatomy: GuideClearanceInput? = nil) throws -> HairEditResult {
        _ = try HaircutValidator.validate(input: input, haircut: base)
        guard edit.baseSHA256 == (try HairArtifactHash.digest(base)), edit.value.isFinite,
              base.revision < 1_000_000 else { throw CaptureError.invalid("Edit refers to a stale base or has an invalid value.") }
        switch edit.operation {
        case .shortenToLength:
            guard (0.001...1.5).contains(edit.value) else { throw CaptureError.invalid("Invalid target curve length.") }
        case .rotateAroundRootNormal:
            guard (-45...45).contains(edit.value) else { throw CaptureError.invalid("Direction adjustment must be between -45 and 45 degrees.") }
        case .scaleLateralVolume:
            guard (0.5...1.5).contains(edit.value) else { throw CaptureError.invalid("Volume factor must be between 0.5 and 1.5.") }
        }
        var result = base, changed: [String] = []
        for index in result.guides.indices where result.guides[index].region == edit.region {
            let guide = base.guides[index]
            let points: [Point3D]
            switch edit.operation {
            case .shortenToLength:
                let length = try HaircutValidator.arcLength(guide.points)
                guard edit.value <= length + 1e-9 else { throw CaptureError.invalid("Shortening cannot extend a guide. Generate a new design for added length.") }
                points = trim(guide.points, at: min(edit.value, length))
            case .rotateAroundRootNormal:
                let normal = try HaircutValidator.attachment(guide.root, scalp: input.scalp).normal
                let root = guide.points[0], angle = edit.value * .pi / 180
                let cosine = cos(angle), sine = sin(angle)
                points = [root] + guide.points.dropFirst().map { point in
                    let delta = point-root
                    return root + delta*cosine + normal.cross(delta)*sine + normal*(normal.dot(delta)*(1-cosine))
                }
            case .scaleLateralVolume:
                let attachment = try HaircutValidator.attachment(guide.root, scalp: input.scalp)
                let root = guide.points[0], normal = attachment.normal
                points = guide.points.map { point in
                    let delta = point-root, axial = normal * delta.dot(normal)
                    return root + axial + (delta-axial) * edit.value
                }
            }
            if zip(points,guide.points).contains(where: { ($0-$1).length > 1e-9 }) || points.count != guide.points.count {
                result.guides[index].points = points
                changed.append(guide.id)
            }
        }
        guard !changed.isEmpty else { throw CaptureError.invalid("Edit changes no guides in the selected region.") }
        result.revision += 1; result.parentSHA256 = edit.baseSHA256; result.edit = edit
        let report = try HaircutValidator.validate(input: input, haircut: result)
        let clearance = try anatomy.map { try GuideClearance.check(input: input, haircut: result, anatomy: $0) }
        if let clearance, !clearance.surfaceChecksPassed {
            throw CaptureError.invalid("Edit intersects or violates clearance from supplied anatomy (\(clearance.violations.count) affected guide segments). Previous revision is preserved.")
        }
        return HairEditResult(haircut: result, validation: report, changedGuideIDs: changed, clearance: clearance)
    }

    private static func trim(_ points: [Point3D], at target: Double) -> [Point3D] {
        var result = [points[0]], traversed = 0.0
        for i in 1..<points.count {
            let distance = (points[i]-points[i-1]).length
            if traversed + distance >= target {
                let remaining = target-traversed
                if remaining > 1e-9 { result.append(points[i-1] + (points[i]-points[i-1]) * (remaining/distance)) }
                break
            }
            result.append(points[i]); traversed += distance
        }
        return result
    }
}
