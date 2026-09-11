import Foundation
import Vision
import ImageIO
import CoreML

public enum ImageQuarterTurn: String, Codable, CaseIterable, Sendable {
    case none, clockwise90, clockwise180, clockwise270
    var exif: CGImagePropertyOrientation {
        switch self { case .none: return .up; case .clockwise90: return .right; case .clockwise180: return .down; case .clockwise270: return .left }
    }
}

public enum LandmarkCoordinates {
    /// Vision global normalized coordinates have a lower-left origin in the
    /// upright image. Return continuous native sensor coordinates, upper-left.
    public static func nativePixel(_ normalized: PixelPoint, size: PixelSize, rotation: ImageQuarterTurn) throws -> PixelPoint {
        guard size.isValid, normalized.x.isFinite, normalized.y.isFinite,
              (0...1).contains(normalized.x), (0...1).contains(normalized.y) else { throw CaptureError.invalid("Invalid normalized landmark coordinates.") }
        let w = Double(size.width), h = Double(size.height)
        switch rotation {
        case .none: return PixelPoint(x: normalized.x*w, y: (1-normalized.y)*h)
        case .clockwise90: return PixelPoint(x: (1-normalized.y)*w, y: (1-normalized.x)*h)
        case .clockwise180: return PixelPoint(x: (1-normalized.x)*w, y: normalized.y*h)
        case .clockwise270: return PixelPoint(x: normalized.y*w, y: normalized.x*h)
        }
    }
}

public enum FaceLandmarkStatus: String, Codable, Sendable {
    case detected, noFace = "no_face", multipleFaces = "multiple_faces", lowConfidence = "low_confidence", missingLandmarks = "missing_landmarks"
}
public struct FaceLandmarkPoint: Codable, Sendable {
    /// Vision region name and within-region index, not an anatomical guarantee
    /// or a verified correspondence across strongly different poses.
    public var id: String
    public var region: String
    public var regionIndex: Int
    public var nativePixel: PixelPoint
    public var cameraPoint: Point3D?
    public var depthFailure: String?
}
public struct FaceLandmarkReport: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var method: String = "apple_vision_face_landmarks_revision_3_constellation_76"
    public var osVersion: String
    public var computePolicy: String
    public var captureID: String
    public var frameID: String
    public var frameSHA256: String
    public var source: CaptureSource
    public var nativeImageSize: PixelSize
    public var rotationToUpright: ImageQuarterTurn
    public var status: FaceLandmarkStatus
    public var faceCount: Int
    public var detectionConfidence: Double?
    public var minimumDetectionConfidence: Double
    public var minimumDepthConfidence: UInt8
    public var points: [FaceLandmarkPoint]
    public var notes: [String]
}

public enum FaceLandmarkExtractor {
    public static func extract(bundle: URL, frameID: String, rotation: ImageQuarterTurn,
                               minimumDetectionConfidence: Double = 0.7, minimumDepthConfidence: UInt8 = 1) throws -> FaceLandmarkReport {
        guard minimumDetectionConfidence.isFinite, (0...1).contains(minimumDetectionConfidence), minimumDepthConfidence <= 2 else {
            throw CaptureError.invalid("Invalid face/depth confidence threshold.")
        }
        let inspection = try CaptureBundle.inspect(bundle)
        guard inspection.valid else { throw CaptureError.invalid("Landmark extraction requires a valid capture bundle.") }
        let manifest = try CaptureBundle.load(bundle)
        guard manifest.status == .completed, let frame = manifest.frames.first(where: { $0.metadata.id == frameID }),
              frame.metadata.pixelOrientation == "sensor_native", !frame.metadata.mirrored else {
            throw CaptureError.invalid("Landmark extraction requires a completed, native unmirrored frame.")
        }
        if manifest.source == .sensor && frame.metadata.depthRectification == "synthetic_pinhole" {
            throw CaptureError.invalid("Sensor evidence cannot use synthetic calibration.")
        }
        let jpeg = try CaptureBundle.payload(frame.image, in: bundle)
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == frame.metadata.imageSize.width, image.height == frame.metadata.imageSize.height else {
            throw CaptureError.invalid("Decoded image dimensions disagree with the frame metadata.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString: Any]
        guard (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1 == 1 else {
            throw CaptureError.invalid("Native capture image contains an unexpected EXIF orientation.")
        }
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        request.constellation = .constellation76Points
        var computePolicy = "vision_automatic"
        #if targetEnvironment(simulator)
        // Simulator's default accelerator selection can fail to create an
        // inference context. Use a supported CPU device, never a fake result.
        let stages = try request.supportedComputeStageDevices
        guard !stages.isEmpty else { throw CaptureError.invalid("Vision reports no Simulator compute stages.") }
        for (stage,devices) in stages {
            guard let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) else {
                throw CaptureError.invalid("Vision has no supported CPU device for a Simulator compute stage.")
            }
            request.setComputeDevice(cpu, for: stage)
        }
        computePolicy = "simulator_supported_cpu_stages"
        #endif
        try VNImageRequestHandler(cgImage: image, orientation: rotation.exif, options: [:]).perform([request])
        let faces = request.results ?? []
        var report = FaceLandmarkReport(osVersion: ProcessInfo.processInfo.operatingSystemVersionString, computePolicy: computePolicy,
            captureID: manifest.id, frameID: frameID, frameSHA256: try HairArtifactHash.digest(frame), source: manifest.source,
            nativeImageSize: frame.metadata.imageSize, rotationToUpright: rotation, status: .noFace, faceCount: faces.count,
            minimumDetectionConfidence: minimumDetectionConfidence, minimumDepthConfidence: minimumDepthConfidence,
            points: [], notes: ["Model landmark estimates, not anatomical measurements or registration acceptance.",
                "Rotation is supplied explicitly because sensor-native captures do not yet record device-to-upright orientation.",
                "Vision region names are preserved. Anatomical side interpretation and cross-pose correspondences require validation.",
                "Missing or unreliable depth stays unavailable; no model-estimated depth is substituted.",
                "This is not a skin/hair segmentation mask and must not be used to fill hidden scalp."])
        guard !faces.isEmpty else { return report }
        guard faces.count == 1 else { report.status = .multipleFaces; return report }
        let face = faces[0]
        report.detectionConfidence = Double(face.confidence)
        guard Double(face.confidence) >= minimumDetectionConfidence else { report.status = .lowConfidence; return report }
        guard let landmarks = face.landmarks else { report.status = .missingLandmarks; return report }
        let regions: [(String, VNFaceLandmarkRegion2D?)] = [
            ("vision_face_contour",landmarks.faceContour), ("vision_left_eye",landmarks.leftEye),
            ("vision_right_eye",landmarks.rightEye), ("vision_left_eyebrow",landmarks.leftEyebrow),
            ("vision_right_eyebrow",landmarks.rightEyebrow), ("vision_nose",landmarks.nose),
            ("vision_nose_crest",landmarks.noseCrest), ("vision_median_line",landmarks.medianLine),
            ("vision_outer_lips",landmarks.outerLips), ("vision_inner_lips",landmarks.innerLips),
            ("vision_left_pupil",landmarks.leftPupil), ("vision_right_pupil",landmarks.rightPupil)]
        let depth = try frame.depth.flatMap { evidence in
            try frame.metadata.depthSize.map { try DepthGeometry.decode(CaptureBundle.payload(evidence, in: bundle), size: $0) }
        }
        let confidence = try frame.confidence.map { try CaptureBundle.payload($0, in: bundle) }
        for (name,optionalRegion) in regions {
            guard let region = optionalRegion else { continue }
            for (index,local) in region.normalizedPoints.enumerated() {
                let normalized = PixelPoint(x: face.boundingBox.minX + Double(local.x)*face.boundingBox.width,
                                            y: face.boundingBox.minY + Double(local.y)*face.boundingBox.height)
                let native: PixelPoint
                do { native = try LandmarkCoordinates.nativePixel(normalized, size: frame.metadata.imageSize, rotation: rotation) }
                catch {
                    report.notes.append("Skipped \(name):\(index): landmark lies outside usable image coordinates.")
                    continue
                }
                var point = FaceLandmarkPoint(id: "\(name):\(index)", region: name, regionIndex: index, nativePixel: native)
                if let depth {
                    do { point.cameraPoint = try CalibratedLandmarks.sample(native, frame: frame.metadata, values: depth,
                        confidence: confidence, minimumConfidence: minimumDepthConfidence) }
                    catch { point.depthFailure = error.localizedDescription }
                } else { point.depthFailure = "This frame contains no depth evidence." }
                report.points.append(point)
            }
        }
        report.status = report.points.isEmpty ? .missingLandmarks : .detected
        return report
    }
}
