import Foundation

public enum HairTexture: String, Codable, Sendable { case straight, wavy, curly, coily, mixed }
public enum HairFlowMeaning: String, Codable, Sendable {
    case visibleArrangement = "visible_arrangement", estimatedRootGrowth = "estimated_root_growth"
}

public struct HairObservationEvidence: Codable, Sendable {
    public var origin: ObservationOrigin
    public var quality: EvidenceQuality
    public var sourceSHA256: [String]
    public var method: String
    public var methodVersion: String
    /// State affecting the appearance, e.g. dry, styled or product use; unknown is explicit.
    public var captureCondition: String
}

public struct RegionalTextureObservation: Codable, Sendable {
    public var region: HairRegion
    public var value: HairTexture?
    public var evidence: HairObservationEvidence
}

public struct HairFlowObservation: Codable, Sendable {
    public var region: HairRegion
    public var meaning: HairFlowMeaning
    public var scalpLocation: ScalpBinding
    /// Unit tangent in the anatomical head frame. Nil means unknown.
    public var direction: Point3D?
    public var evidence: HairObservationEvidence
}

public struct HairlineObservation: Codable, Sendable {
    public var region: HairRegion
    /// Ordered anchors on the exact scalp revision. No curve means unknown.
    public var anchors: [ScalpBinding]?
    public var evidence: HairObservationEvidence
}

public struct HairCharacteristics: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var scalpSHA256: String
    public var textures: [RegionalTextureObservation]
    public var flow: [HairFlowObservation]
    public var hairline: [HairlineObservation]
}

public enum HairCharacteristicsValidator {
    public static func validate(_ value: HairCharacteristics, scalp: ScalpProfile) throws {
        guard value.schemaVersion == 1, value.scalpSHA256 == (try HairArtifactHash.digest(scalp)),
              value.textures.count <= 6, value.flow.count <= 4096, value.hairline.count <= 6 else {
            throw CaptureError.invalid("Invalid hair characteristics version, scalp binding or observation budget.")
        }
        var regions = Set<HairRegion>()
        for texture in value.textures {
            guard regions.insert(texture.region).inserted else { throw CaptureError.invalid("Duplicate regional texture.") }
            try evidence(texture.evidence, known: texture.value != nil)
        }
        for flow in value.flow {
            try evidence(flow.evidence, known: flow.direction != nil)
            let attachment = try HaircutValidator.attachment(flow.scalpLocation, scalp: scalp)
            if let direction = flow.direction {
                guard direction.finite, abs(direction.length - 1) < 1e-5,
                      abs(direction.dot(attachment.normal)) < 0.05 else {
                    throw CaptureError.invalid("Hair flow must be a unit tangent in the anatomical frame.")
                }
                if flow.meaning == .estimatedRootGrowth {
                    guard [.inferred, .userSupplied].contains(flow.evidence.origin) else {
                        throw CaptureError.invalid("Root growth cannot be labeled as directly observed from surface imagery.")
                    }
                }
            }
        }
        regions.removeAll()
        for line in value.hairline {
            guard regions.insert(line.region).inserted else { throw CaptureError.invalid("Duplicate regional hairline.") }
            try evidence(line.evidence, known: line.anchors != nil)
            if let anchors = line.anchors {
                guard (2...512).contains(anchors.count) else { throw CaptureError.invalid("Hairline needs 2–512 anchors.") }
                var previous: Point3D?
                for anchor in anchors {
                    guard anchor.normalOffsetMeters == 0 else { throw CaptureError.invalid("Hairline anchors must lie on the scalp surface.") }
                    let point = try HaircutValidator.attachment(anchor, scalp: scalp).position
                    if let previous {
                        let distance = (point - previous).length
                        guard distance > 1e-6, distance <= 0.05 else {
                            throw CaptureError.invalid("Hairline has duplicate anchors or a gap exceeding 5 cm.")
                        }
                    }
                    previous = point
                }
            }
        }
    }

    private static func evidence(_ evidence: HairObservationEvidence, known: Bool) throws {
        guard !evidence.method.isEmpty, evidence.method.utf8.count <= 512,
              !evidence.methodVersion.isEmpty, evidence.methodVersion.utf8.count <= 128,
              !evidence.captureCondition.isEmpty, evidence.captureCondition.utf8.count <= 512,
              evidence.sourceSHA256.count <= 64,
              evidence.sourceSHA256.allSatisfy(HairArtifactHash.valid) else {
            throw CaptureError.invalid("Invalid hair observation evidence metadata.")
        }
        if known {
            guard [.observed, .inferred, .userSupplied].contains(evidence.origin),
                  evidence.quality != .unknown, !evidence.sourceSHA256.isEmpty else {
                throw CaptureError.invalid("A personal characteristic needs provenance and source evidence; defaults are not observations.")
            }
        } else {
            guard evidence.origin == .unknown, evidence.quality == .unknown else {
                throw CaptureError.invalid("An absent characteristic must remain explicitly unknown.")
            }
        }
    }
}
