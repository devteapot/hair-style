import Foundation

public struct MaskRun: Codable, Sendable {
    public var start: Int
    public var count: Int
    public init(start: Int, count: Int) { self.start = start; self.count = count }
}

public enum MaskProvenance: String, Codable, Sendable {
    case userSelected = "user_selected", modelInferred = "model_inferred", syntheticFixture = "synthetic_fixture"
}

/// Inclusion mask at native depth resolution. Hair/background/obstructions must
/// be excluded by the caller. This builder does not infer semantic segmentation.
public struct SurfaceMask: Codable, Sendable {
    public var size: PixelSize
    public var provenance: MaskProvenance
    public var method: String
    public var includedRuns: [MaskRun]
    public init(size: PixelSize, provenance: MaskProvenance, method: String, includedRuns: [MaskRun]) {
        self.size = size; self.provenance = provenance; self.method = method; self.includedRuns = includedRuns
    }
    func decode() throws -> [Bool] {
        guard size.isValid, size.width * size.height <= 1_000_000,
              !method.isEmpty, includedRuns.count <= size.width * size.height else { throw CaptureError.invalid("Invalid surface mask or depth exceeds the one-million-pixel processing limit.") }
        var mask = [Bool](repeating: false, count: size.width * size.height)
        var previousEnd = 0
        for run in includedRuns {
            guard run.start >= previousEnd, run.count > 0, run.start < mask.count, run.count <= mask.count - run.start else {
                throw CaptureError.invalid("Mask runs must be sorted, disjoint and within depth dimensions.")
            }
            for i in run.start..<(run.start + run.count) { mask[i] = true }
            previousEnd = run.start + run.count
        }
        guard mask.contains(true) else { throw CaptureError.invalid("Surface mask contains no included samples.") }
        return mask
    }
}

public struct SurfaceFrameRequest: Codable, Sendable {
    public var captureID: String
    public var frameID: String
    public var mask: SurfaceMask
    public var registrationToReference: CaptureLandmarkSelection?
    public var componentSelection: SurfaceComponentSelection? = nil
    public init(captureID: String, frameID: String, mask: SurfaceMask, registrationToReference: CaptureLandmarkSelection? = nil,
                componentSelection: SurfaceComponentSelection? = nil) {
        self.captureID = captureID; self.frameID = frameID; self.mask = mask; self.registrationToReference = registrationToReference
        self.componentSelection = componentSelection
    }
}

public struct SurfaceRequest: Codable, Sendable {
    public var schemaVersion: Int = 1
    /// First frame establishes the output optical-camera coordinates.
    public var frames: [SurfaceFrameRequest]
    public var samplingStride: Int = 2
    public var minimumConfidence: UInt8 = 1
    public var maximumEdgeMeters: Double = 0.02
    public var fusionRadiusMeters: Double = 0.0015
    public init(frames: [SurfaceFrameRequest]) { self.frames = frames }
}

public struct SurfaceObservation: Codable, Sendable {
    public var frameIndex: Int
    public var depthPixelIndex: Int
}

public struct SurfaceVertex: Codable, Sendable {
    public var position: Point3D
    public var normal: Point3D
    public var observations: [SurfaceObservation]
}

public struct SurfaceFrameEvidence: Codable, Sendable {
    public var captureID: String
    public var frameID: String
    public var frameSHA256: String
    public var maskSHA256: String
    public var source: CaptureSource
    public var referenceFromCamera: RigidTransform
    public var registration: CapturedRegistrationReport?
    public var retainedSamples: Int
    public var skippedSamples: Int
    public var componentCleanup: SurfaceComponentReport? = nil
}

public struct ObservedSurface: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var method: String = "masked_depth_patch_fusion_v1"
    public var requestSHA256: String
    public var coordinateConvention: String = "reference_optical_x_right_y_down_z_forward_meters"
    public var source: CaptureSource
    public var vertices: [SurfaceVertex]
    public var triangles: [[Int]]
    public var frames: [SurfaceFrameEvidence]
    public var includesInferredAnatomy: Bool = false
    public var completeHead: Bool = false
    public var notes: [String]

    public func ply() -> Data {
        var text = "ply\nformat ascii 1.0\ncomment observed depth surface; not a complete head\nelement vertex \(vertices.count)\nproperty float x\nproperty float y\nproperty float z\nproperty float nx\nproperty float ny\nproperty float nz\nelement face \(triangles.count)\nproperty list uchar int vertex_indices\nend_header\n"
        for v in vertices { text += "\(v.position.x) \(v.position.y) \(v.position.z) \(v.normal.x) \(v.normal.y) \(v.normal.z)\n" }
        for t in triangles { text += "3 \(t[0]) \(t[1]) \(t[2])\n" }
        return Data(text.utf8)
    }
}

public enum ObservedSurfaceBuilder {
    public static func build(captureRoot: URL, request: SurfaceRequest) throws -> ObservedSurface {
        guard request.schemaVersion == 1, (1...8).contains(request.frames.count), (1...8).contains(request.samplingStride),
              request.minimumConfidence <= 2, (0.002...0.05).contains(request.maximumEdgeMeters),
              (0.0001...0.003).contains(request.fusionRadiusMeters) else { throw CaptureError.invalid("Invalid surface request or processing limits.") }
        let reference = request.frames[0]
        guard reference.registrationToReference == nil else { throw CaptureError.invalid("The reference frame must not supply a registration.") }
        let referenceURL = try bundleURL(reference.captureID, root: captureRoot)
        let referenceManifest = try CaptureBundle.load(referenceURL)
        guard let referenceFrame = referenceManifest.frames.first(where: { $0.metadata.id == reference.frameID }) else {
            throw CaptureError.invalid("Reference frame is missing.")
        }
        let referenceMask = try reference.mask.decode()
        var inspected = Set<String>()
        var keys = Set<String>(), evidences: [SurfaceFrameEvidence] = [], vertices: [SurfaceVertex] = [], faces: [[Int]] = []
        var anchors: [Point3D] = [], normalSums: [Point3D] = [], pointSums: [Point3D] = []
        var cells: [Cell: [Int]] = [:]
        var seenFaces = Set<String>()
        var source: CaptureSource = .sensor

        for (frameIndex, item) in request.frames.enumerated() {
            guard keys.insert("\(item.captureID)/\(item.frameID)").inserted else { throw CaptureError.invalid("Duplicate surface frame.") }
            let url = try bundleURL(item.captureID, root: captureRoot)
            if inspected.insert(item.captureID).inserted {
                let integrity = try CaptureBundle.inspect(url)
                guard integrity.valid else { throw CaptureError.invalid("Surface capture failed integrity validation.") }
            }
            let manifest = try CaptureBundle.load(url)
            guard manifest.id == item.captureID, manifest.status == .completed,
                  manifest.subjectSessionID == referenceManifest.subjectSessionID,
                  [.frontFace, .rearHead].contains(manifest.kind),
                  let frame = manifest.frames.first(where: { $0.metadata.id == item.frameID }),
                  let depth = frame.depth, let size = frame.metadata.depthSize,
                  size == item.mask.size else { throw CaptureError.invalid("Surface frame or mask does not match a completed geometry capture.") }
            if manifest.source == .syntheticFixture { source = .syntheticFixture }
            if manifest.source == .sensor && (item.mask.provenance == .syntheticFixture || frame.metadata.depthRectification == "synthetic_pinhole") {
                throw CaptureError.invalid("Sensor captures cannot use synthetic mask/calibration provenance.")
            }
            try CaptureBundle.validate(frame.metadata)
            try CalibratedLandmarks.requireSynchronizedDepth(frame.metadata)
            _ = try CaptureBundle.payload(frame.image, in: url)
            let values = try DepthGeometry.decode(CaptureBundle.payload(depth, in: url), size: size)
            let confidence = try frame.confidence.map { try CaptureBundle.payload($0, in: url) }
            if let confidence, confidence.count != values.count { throw CaptureError.invalid("Confidence size mismatch.") }
            let mask = try item.mask.decode()
            var transform = RigidTransform.identity
            var registration: CapturedRegistrationReport?
            if frameIndex > 0 {
                guard let selection = item.registrationToReference,
                      selection.sourceFrameID == item.frameID, selection.targetFrameID == reference.frameID else {
                    throw CaptureError.invalid("Every contributor needs landmark registration to the reference frame.")
                }
                for pair in selection.fitPairs + selection.validationPairs {
                    guard included(pair.source, frame: frame.metadata, mask: mask, size: item.mask.size),
                          included(pair.target, frame: referenceFrame.metadata, mask: referenceMask, size: reference.mask.size) else {
                        throw CaptureError.invalid("Registration landmarks must fall within both surface masks.")
                    }
                }
                let result = try CalibratedLandmarks.register(sourceBundle: url, targetBundle: referenceURL,
                    selection: selection, minimumConfidence: request.minimumConfidence)
                guard result.registration.accepted else { throw CaptureError.invalid("A contributor failed independent registration validation.") }
                registration = result; transform = result.registration.targetFromSource
            }
            let prepared = try prepare(frame.metadata)
            let step = request.samplingStride
            var projected = [Int: Point3D]()
            func usable(_ i: Int) -> Bool {
                guard mask[i], values[i].isFinite, (0.05...2).contains(values[i]) else { return false }
                if let confidence {
                    let level = confidence[confidence.startIndex + i]
                    return level >= request.minimumConfidence && level <= 2
                }
                return true
            }
            var skipped = 0
            for y in stride(from: 0, to: size.height, by: step) {
                for x in stride(from: 0, to: size.width, by: step) {
                    let i = y * size.width + x
                    if usable(i) {
                        let point = transform.apply(try prepared.project(x: x, y: y, depth: Double(values[i])))
                        guard point.finite, point.length <= 10 else {
                            throw CaptureError.invalid("Surface calibration or registration projects outside the 10-meter processing bounds.")
                        }
                        projected[i] = point
                    }
                    else { skipped += 1 }
                }
            }
            var localFaces: [[Int]] = [], localNormals: [Int: Point3D] = [:]
            for y in stride(from: 0, to: size.height - step, by: step) {
                for x in stride(from: 0, to: size.width - step, by: step) {
                    // Reject the complete coarse cell if a skipped interior sample is
                    // masked/invalid, rather than bridging a hole with a large triangle.
                    var complete = true
                    for yy in y...(y+step) { for xx in x...(x+step) { if !usable(yy*size.width+xx) { complete = false } } }
                    if !complete { continue }
                    let a = y*size.width+x, b = a+step, c = (y+step)*size.width+x, d = c+step
                    for triangle in [[a,c,b], [b,c,d]] {
                        guard let p = projected[triangle[0]], let q = projected[triangle[1]], let r = projected[triangle[2]],
                              edgePass(p,q,r, limit: request.maximumEdgeMeters) else { continue }
                        let normal = (q-p).cross(r-p)
                        guard normal.length > 1e-10 else { continue }
                        localFaces.append(triangle)
                        for index in triangle { localNormals[index] = (localNormals[index] ?? .zero) + normal }
                    }
                }
            }
            guard !localFaces.isEmpty else { throw CaptureError.invalid("A selected frame has no connected valid surface under the mask and edge limits.") }
            var componentReport: SurfaceComponentReport?
            if let selection = item.componentSelection {
                let report = try SurfaceConnectedComponent.select(triangles:localFaces, selection:selection)
                let excluded = Set(report.excludedDepthPixelIndices)
                localFaces = localFaces.filter { !excluded.contains($0[0]) }
                localNormals = localNormals.filter { !excluded.contains($0.key) }
                componentReport = report
            }
            if let selection = item.registrationToReference {
                for pair in selection.fitPairs + selection.validationPairs {
                    guard !nearExcludedComponent(pair.source, frame:frame.metadata, step:step, report:componentReport),
                          !nearExcludedComponent(pair.target, frame:referenceFrame.metadata, step:step, report:evidences.first?.componentCleanup) else {
                        throw CaptureError.invalid("Component cleanup excludes a coarse sample at a registration landmark. Review correspondence and mask selection.")
                    }
                }
            }
            var mapping: [Int: Int] = [:]
            for pixel in localNormals.keys.sorted() {
                let point = projected[pixel]!, normal = localNormals[pixel]!.unit
                let cell = Cell(point, radius: request.fusionRadiusMeters)
                var match: Int?
                var closest = request.fusionRadiusMeters
                for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                    for index in cells[Cell(x: cell.x+dx, y: cell.y+dy, z: cell.z+dz)] ?? [] {
                        // Fuse observations across views; never collapse adjacent
                        // pixels of one view merely because their spacing is small.
                        if vertices[index].observations.contains(where: { $0.frameIndex == frameIndex }) { continue }
                        let distance = (anchors[index]-point).length
                        if distance <= closest && normal.dot(normalSums[index].unit) >= 0.85 {
                            closest = distance; match = index
                        }
                    }
                } } }
                let observation = SurfaceObservation(frameIndex: frameIndex, depthPixelIndex: pixel)
                if let index = match {
                    pointSums[index] = pointSums[index] + point
                    normalSums[index] = normalSums[index] + normal
                    vertices[index].observations.append(observation)
                    vertices[index].position = pointSums[index] / Double(vertices[index].observations.count)
                    vertices[index].normal = normalSums[index].unit
                    mapping[pixel] = index
                } else {
                    guard vertices.count < 250_000 else { throw CaptureError.invalid("Surface exceeds the 250,000-vertex processing budget. Reduce frames or increase sampling stride.") }
                    let index = vertices.count
                    vertices.append(SurfaceVertex(position: point, normal: normal, observations: [observation]))
                    anchors.append(point); pointSums.append(point); normalSums.append(normal)
                    cells[cell, default: []].append(index); mapping[pixel] = index
                }
            }
            for face in localFaces {
                let mapped = face.map { mapping[$0]! }
                if Set(mapped).count == 3, seenFaces.insert(mapped.sorted().map(String.init).joined(separator: ",")).inserted { faces.append(mapped) }
            }
            evidences.append(SurfaceFrameEvidence(captureID: item.captureID, frameID: item.frameID,
                frameSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(frame)),
                maskSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(item.mask)), source: manifest.source,
                referenceFromCamera: transform, registration: registration, retainedSamples: localNormals.count, skippedSamples: skipped,
                componentCleanup:componentReport))
        }
        // Averaging must not create collapsed or discontinuous output triangles.
        faces = faces.filter { f in
            let a = vertices[f[0]].position, b = vertices[f[1]].position, c = vertices[f[2]].position
            let normal = (b-a).cross(c-a)
            let expected = vertices[f[0]].normal + vertices[f[1]].normal + vertices[f[2]].normal
            return edgePass(a,b,c,limit: request.maximumEdgeMeters) && normal.length > 1e-10 && normal.dot(expected) > 0
        }
        guard !faces.isEmpty else { throw CaptureError.invalid("No valid surface survived fusion.") }
        let used = Set(faces.flatMap { $0 }).sorted()
        let remap = Dictionary(uniqueKeysWithValues: used.enumerated().map { ($0.element, $0.offset) })
        vertices = used.map { vertices[$0] }; faces = faces.map { $0.map { remap[$0]! } }
        return ObservedSurface(requestSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(request)), source: source,
            vertices: vertices, triangles: faces, frames: evidences,
            notes: ["Partial surface reconstructed from included depth measurements. Missing areas remain holes.",
                    "Mask semantics are supplied by the caller; hair/obstruction exclusion has not been verified automatically.",
                    "Contributor alignment passed landmark validation; dense surface-overlap refinement is not implemented.",
                    "Vertices are bounded-radius averages of recorded samples; they are not inferred scalp or a complete head."])
    }

    private static func bundleURL(_ id: String, root: URL) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw CaptureError.invalid("Capture ID must be a UUID.") }
        let url = root.appendingPathComponent(id).resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw CaptureError.invalid("Capture escapes the supplied root.") }
        return url
    }
    private static func included(_ pixel: PixelPoint, frame: FrameMetadata, mask: [Bool], size: PixelSize) -> Bool {
        guard frame.depthSize == size, pixel.x.isFinite, pixel.y.isFinite,
              pixel.x >= 0, pixel.y >= 0, pixel.x < Double(frame.imageSize.width), pixel.y < Double(frame.imageSize.height) else { return false }
        let x = min(size.width - 1, Int((pixel.x * Double(size.width) / Double(frame.imageSize.width)).rounded()))
        let y = min(size.height - 1, Int((pixel.y * Double(size.height) / Double(frame.imageSize.height)).rounded()))
        return mask[y * size.width + x]
    }
    private static func edgePass(_ a: Point3D, _ b: Point3D, _ c: Point3D, limit: Double) -> Bool {
        (a-b).length <= limit && (b-c).length <= limit && (c-a).length <= limit
    }
    private static func nearExcludedComponent(_ pixel: PixelPoint, frame: FrameMetadata, step: Int, report: SurfaceComponentReport?) -> Bool {
        guard let report, let size = frame.depthSize, !report.excludedDepthPixelIndices.isEmpty else { return false }
        let x = min((size.width-1)/step, Int((pixel.x*Double(size.width)/Double(frame.imageSize.width)/Double(step)).rounded()))*step
        let y = min((size.height-1)/step, Int((pixel.y*Double(size.height)/Double(frame.imageSize.height)/Double(step)).rounded()))*step
        return report.excludedDepthPixelIndices.contains(y*size.width+x)
    }
    private struct Cell: Hashable {
        var x: Int; var y: Int; var z: Int
        init(x: Int, y: Int, z: Int) { self.x=x; self.y=y; self.z=z }
        init(_ p: Point3D, radius: Double) { x=Int(floor(p.x/radius)); y=Int(floor(p.y/radius)); z=Int(floor(p.z/radius)) }
    }
    private struct Projection {
        var k: Intrinsics
        var size: PixelSize
        var lens: LensCalibration?
        func project(x: Int, y: Int, depth: Double) throws -> Point3D {
            var point = PixelPoint(x: Double(x)*Double(k.referenceSize.width)/Double(size.width),
                                   y: Double(y)*Double(k.referenceSize.height)/Double(size.height))
            if let lens { point = try LensGeometry.undistort(point, lens: lens, referenceSize: k.referenceSize) }
            return Point3D(x: (point.x-k.cx)*depth/k.fx, y: (point.y-k.cy)*depth/k.fy, z: depth)
        }
    }
    private static func prepare(_ frame: FrameMetadata) throws -> Projection {
        guard let k = frame.intrinsics, let size = frame.depthSize, !frame.mirrored, frame.pixelOrientation == "sensor_native" else {
            throw CaptureError.invalid("Surface projection requires native, unmirrored calibrated depth.")
        }
        var lens: LensCalibration?
        switch frame.depthRectification {
        case "arkit_aligned_scene_depth", "synthetic_pinhole": break
        case "not_applied":
            guard let calibration = frame.lensCalibration else { throw CaptureError.invalid("Surface has no required lens calibration.") }
            _ = try LensGeometry.undistort(PixelPoint(x: 0,y: 0), lens: calibration, referenceSize: k.referenceSize)
            lens = calibration
        default: throw CaptureError.invalid("Unknown rectification convention.")
        }
        return Projection(k: k, size: size, lens: lens)
    }
}

extension Point3D {
    func dot(_ b: Self) -> Double { x*b.x + y*b.y + z*b.z }
    var unit: Self { length > 1e-15 ? self / length : .zero }
}
