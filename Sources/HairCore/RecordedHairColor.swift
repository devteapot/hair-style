import Foundation

/// Lighting-dependent recorded RGB, retained with the edit rather than promoted to intrinsic color.
public struct RecordedHairColor: Codable, Sendable {
    public var subjectSessionID: String
    public var captureID: String
    public var frameID: String
    public var reportSHA256: String
    public var imageSHA256: String
    public var rgb: [Double]

    public static func fromReport(_ data: Data, bundle: URL, frameID: String) throws -> Self {
        let report = try HairImageAnalysis.validated(data, bundle: bundle, frameID: frameID)
        guard let color = report.observation.recordedColor else { throw CaptureError.invalid("The image has insufficient color support.") }
        let manifest = try CaptureBundle.load(bundle)
        return Self(subjectSessionID: manifest.subjectSessionID, captureID: report.captureID,
            frameID: report.frameID, reportSHA256: EvidenceHash.sha256(data), imageSHA256: report.imageSHA256, rgb: color.median)
    }
    public static func saved(bundle: URL, frameID: String) throws -> Self? {
        let url = try HairImageAnalysis.location(bundle: bundle, frameID: frameID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576 else {
            throw CaptureError.invalid("Saved image report is too large.")
        }
        return try fromReport(Data(contentsOf: url), bundle: bundle, frameID: frameID)
    }
    func validate(subjectSessionID: String) throws {
        guard self.subjectSessionID == subjectSessionID, UUID(uuidString: captureID) != nil,
              UUID(uuidString: frameID) != nil, HairArtifactHash.valid(reportSHA256), HairArtifactHash.valid(imageSHA256),
              rgb.count == 3, rgb.allSatisfy({ $0.isFinite && (0...255).contains($0) }) else {
            throw CaptureError.invalid("Recorded color has invalid provenance or belongs to a different person.")
        }
    }
    /// Preview approximation: the stored JPEG RGB is treated as sRGB; no illuminant correction.
    var linearRGB: [Double] {
        rgb.map { component in
            let v = component/255
            return v <= 0.04045 ? v/12.92 : pow((v+0.055)/1.055, 2.4)
        }
    }
}
