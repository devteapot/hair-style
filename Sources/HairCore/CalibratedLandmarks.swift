import Foundation

public struct PixelPoint: Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum LensGeometry {
    /// Point mapping from a distorted sensor image to the rectilinear plane.
    /// Apple's SDK reference uses the INVERSE table for this direction. The
    /// forward table is used when resampling a rectified destination image.
    public static func undistort(_ point: PixelPoint, lens: LensCalibration, referenceSize: PixelSize) throws -> PixelPoint {
        guard referenceSize.isValid, point.x.isFinite, point.y.isFinite,
              lens.centerX.isFinite, lens.centerY.isFinite,
              (0...Double(referenceSize.width)).contains(lens.centerX),
              (0...Double(referenceSize.height)).contains(lens.centerY),
              let table = lens.inverseLookupTable, table.count >= 2,
              table.allSatisfy({ $0.isFinite && $0 > -1 }) else {
            throw CaptureError.invalid("A valid inverse lens table and distortion center are required for point rectification.")
        }
        let dx = point.x - lens.centerX, dy = point.y - lens.centerY
        let maxX = max(lens.centerX, Double(referenceSize.width) - lens.centerX)
        let maxY = max(lens.centerY, Double(referenceSize.height) - lens.centerY)
        let radius = hypot(dx, dy), maximum = hypot(maxX, maxY)
        let position = min(Double(table.count - 1), radius / maximum * Double(table.count - 1))
        let lower = Int(floor(position)), upper = min(lower + 1, table.count - 1)
        let fraction = position - Double(lower)
        let magnification = Double(table[lower]) * (1 - fraction) + Double(table[upper]) * fraction
        return PixelPoint(x: lens.centerX + dx * (1 + magnification), y: lens.centerY + dy * (1 + magnification))
    }
}

public struct PixelLandmarkPair: Codable, Sendable {
    public var id: String
    public var source: PixelPoint
    public var target: PixelPoint
    public init(id: String, source: PixelPoint, target: PixelPoint) {
        self.id = id; self.source = source; self.target = target
    }
}

public struct CaptureLandmarkSelection: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var sourceFrameID: String
    public var targetFrameID: String
    public var fitPairs: [PixelLandmarkPair]
    public var validationPairs: [PixelLandmarkPair]
    public init(sourceFrameID: String, targetFrameID: String,
                fitPairs: [PixelLandmarkPair], validationPairs: [PixelLandmarkPair]) {
        self.sourceFrameID = sourceFrameID; self.targetFrameID = targetFrameID
        self.fitPairs = fitPairs; self.validationPairs = validationPairs
    }
}

public struct CapturedRegistrationReport: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var sourceFrameSHA256: String
    public var targetFrameSHA256: String
    public var selectionSHA256: String
    public var depthSampling: String = "nearest_pixel_depth_at_selected_image_ray"
    public var minimumConfidence: UInt8
    public var sourceLensCorrection: Bool
    public var targetLensCorrection: Bool
    public var registration: RegistrationReport
}

public enum CalibratedLandmarks {
    /// Provisional geometry-use gate. Keep raw evidence intact for diagnostics.
    /// Derive skew from source timestamps, never from a supplied quality summary.
    public static func requireSynchronizedDepth(_ frame: FrameMetadata) throws {
        guard let depthTime = frame.depthTimestamp, depthTime.isFinite, frame.imageTimestamp.isFinite,
              abs(frame.imageTimestamp - depthTime) <= 0.010 else {
            throw CaptureError.invalid("RGB/depth timestamps differ by more than 10 ms or are missing. Exclude this frame from geometry.")
        }
    }
    public static func register(sourceBundle: URL, targetBundle: URL, selection: CaptureLandmarkSelection,
                                minimumConfidence: UInt8 = 1) throws -> CapturedRegistrationReport {
        guard selection.schemaVersion == 1, minimumConfidence <= 2 else { throw CaptureError.invalid("Unsupported selection schema or confidence level.") }
        let source = try load(sourceBundle, frameID: selection.sourceFrameID)
        let target = try load(targetBundle, frameID: selection.targetFrameID)
        func pairs(_ pixels: [PixelLandmarkPair]) throws -> [LandmarkPair] {
            try pixels.map { pair in
                LandmarkPair(id: pair.id,
                    source: try sample(pair.source, frame: source.frame.metadata, values: source.values, confidence: source.confidence, minimumConfidence: minimumConfidence),
                    target: try sample(pair.target, frame: target.frame.metadata, values: target.values, confidence: target.confidence, minimumConfidence: minimumConfidence))
            }
        }
        let input = RegistrationInput(sourceFrameID: "\(source.manifest.id)/\(source.frame.metadata.id)",
            targetFrameID: "\(target.manifest.id)/\(target.frame.metadata.id)",
            evidenceSource: source.manifest.source == .sensor && target.manifest.source == .sensor ? .sensor : .syntheticFixture,
            fitPairs: try pairs(selection.fitPairs), validationPairs: try pairs(selection.validationPairs))
        let registration = try RigidRegistration.register(input)
        return CapturedRegistrationReport(
            sourceFrameSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(source.frame)),
            targetFrameSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(target.frame)),
            selectionSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(selection)), minimumConfidence: minimumConfidence,
            sourceLensCorrection: source.frame.metadata.depthRectification == "not_applied",
            targetLensCorrection: target.frame.metadata.depthRectification == "not_applied", registration: registration)
    }

    public static func sample(_ pixel: PixelPoint, frame: FrameMetadata, values: [Float],
                              confidence: Data? = nil, minimumConfidence: UInt8 = 1) throws -> Point3D {
        try CaptureBundle.validate(frame)
        try requireSynchronizedDepth(frame)
        guard minimumConfidence <= 2, pixel.x.isFinite, pixel.y.isFinite,
              pixel.x >= 0, pixel.y >= 0, pixel.x < Double(frame.imageSize.width), pixel.y < Double(frame.imageSize.height),
              let size = frame.depthSize, let k = frame.intrinsics,
              values.count == size.width * size.height else { throw CaptureError.invalid("Invalid image landmark or calibrated depth frame.") }
        guard !frame.mirrored, frame.pixelOrientation == "sensor_native" else {
            throw CaptureError.invalid("Landmarks must use unmirrored native image coordinates.")
        }
        let x = min(size.width - 1, Int((pixel.x * Double(size.width) / Double(frame.imageSize.width)).rounded()))
        let y = min(size.height - 1, Int((pixel.y * Double(size.height) / Double(frame.imageSize.height)).rounded()))
        if let confidence {
            guard confidence.count == values.count else { throw CaptureError.invalid("Confidence dimensions do not match depth.") }
            let sampleConfidence = confidence[confidence.startIndex + y * size.width + x]
            guard sampleConfidence <= 2, sampleConfidence >= minimumConfidence else { throw CaptureError.invalid("Landmark depth confidence is insufficient or invalid.") }
        }
        let depth = Double(values[y * size.width + x])
        guard depth.isFinite, (0.05...2).contains(depth) else { throw CaptureError.invalid("Selected landmark has no usable depth between 0.05 and 2 meters.") }
        var reference = PixelPoint(x: pixel.x * Double(k.referenceSize.width) / Double(frame.imageSize.width),
                                   y: pixel.y * Double(k.referenceSize.height) / Double(frame.imageSize.height))
        switch frame.depthRectification {
        case "synthetic_pinhole", "arkit_aligned_scene_depth": break
        case "not_applied":
            guard let lens = frame.lensCalibration else { throw CaptureError.invalid("Unrectified depth has no lens calibration; registration is unavailable.") }
            reference = try LensGeometry.undistort(reference, lens: lens, referenceSize: k.referenceSize)
        default: throw CaptureError.invalid("Unknown depth rectification convention.")
        }
        return Point3D(x: (reference.x - k.cx) * depth / k.fx, y: (reference.y - k.cy) * depth / k.fy, z: depth)
    }

    static func load(_ url: URL, frameID: String) throws -> (manifest: CaptureManifest, frame: StoredFrame, values: [Float], confidence: Data?) {
        let report = try CaptureBundle.inspect(url)
        guard report.valid else { throw CaptureError.invalid("Capture integrity failed: \(report.errors.joined(separator: "; "))") }
        let manifest = try CaptureBundle.load(url)
        guard manifest.status == .completed, [.frontFace, .rearHead].contains(manifest.kind),
              let frame = manifest.frames.first(where: { $0.metadata.id == frameID }),
              let evidence = frame.depth, let size = frame.metadata.depthSize else {
            throw CaptureError.invalid("Registration requires a finished geometry pass and a selected depth frame.")
        }
        if frame.metadata.depthRectification == "synthetic_pinhole" && manifest.source != .syntheticFixture {
            throw CaptureError.invalid("Sensor evidence cannot claim synthetic calibration.")
        }
        let values = try DepthGeometry.decode(CaptureBundle.payload(evidence, in: url), size: size)
        let confidence = try frame.confidence.map { try CaptureBundle.payload($0, in: url) }
        return (manifest, frame, values, confidence)
    }
}
