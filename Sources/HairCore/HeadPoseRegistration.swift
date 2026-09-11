import Foundation

public struct HeadPoseRegistrationRequest: Codable, Sendable {
    public var sourceFrameID: String
    public var targetFrameID: String
    public var validationPairs: [PixelLandmarkPair]
    public init(sourceFrameID: String, targetFrameID: String, validationPairs: [PixelLandmarkPair]) {
        self.sourceFrameID = sourceFrameID; self.targetFrameID = targetFrameID
        self.validationPairs = validationPairs
    }
}

public struct HeadPoseRegistrationReport: Codable, Sendable {
    public var schemaVersion = 1
    public var method = "tracked_head_pose_initializer_v1"
    public var captureID: String
    public var sourceFrameID: String
    public var targetFrameID: String
    public var sourceFrameSHA256: String
    public var targetFrameSHA256: String
    public var requestSHA256: String
    public var evidenceSource: CaptureSource
    public var anchorID: String
    public var targetFromSource: RigidTransform
    public var validationResiduals: [LandmarkResidual]
    public var validationMedianMeters: Double
    public var validationP95Meters: Double
    public var acceptedForFusion = false
    public var notes: [String]
}

public enum HeadPoseRegistration {
    /// Same capture only: anchor UUIDs do not establish a shared frame across sessions.
    /// Independent landmark residuals diagnose the tracker without fitting to them.
    public static func inspect(bundle: URL, request: HeadPoseRegistrationRequest) throws -> HeadPoseRegistrationReport {
        guard request.sourceFrameID != request.targetFrameID,
              (3...200).contains(request.validationPairs.count),
              request.validationPairs.allSatisfy({ !$0.id.isEmpty }),
              Set(request.validationPairs.map(\.id)).count == request.validationPairs.count else {
            throw CaptureError.invalid("Use distinct frames and 3–200 uniquely named validation pairs.")
        }
        for i in request.validationPairs.indices {
            for j in request.validationPairs.indices where j > i {
                let a = request.validationPairs[i], b = request.validationPairs[j]
                guard hypot(a.source.x-b.source.x, a.source.y-b.source.y) > 1e-6,
                      hypot(a.target.x-b.target.x, a.target.y-b.target.y) > 1e-6 else {
                    throw CaptureError.invalid("Validation pixels must be distinct in both frames.")
                }
            }
        }
        let source = try CalibratedLandmarks.load(bundle, frameID: request.sourceFrameID)
        let target = try CalibratedLandmarks.load(bundle, frameID: request.targetFrameID)
        guard source.manifest.kind == .frontFace, source.manifest.id == target.manifest.id else {
            throw CaptureError.invalid("Tracked initialization requires frames from one front capture.")
        }
        let transform = try relativeTransform(source: source.frame.metadata, target: target.frame.metadata)
        let residuals = try request.validationPairs.map { pair -> LandmarkResidual in
            let a = try CalibratedLandmarks.sample(pair.source, frame: source.frame.metadata,
                values: source.values, confidence: source.confidence)
            let b = try CalibratedLandmarks.sample(pair.target, frame: target.frame.metadata,
                values: target.values, confidence: target.confidence)
            return LandmarkResidual(id: pair.id, meters: (transform.apply(a)-b).length)
        }
        let sorted = residuals.map(\.meters).sorted(), n = residuals.count
        return HeadPoseRegistrationReport(captureID: source.manifest.id,
            sourceFrameID: request.sourceFrameID, targetFrameID: request.targetFrameID,
            sourceFrameSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(source.frame)),
            targetFrameSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(target.frame)),
            requestSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(request)),
            evidenceSource: source.manifest.source, anchorID: source.frame.metadata.headPose!.anchorID,
            targetFromSource: transform, validationResiduals: residuals,
            validationMedianMeters: n % 2 == 0 ? (sorted[n/2-1]+sorted[n/2])/2 : sorted[n/2],
            validationP95Meters: sorted[Int(ceil(Double(n)*0.95))-1],
            notes: ["No landmark was used to fit, refine or select the transform; all supplied residuals are retained.",
                    "Tracker pose is an initializer, not measured skull geometry or accepted fusion registration.",
                    "Depth/RGB optical calibration and tracker alignment still require physical validation.",
                    "A shared anchor identifies a tracking coordinate system, not verified subject identity."])
    }

    static func relativeTransform(source: FrameMetadata, target: FrameMetadata) throws -> RigidTransform {
        try CaptureBundle.validate(source); try CaptureBundle.validate(target)
        try CalibratedLandmarks.requireSynchronizedDepth(source)
        try CalibratedLandmarks.requireSynchronizedDepth(target)
        guard let a = source.headPose, let b = target.headPose, a.anchorID == b.anchorID,
              !source.mirrored, !target.mirrored,
              source.pixelOrientation == "sensor_native", target.pixelOrientation == "sensor_native" else {
            throw CaptureError.invalid("Both frames need the same tracked anchor and native unmirrored optical coordinates.")
        }
        // inverse(headFromTarget) * headFromSource: R_b^T R_a, R_b^T(t_a-t_b).
        let x = a.headFromOpticalCamera.rowMajor, y = b.headFromOpticalCamera.rowMajor
        var result = RigidTransform.identity.rowMajor
        for row in 0..<3 {
            for col in 0..<3 {
                result[row*4+col] = (0..<3).reduce(0.0) { $0 + y[$1*4+row]*x[$1*4+col] }
            }
            result[row*4+3] = (0..<3).reduce(0.0) { $0 + y[$1*4+row]*(x[$1*4+3]-y[$1*4+3]) }
        }
        let transform = RigidTransform(rowMajor: result)
        guard transform.isValid else { throw CaptureError.invalid("Relative tracked pose is invalid.") }
        return transform
    }
}
