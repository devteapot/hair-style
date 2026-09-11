import Foundation

/// Review-only summary of the local image analysis. Does not accept a profile or 3D fit.
public struct HairImageAnalysis: Codable, Sendable {
    public struct RecordedColor: Codable, Sendable {
        public var space: String
        public var sampleCount: Int
        public var median: [Double]
        public var intrinsicColorCalibrated: Bool
    }
    public struct Observation: Codable, Sendable {
        public var hairPixels: Int
        public var interiorPixels: Int
        public var recordedColor: RecordedColor?
        public var semanticAccuracyValidated: Bool
    }
    public struct Orientation: Codable, Sendable {
        public var supportedPixels: Int
        public var directed: Bool
        public var rootToTipMeasured: Bool
        public var accuracyValidated: Bool
    }
    public var schemaVersion: Int
    public var method: String
    public var captureID: String
    public var frameID: String
    public var sourceManifestSHA256: String
    public var imageSHA256: String
    public var imageSize: PixelSize
    public var captureCondition: HairCaptureCondition
    public var captureConditionSource: String
    public var observation: Observation
    public var textureOrientation: Orientation?
    public var acceptedForNaturalHairBaseline: Bool
    public var registeredToHead: Bool

    public static func validated(_ data: Data, bundle: URL, frameID: String) throws -> Self {
        guard data.count <= 1_048_576 else { throw CaptureError.invalid("Hair analysis exceeds the review size limit.") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        let manifestData = try Data(contentsOf: bundle.appendingPathComponent("manifest.json"))
        let manifest = try ManifestCoding.decoder().decode(CaptureManifest.self, from: manifestData)
        guard manifest.status != .recording, value.schemaVersion == 1,
              value.method == "local_segformer_hair_image_v1", value.captureID == manifest.id,
              value.sourceManifestSHA256 == EvidenceHash.sha256(manifestData), value.frameID == frameID,
              let frame = manifest.frames.first(where: { $0.metadata.id == frameID }),
              value.imageSHA256 == frame.image.sha256, value.imageSize == frame.metadata.imageSize,
              value.imageSize.isValid, !value.acceptedForNaturalHairBaseline, !value.registeredToHead,
              !value.observation.semanticAccuracyValidated else {
            throw CaptureError.invalid("Hair analysis does not match this saved frame or its review-only contract.")
        }
        _ = try CaptureBundle.payload(frame.image, in: bundle)
        if let declared = manifest.declaredHairCondition, declared != .unknown, declared != value.captureCondition {
            throw CaptureError.invalid("Hair analysis conflicts with the saved hair preparation.")
        }
        guard ["unknown", "operator_assertion", "participant_declaration"].contains(value.captureConditionSource),
              value.captureConditionSource != "participant_declaration" || manifest.declaredHairCondition == value.captureCondition else {
            throw CaptureError.invalid("Hair preparation provenance is inconsistent.")
        }
        let pixels = value.imageSize.width * value.imageSize.height
        let o = value.observation
        guard (0...pixels).contains(o.hairPixels), (0...o.hairPixels).contains(o.interiorPixels) else {
            throw CaptureError.invalid("Invalid hair analysis pixel counts.")
        }
        if let c = o.recordedColor {
            guard c.space == "recorded_rgb_uint8", c.sampleCount == o.interiorPixels, c.sampleCount >= 100,
                  !c.intrinsicColorCalibrated, c.median.count == 3,
                  c.median.allSatisfy({ $0.isFinite && (0...255).contains($0) }) else {
                throw CaptureError.invalid("Invalid recorded color estimate.")
            }
        }
        if let a = value.textureOrientation {
            guard (0...o.hairPixels).contains(a.supportedPixels), !a.directed,
                  !a.rootToTipMeasured, !a.accuracyValidated else {
                throw CaptureError.invalid("Invalid image texture orientation claims.")
            }
        }
        return value
    }

    private static func location(bundle: URL, frameID: String) throws -> URL {
        guard UUID(uuidString: frameID) != nil else { throw CaptureError.invalid("Invalid frame identifier.") }
        return bundle.appendingPathComponent("analysis/hair/\(frameID).json")
    }
    public static func save(_ data: Data, bundle: URL, frameID: String) throws -> Self {
        let value = try validated(data, bundle: bundle, frameID: frameID)
        let url = try location(bundle: bundle, frameID: frameID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try EvidenceIO.write(data, to: url)
        return value
    }
    public static func load(bundle: URL, frameID: String) throws -> Self? {
        let url = try location(bundle: bundle, frameID: frameID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try validated(Data(contentsOf: url), bundle: bundle, frameID: frameID)
    }
}
