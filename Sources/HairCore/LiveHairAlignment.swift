import Foundation

public struct LiveCalibrationRequest: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var scalpSHA256: String
    public var trackingSessionID: String
    public var anchorID: String
    public var landmarkEvidenceSHA256: String
    /// Sources are personal canonical head points; targets are AR face-local points.
    public var registration: RegistrationInput
    public init(scalpSHA256: String, trackingSessionID: String, anchorID: String,
                landmarkEvidenceSHA256: String, registration: RegistrationInput) {
        self.scalpSHA256 = scalpSHA256; self.trackingSessionID = trackingSessionID
        self.anchorID = anchorID; self.landmarkEvidenceSHA256 = landmarkEvidenceSHA256
        self.registration = registration
    }
}
public struct LiveHairCalibration: Codable, Sendable {
    public var request: LiveCalibrationRequest
    public var requestSHA256: String
    public var registration: RegistrationReport
}
public enum LiveHairAlignment {
    public static func calibrate(_ request: LiveCalibrationRequest, scalp: ScalpProfile) throws -> LiveHairCalibration {
        guard request.schemaVersion == 1, request.scalpSHA256 == (try HairArtifactHash.digest(scalp)),
              UUID(uuidString: request.trackingSessionID) != nil, UUID(uuidString: request.anchorID) != nil,
              HairArtifactHash.valid(request.landmarkEvidenceSHA256),
              request.registration.sourceFrameID == "personal_canonical",
              request.registration.targetFrameID == "ar_face_local",
              (request.registration.fitPairs + request.registration.validationPairs).allSatisfy({
                  $0.source.length <= 0.5 && $0.target.length <= 0.5
              }) else { throw CaptureError.invalid("Invalid live calibration identity, frames, evidence or metric landmarks.") }
        let report = try RigidRegistration.register(request.registration)
        guard report.accepted else { throw CaptureError.invalid("Live alignment failed independent landmark validation.") }
        return LiveHairCalibration(request: request, requestSHA256: try HairArtifactHash.digest(request), registration: report)
    }

    /// worldFromFace * faceFromCanonical, using column vectors and row-major storage.
    public static func worldFromCanonical(worldFromFace: RigidTransform, calibration: LiveHairCalibration) throws -> RigidTransform {
        guard worldFromFace.isValid, calibration.registration.targetFromSource.isValid else {
            throw CaptureError.invalid("Invalid live rigid transform.")
        }
        let a = worldFromFace.rowMajor, b = calibration.registration.targetFromSource.rowMajor
        var c = [Double](repeating: 0, count: 16)
        for row in 0..<4 { for column in 0..<4 {
            for k in 0..<4 { c[row*4+column] += a[row*4+k] * b[k*4+column] }
        } }
        let result = RigidTransform(rowMajor: c)
        guard result.isValid else { throw CaptureError.invalid("Composed live transform is not rigid.") }
        return result
    }
}

public struct LiveFaceSample: Sendable {
    public var trackingSessionID: String
    public var anchorID: String
    /// Monotonic seconds from the same clock as presentation(now:).
    public var timestamp: Double
    public var tracked: Bool
    /// Number of face anchors reported for this frame, including untracked anchors.
    public var faceCount: Int
    public var worldFromFace: RigidTransform
    public init(trackingSessionID: String, anchorID: String, timestamp: Double,
                tracked: Bool, worldFromFace: RigidTransform, faceCount: Int = 1) {
        self.trackingSessionID = trackingSessionID; self.anchorID = anchorID
        self.timestamp = timestamp; self.tracked = tracked; self.worldFromFace = worldFromFace
        self.faceCount = faceCount
    }
}
public enum LiveOverlayState: String, Codable, Sendable {
    case acquiring, visible, trackingLost = "tracking_lost", recalibrationRequired = "recalibration_required"
}
public struct LiveOverlayPresentation: Sendable {
    public var state: LiveOverlayState
    public var worldFromCanonical: RigidTransform?
}

/// Stateful gating independent of ARKit, reusable by a renderer's frame callback.
/// The renderer must call presentation every display frame, even without new samples.
public struct LiveHairTracker: Sendable {
    private let calibration: LiveHairCalibration
    private var state: LiveOverlayState = .acquiring
    private var lastTimestamp: Double?
    private var lastTransform: RigidTransform?
    private var previousFacePose: RigidTransform?
    private var consecutive = 0
    public init(calibration: LiveHairCalibration, scalp: ScalpProfile) throws {
        // Recompute supplied evidence rather than trusting a decoded accepted flag.
        let verified = try LiveHairAlignment.calibrate(calibration.request, scalp: scalp)
        guard try HairArtifactHash.digest(verified) == HairArtifactHash.digest(calibration) else {
            throw CaptureError.invalid("Live calibration record was modified.")
        }
        self.calibration = verified
    }

    public mutating func update(_ sample: LiveFaceSample) throws {
        guard sample.timestamp.isFinite, sample.timestamp >= 0 else {
            if state != .recalibrationRequired { state = .trackingLost }
            consecutive = 0; lastTransform = nil; previousFacePose = nil
            throw CaptureError.invalid("Live sample timestamp must be finite and nonnegative.")
        }
        guard state != .recalibrationRequired else { return }
        // Ambiguity latches even if the calibrated anchor remains present.
        // Returning to one face must not silently restore the overlay.
        guard sample.faceCount >= 0, sample.faceCount <= 1 else {
            interrupt()
            return
        }
        guard sample.trackingSessionID == calibration.request.trackingSessionID,
              sample.anchorID == calibration.request.anchorID else {
            state = .recalibrationRequired; consecutive = 0; lastTransform = nil; return
        }
        if let lastTimestamp, sample.timestamp <= lastTimestamp { return } // Ignore late callbacks.
        if let lastTimestamp, sample.timestamp - lastTimestamp > 0.2 { consecutive = 0; previousFacePose = nil }
        lastTimestamp = sample.timestamp
        guard sample.faceCount == 1, sample.tracked, sample.worldFromFace.isValid else {
            state = .trackingLost; consecutive = 0; lastTransform = nil; previousFacePose = nil; return
        }
        if let previousFacePose {
            let a = previousFacePose.rowMajor, b = sample.worldFromFace.rowMajor
            let displacement = Point3D(x: a[3]-b[3], y: a[7]-b[7], z: a[11]-b[11]).length
            let trace = [0,1,2,4,5,6,8,9,10].reduce(0.0) { $0 + a[$1]*b[$1] }
            let angle = acos(min(1, max(-1, (trace-1)/2)))
            if displacement > 0.25 || angle > Double.pi/3 {
                state = .recalibrationRequired; consecutive = 0; lastTransform = nil; return
            }
        }
        previousFacePose = sample.worldFromFace
        lastTransform = try LiveHairAlignment.worldFromCanonical(worldFromFace: sample.worldFromFace, calibration: calibration)
        consecutive += 1
        state = consecutive >= 3 ? .visible : .acquiring
    }

    public mutating func presentation(now: Double) -> LiveOverlayPresentation {
        guard now.isFinite, now >= 0 else {
            if state != .recalibrationRequired { state = .trackingLost }
            consecutive = 0; lastTransform = nil; previousFacePose = nil
            return LiveOverlayPresentation(state: state, worldFromCanonical: nil)
        }
        if state != .recalibrationRequired, let lastTimestamp,
           now < lastTimestamp || now - lastTimestamp > 0.2 {
            state = .trackingLost; consecutive = 0; lastTransform = nil; previousFacePose = nil
        }
        return LiveOverlayPresentation(state: state, worldFromCanonical: state == .visible ? lastTransform : nil)
    }

    public mutating func interrupt() {
        state = .recalibrationRequired; consecutive = 0; lastTransform = nil
    }
}
