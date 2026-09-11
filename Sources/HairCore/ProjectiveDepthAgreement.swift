import Foundation

public struct ProjectiveDepthRequest: Codable, Sendable {
    public var frameID: String
    public var mask: SurfaceMask
    public var cameraFromSurface: RigidTransform
    public var toleranceMeters: Double = 0.005
    public var minimumConfidence: UInt8 = 1
    public init(frameID: String, mask: SurfaceMask, cameraFromSurface: RigidTransform) {
        self.frameID = frameID; self.mask = mask; self.cameraFromSurface = cameraFromSurface
    }
}

public enum ProjectiveSampleState: String, Codable, Sendable {
    case behindCamera = "behind_camera"
    case outsideImage = "outside_image"
    case outsideMask = "outside_mask"
    case missingDepth = "missing_depth"
    case lowConfidence = "low_confidence"
    case consistent
    case behindObservedSurface = "behind_observed_surface"
    case inFrontOfObservedSurface = "in_front_of_observed_surface"
}

public struct ProjectiveSampleResidual: Codable, Sendable {
    public var sampleIndex: Int
    public var state: ProjectiveSampleState
    public var targetDepthPixelIndex: Int?
    public var projectedDepthMeters: Double
    public var observedDepthMeters: Double?
    /// Projected depth minus measured target depth, including disagreements.
    public var signedDifferenceMeters: Double?
}

public struct ProjectiveDepthReport: Codable, Sendable {
    public var schemaVersion = 1
    public var method = "projective_aligned_depth_diagnostic_v1"
    public var sourceSurfaceSHA256: String
    public var targetFrameSHA256: String
    public var requestSHA256: String
    public var counts: [String:Int]
    public var samples: [ProjectiveSampleResidual]
    public var acceptedForFusion = false
    public var notes: [String]
}

public enum ProjectiveDepthAgreement {
    public static func inspect(surface: ObservedSurface, targetBundle: URL, request: ProjectiveDepthRequest) throws -> ProjectiveDepthReport {
        guard !surface.completeHead, !surface.includesInferredAnatomy,
              surface.coordinateConvention == "reference_optical_x_right_y_down_z_forward_meters" else {
            throw CaptureError.invalid("Projective comparison requires an observed optical-coordinate surface.")
        }
        let integrity = try CaptureBundle.inspect(targetBundle)
        guard integrity.valid else { throw CaptureError.invalid("Target capture failed integrity checks.") }
        let manifest = try CaptureBundle.load(targetBundle)
        guard manifest.status == .completed,
              let frame = manifest.frames.first(where: { $0.metadata.id == request.frameID }),
              let depth = frame.depth, let size = frame.metadata.depthSize else {
            throw CaptureError.invalid("Projective comparison requires a completed target depth frame.")
        }
        if frame.metadata.depthRectification == "synthetic_pinhole" && manifest.source != .syntheticFixture {
            throw CaptureError.invalid("Sensor evidence cannot use synthetic calibration.")
        }
        if request.mask.provenance == .syntheticFixture && manifest.source != .syntheticFixture {
            throw CaptureError.invalid("Sensor evidence cannot use a synthetic mask.")
        }
        let values = try DepthGeometry.decode(CaptureBundle.payload(depth,in:targetBundle),size:size)
        let confidence = try frame.confidence.map { try CaptureBundle.payload($0,in:targetBundle) }
        let samples = try evaluate(points:surface.vertices.map(\.position),frame:frame.metadata,depth:values,confidence:confidence,request:request)
        var counts: [String:Int] = [:]
        for sample in samples { counts[sample.state.rawValue,default:0] += 1 }
        return ProjectiveDepthReport(sourceSurfaceSHA256:EvidenceHash.sha256(try ManifestCoding.encoder().encode(surface)),
            targetFrameSHA256:EvidenceHash.sha256(try ManifestCoding.encoder().encode(frame)),
            requestSHA256:EvidenceHash.sha256(try ManifestCoding.encoder().encode(request)),counts:counts,samples:samples,
            notes:["Fixed supplied transform; no alignment fitting or outlier removal is performed.",
                   "Behind-observed samples may be occluded, misaligned or affected by depth error. They are reported, not silently discarded.",
                   "Outside-mask and low-confidence samples remain in the denominator and have explicit states.",
                   "Nearest native target depth is used without filling holes or upsampling. The tolerance is provisional, not an accuracy certification.",
                   "Supports aligned pinhole target depth. Raw distorted front depth projection is not implemented.",
                   "Diagnostic only; target payload integrity is checked, but the supplied source surface and transform are not independently authenticated or approved for fusion."])
    }

    static func evaluate(points: [Point3D], frame: FrameMetadata, depth: [Float], confidence: Data?, request: ProjectiveDepthRequest) throws -> [ProjectiveSampleResidual] {
        try CaptureBundle.validate(frame); try CalibratedLandmarks.requireSynchronizedDepth(frame)
        guard request.frameID == frame.id, let size = frame.depthSize, let intrinsics = frame.intrinsics,
              size == request.mask.size, depth.count == size.width*size.height,
              confidence == nil || confidence!.count == depth.count,
              !frame.mirrored, frame.pixelOrientation == "sensor_native",
              ["arkit_aligned_scene_depth","synthetic_pinhole"].contains(frame.depthRectification),
              request.cameraFromSurface.isValid, (0.001...0.020).contains(request.toleranceMeters),
              request.minimumConfidence <= 2, (1...250_000).contains(points.count),
              points.allSatisfy({ $0.finite && $0.length <= 10 }) else {
            throw CaptureError.invalid("Invalid projective inputs or target depth is not an aligned pinhole image.")
        }
        let mask = try request.mask.decode(), k = intrinsics.scaled(to:size)
        return try points.enumerated().map { index,point in
            let p = request.cameraFromSurface.apply(point)
            guard p.finite, p.length <= 20 else { throw CaptureError.invalid("Transformed sample is outside the diagnostic coordinate bounds.") }
            var result = ProjectiveSampleResidual(sampleIndex:index,state:.behindCamera,projectedDepthMeters:p.z)
            guard p.z > 0 else { return result }
            let x = k.fx*p.x/p.z+k.cx, y = k.fy*p.y/p.z+k.cy
            result.state = .outsideImage
            guard x.isFinite, y.isFinite, x >= 0, y >= 0, x < Double(size.width), y < Double(size.height) else { return result }
            let xx = min(size.width-1,Int(x.rounded())), yy = min(size.height-1,Int(y.rounded())), pixel = yy*size.width+xx
            result.targetDepthPixelIndex = pixel
            result.state = .outsideMask
            guard mask[pixel] else { return result }
            result.state = .missingDepth
            let z = Double(depth[pixel])
            guard z.isFinite, (0.05...2).contains(z) else { return result }
            result.observedDepthMeters = z; result.signedDifferenceMeters = p.z-z
            if let confidence {
                let level = confidence[confidence.startIndex+pixel]
                if level > 2 || level < request.minimumConfidence { result.state = .lowConfidence; return result }
            }
            let delta = p.z-z
            result.state = abs(delta) <= request.toleranceMeters ? .consistent : delta > 0 ? .behindObservedSurface : .inFrontOfObservedSurface
            return result
        }
    }
}
