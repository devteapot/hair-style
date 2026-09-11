import Foundation

public struct HairEditResult: Codable, Sendable {
    public var haircut: HaircutRevision
    public var validation: HairValidationReport
    /// Guides whose geometry or material assignment changed.
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
        if edit.operation == .matchRecordedColor { return try recolor(edit, base: base, input: input, anatomy: anatomy) }
        guard edit.recordedColor == nil else { throw CaptureError.invalid("Geometry edit cannot carry color evidence.") }
        switch edit.operation {
        case .matchRecordedColor: throw CaptureError.invalid("Unexpected color operation.")
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
            case .matchRecordedColor: throw CaptureError.invalid("Unexpected color operation.")
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

    private static func recolor(_ edit: HairEdit, base: HaircutRevision, input: HairDesignInput,
                                anatomy: GuideClearanceInput?) throws -> HairEditResult {
        guard edit.value == 0, let evidence = edit.recordedColor else { throw CaptureError.invalid("Color edit needs recorded image evidence.") }
        try evidence.validate(subjectSessionID: input.scalp.subjectSessionID)
        let color = evidence.linearRGB
        var result = base, changed: [String] = [], replacements: [String: String] = [:]
        var usedIDs = Set(base.materials.map(\.id))
        let originals = Dictionary(uniqueKeysWithValues: base.materials.map { ($0.id, $0) })
        for i in result.guides.indices where result.guides[i].region == edit.region {
            let sourceID = result.guides[i].materialID
            guard var material = originals[sourceID] else { throw CaptureError.invalid("Missing hair material.") }
            if zip(material.linearRGB, color).allSatisfy({ abs($0-$1) < 1e-12 }) { continue }
            if let replacement = replacements[sourceID] { result.guides[i].materialID = replacement }
            else {
                let token = EvidenceHash.sha256(Data((sourceID+evidence.reportSHA256+edit.region.rawValue).utf8)).prefix(24)
                var id = "photo-\(token)", suffix = 0
                while usedIDs.contains(id) { suffix += 1; id = "photo-\(token)-\(suffix)" }
                usedIDs.insert(id); material.id = id; material.linearRGB = color
                result.materials.append(material); replacements[sourceID] = id; result.guides[i].materialID = id
            }
            changed.append(result.guides[i].id)
        }
        guard !changed.isEmpty else { throw CaptureError.invalid("Recorded color changes no materials in this region.") }
        let referenced = Set(result.guides.map(\.materialID))
        result.materials.removeAll { !referenced.contains($0.id) }
        result.revision += 1; result.parentSHA256 = edit.baseSHA256; result.edit = edit
        let validation = try HaircutValidator.validate(input: input, haircut: result)
        // Color cannot resolve or introduce a geometric collision; retain the report without claiming clearance.
        let clearance = try anatomy.map { try GuideClearance.check(input: input, haircut: result, anatomy: $0) }
        return HairEditResult(haircut: result, validation: validation, changedGuideIDs: changed, clearance: clearance)
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
