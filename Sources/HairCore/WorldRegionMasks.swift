import Foundation

/// A spatial crop, not a semantic head/skin mask. Coordinates belong to one capture's AR world.
public struct WorldRegionRequest: Codable, Sendable {
    public var center: Point3D
    public var radii: Point3D
    public var selectionProvenance: MaskProvenance
    public var selectionMethod: String
    public var minimumConfidence: UInt8 = 1
    /// Optional lower world-Y crop plane. An explicit estimate, never automatic neck segmentation.
    public var minimumWorldY: Double? = nil
    public init(center: Point3D, radii: Point3D, selectionProvenance: MaskProvenance, selectionMethod: String) {
        self.center = center; self.radii = radii
        self.selectionProvenance = selectionProvenance; self.selectionMethod = selectionMethod
    }
}

public struct WorldRegionFrame: Codable, Sendable {
    public var frameID: String
    public var frameSHA256: String
    public var mask: SurfaceMask?
    public var includedSamples: Int
    public var invalidDepthSamples: Int
    public var lowConfidenceSamples: Int
    public var outsideRegionSamples: Int
    public var skippedReason: String?
}

public struct WorldRegionReport: Codable, Sendable {
    public var schemaVersion = 1
    public var method = "fixed_world_ellipsoid_crop_v1"
    public var captureID: String
    public var requestSHA256: String
    public var frames: [WorldRegionFrame]
    public var acceptedForFusion = false
    public var notes: [String]
}

public enum WorldRegionMasks {
    public static func build(bundle: URL, request: WorldRegionRequest) throws -> WorldRegionReport {
        try validate(request)
        let integrity = try CaptureBundle.inspect(bundle)
        guard integrity.valid else { throw CaptureError.invalid("Region masking requires intact capture payloads.") }
        let manifest = try CaptureBundle.load(bundle)
        guard manifest.status == .completed, manifest.kind == .rearHead, manifest.frames.count <= 1200 else {
            throw CaptureError.invalid("Region masking requires a completed rear capture of at most 1200 frames.")
        }
        guard request.selectionProvenance != .syntheticFixture || manifest.source == .syntheticFixture else {
            throw CaptureError.invalid("Sensor capture cannot use a synthetic selection.")
        }
        var results: [WorldRegionFrame] = []
        for frame in manifest.frames {
            let hash = EvidenceHash.sha256(try ManifestCoding.encoder().encode(frame))
            if frame.metadata.quality.trackingState != "normal" {
                results.append(WorldRegionFrame(frameID:frame.metadata.id,frameSHA256:hash,mask:nil,
                    includedSamples:0,invalidDepthSamples:0,lowConfidenceSamples:0,outsideRegionSamples:0,
                    skippedReason:"Camera world tracking is not normal; no samples processed."))
                continue
            }
            guard let size = frame.metadata.depthSize, let depth = frame.depth, let confidence = frame.confidence,
                  frame.metadata.poseSource == "arkit_world_tracking",
                  frame.metadata.depthRectification == "arkit_aligned_scene_depth" else {
                throw CaptureError.invalid("Tracked rear frame is missing aligned depth, confidence or world pose provenance.")
            }
            var result = try evaluate(frame:frame.metadata,
                depth:DepthGeometry.decode(CaptureBundle.payload(depth,in:bundle),size:size),
                confidence:CaptureBundle.payload(confidence,in:bundle),request:request)
            result.frameSHA256 = hash; results.append(result)
        }
        return WorldRegionReport(captureID:manifest.id,requestSHA256:EvidenceHash.sha256(try ManifestCoding.encoder().encode(request)),
            frames:results,notes:["Fixed ellipsoid in this capture's AR world; dimensions and center are supplied estimates, not anatomical measurements.",
                "Spatial filtering removes points outside the region and optional lower world-Y plane; retained points may include hair, clips, hands, neck or background.",
                "Camera world poses do not compensate for head movement. These masks do not establish head registration or authorize fusion.",
                "Each included mask sample refers to an original native depth pixel; no depth interpolation or completion.",
                "Tracking failures skip complete frames; all other processed depth pixels are accounted for by inclusion or an exclusion category."])
    }

    static func validate(_ request: WorldRegionRequest) throws {
        guard request.center.finite, request.center.length <= 20, request.radii.finite,
              [request.radii.x,request.radii.y,request.radii.z].allSatisfy({ (0.02...0.5).contains($0) }),
              request.minimumConfidence <= 2, !request.selectionMethod.isEmpty, request.selectionMethod.count <= 2000 else {
            throw CaptureError.invalid("Invalid world region or selection evidence.")
        }
        if let lower = request.minimumWorldY, !lower.isFinite || abs(lower) > 20 {
            throw CaptureError.invalid("Invalid lower world-Y crop plane.")
        }
    }

    static func evaluate(frame: FrameMetadata, depth: [Float], confidence: Data, request: WorldRegionRequest) throws -> WorldRegionFrame {
        try validate(request); try CaptureBundle.validate(frame); try CalibratedLandmarks.requireSynchronizedDepth(frame)
        guard let size = frame.depthSize, size.width*size.height <= 1_000_000,
              depth.count == size.width*size.height, confidence.count == depth.count,
              let intrinsics = frame.intrinsics, let pose = frame.worldFromOpticalCamera, pose.isValid,
              frame.quality.trackingState == "normal", frame.poseSource == "arkit_world_tracking",
              frame.depthRectification == "arkit_aligned_scene_depth",
              !frame.mirrored, frame.pixelOrientation == "sensor_native" else {
            throw CaptureError.invalid("World cropping requires synchronized aligned depth and normal world tracking.")
        }
        let k = intrinsics.scaled(to:size)
        var result = WorldRegionFrame(frameID:frame.id,frameSHA256:"",mask:nil,includedSamples:0,
            invalidDepthSamples:0,lowConfidenceSamples:0,outsideRegionSamples:0)
        var runs: [MaskRun] = []
        for pixel in depth.indices {
            let z = Double(depth[pixel])
            guard z.isFinite, (0.05...2).contains(z) else { result.invalidDepthSamples += 1; continue }
            let level = confidence[confidence.startIndex+pixel]
            guard level <= 2, level >= request.minimumConfidence else { result.lowConfidenceSamples += 1; continue }
            let camera = Point3D(x:(Double(pixel % size.width)-k.cx)*z/k.fx,
                                 y:(Double(pixel / size.width)-k.cy)*z/k.fy,z:z)
            let world = pose.apply(camera), delta = world-request.center
            let x = delta.x/request.radii.x, y = delta.y/request.radii.y, zz = delta.z/request.radii.z
            guard world.finite else { throw CaptureError.invalid("Invalid transformed world coordinate.") }
            guard x*x+y*y+zz*zz <= 1, world.y >= (request.minimumWorldY ?? -.infinity) else { result.outsideRegionSamples += 1; continue }
            result.includedSamples += 1
            if let last = runs.last, last.start+last.count == pixel { runs[runs.count-1].count += 1 }
            else { runs.append(MaskRun(start:pixel,count:1)) }
        }
        if !runs.isEmpty {
            result.mask = SurfaceMask(size:size,provenance:request.selectionProvenance,
                method:"Spatial crop only, not semantic segmentation. " + request.selectionMethod,includedRuns:runs)
        }
        return result
    }
}
