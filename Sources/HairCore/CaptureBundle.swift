import Foundation
import CryptoKit

public enum EvidenceHash {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum EvidenceIO {
    static func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

/// Call on one serialized capture queue. Commits frame payloads before the manifest.
public final class CaptureBundleWriter {
    public let url: URL
    public private(set) var manifest: CaptureManifest

    public init(root: URL, subjectSessionID: String, kind: CaptureKind, source: CaptureSource,
                device: DeviceReport, consentVersion: String, sampleRateHz: Double = 3,
                declaredHairCondition: HairCaptureCondition? = nil) throws {
        guard !consentVersion.isEmpty, sampleRateHz > 0, sampleRateHz.isFinite else {
            throw CaptureError.invalid("Consent version and a valid sample rate are required.")
        }
        let now = Date()
        let id = UUID().uuidString
        url = root.appendingPathComponent(id, isDirectory: true)
        manifest = CaptureManifest(id: id, subjectSessionID: subjectSessionID, kind: kind, source: source,
            status: .recording, createdAt: now, updatedAt: now, consentVersion: consentVersion,
            device: device, requestedSampleRateHz: sampleRateHz, frames: [], notes: [],
            declaredHairCondition: declaredHairCondition)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("frames"), withIntermediateDirectories: true)
        try checkpoint()
    }

    public func append(metadata: FrameMetadata, imageJPEG: Data, depth: Data? = nil, confidence: Data? = nil) throws {
        guard manifest.status == .recording else { throw CaptureError.invalid("Capture is already closed.") }
        try CaptureBundle.validate(metadata)
        guard UUID(uuidString: metadata.id) != nil, !manifest.frames.contains(where: { $0.metadata.id == metadata.id }) else {
            throw CaptureError.invalid("Frame ID must be a unique UUID.")
        }
        guard !imageJPEG.isEmpty else { throw CaptureError.invalid("Image payload is empty.") }
        if let size = metadata.depthSize {
            guard let depth, depth.count == size.width * size.height * 4 else { throw CaptureError.invalid("Depth payload is missing or has the wrong size.") }
            if let confidence, confidence.count != size.width * size.height { throw CaptureError.invalid("Confidence payload has the wrong size.") }
        } else if depth != nil || confidence != nil { throw CaptureError.invalid("Unexpected depth payload.") }

        let framePath = "frames/\(metadata.id)"
        let destination = url.appendingPathComponent(framePath, isDirectory: true)
        let temporary = url.appendingPathComponent(".pending-\(metadata.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        func write(_ data: Data, name: String) throws -> FileEvidence {
            try EvidenceIO.write(data, to: temporary.appendingPathComponent(name))
            return FileEvidence(path: "\(framePath)/\(name)", byteCount: data.count, sha256: EvidenceHash.sha256(data))
        }
        let stored = StoredFrame(metadata: metadata, image: try write(imageJPEG, name: "image.jpg"),
            depth: try depth.map { try write($0, name: "depth.f32") },
            confidence: try confidence.map { try write($0, name: "confidence.u8") })
        try EvidenceIO.write(ManifestCoding.encoder().encode(stored), to: temporary.appendingPathComponent("frame.json"))
        try FileManager.default.moveItem(at: temporary, to: destination)
        manifest.frames.append(stored)
        manifest.updatedAt = Date()
        do { try checkpoint() }
        catch {
            manifest.frames.removeLast()
            // The committed frame remains recoverable through frame.json. It is not yet indexed.
            throw error
        }
    }

    public func finish(interrupted: Bool = false, note: String? = nil) throws {
        manifest.status = interrupted || manifest.frames.isEmpty ? .interrupted : .completed
        manifest.updatedAt = Date()
        if let note { manifest.notes.append(note) }
        try checkpoint()
    }

    private func checkpoint() throws {
        try EvidenceIO.write(ManifestCoding.encoder().encode(manifest), to: url.appendingPathComponent("manifest.json"))
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
        var mutableURL = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}

public struct BundleReport: Codable, Sendable {
    public var captureID: String
    public var source: CaptureSource
    public var frameCount: Int
    public var depthFrameCount: Int
    public var errors: [String]
    public var warnings: [String]
    public var valid: Bool { errors.isEmpty }
}

public enum CaptureBundle {
    public static func load(_ url: URL) throws -> CaptureManifest {
        let data = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let manifest = try ManifestCoding.decoder().decode(CaptureManifest.self, from: data)
        guard manifest.schemaVersion == 1 else { throw CaptureError.invalid("Unsupported capture schema version.") }
        return manifest
    }

    public static func validate(_ m: FrameMetadata) throws {
        guard m.imageSize.isValid, m.imageTimestamp.isFinite, m.imageTimestamp >= 0 else { throw CaptureError.invalid("Invalid image dimensions or timestamp.") }
        if let t = m.depthTimestamp, !t.isFinite || t < 0 { throw CaptureError.invalid("Invalid depth timestamp.") }
        if let size = m.depthSize {
            guard size.isValid, m.intrinsics?.isValid == true, m.depthTimestamp != nil,
                  m.depthEncoding == "float32_little_endian_meters" else { throw CaptureError.invalid("Depth frame needs valid dimensions, calibration, timestamp and encoding.") }
        }
        if let transform = m.worldFromOpticalCamera, !transform.isValid { throw CaptureError.invalid("Invalid camera pose.") }
        if let fraction = m.quality.validDepthFraction, !fraction.isFinite || !(0...1).contains(fraction) {
            throw CaptureError.invalid("Invalid valid-depth fraction.")
        }
        guard m.quality.headPoseAvailable == (m.headPose != nil) else {
            throw CaptureError.invalid("Head-pose availability must match its recorded evidence.")
        }
        if let pose=m.headPose {
            guard pose.headFromOpticalCamera.isValid,pose.timestamp.isFinite,pose.timestamp>=0,
                  abs(pose.timestamp-m.imageTimestamp)<=0.01,UUID(uuidString:pose.anchorID) != nil,
                  pose.source=="arkit_face_tracking" else {
                throw CaptureError.invalid("Invalid head-pose transform, timing, anchor or source.")
            }
            if let depthTimestamp = m.depthTimestamp, abs(pose.timestamp - depthTimestamp) > 0.01 {
                throw CaptureError.invalid("Head pose and depth must be captured within 10 ms.")
            }
        }
    }

    public static func payload(_ evidence: FileEvidence, in root: URL) throws -> Data {
        let components = evidence.path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3, components[0] == "frames", UUID(uuidString: String(components[1])) != nil,
              ["image.jpg", "depth.f32", "confidence.u8"].contains(String(components[2])) else {
            throw CaptureError.invalid("Invalid evidence path.")
        }
        let file = root.appendingPathComponent(evidence.path).resolvingSymlinksInPath()
        let base = root.resolvingSymlinksInPath().path + "/"
        guard file.path.hasPrefix(base), evidence.byteCount > 0, evidence.byteCount <= 300_000_000 else {
            throw CaptureError.invalid("Evidence path escapes the bundle or size is invalid.")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard (attributes[.size] as? NSNumber)?.intValue == evidence.byteCount else { throw CaptureError.invalid("Evidence size mismatch: \(evidence.path)") }
        // Return owned bytes. A read-only mapping can crash a caller that edits Data,
        // and an externally truncated mapped file can fault during replay.
        let data = try Data(contentsOf: file)
        guard EvidenceHash.sha256(data) == evidence.sha256 else { throw CaptureError.invalid("Evidence checksum mismatch: \(evidence.path)") }
        return data
    }

    public static func inspect(_ root: URL) throws -> BundleReport {
        let manifest = try load(root)
        var report = BundleReport(captureID: manifest.id, source: manifest.source, frameCount: manifest.frames.count,
                                  depthFrameCount: 0, errors: [], warnings: [])
        if manifest.source == .syntheticFixture { report.warnings.append("Synthetic fixture: not sensor or human validation evidence.") }
        if manifest.status != .completed { report.warnings.append("Capture is incomplete (\(manifest.status.rawValue)); review before processing.") }
        if manifest.frames.isEmpty { report.errors.append("Capture contains no frames.") }
        var ids = Set<String>()
        var lastTime: Double = -1
        for frame in manifest.frames {
            do {
                let m = frame.metadata
                try validate(m)
                guard ids.insert(m.id).inserted else { throw CaptureError.invalid("Duplicate frame ID.") }
                guard m.imageTimestamp > lastTime else { throw CaptureError.invalid("Image timestamps must increase within a pass.") }
                lastTime = m.imageTimestamp
                guard frame.image.path == "frames/\(m.id)/image.jpg" else { throw CaptureError.invalid("Image belongs to a different frame.") }
                _ = try payload(frame.image, in: root)
                if let size = m.depthSize {
                    guard let evidence = frame.depth, evidence.path == "frames/\(m.id)/depth.f32" else { throw CaptureError.invalid("Depth payload missing or bound to a different frame.") }
                    _ = try DepthGeometry.decode(payload(evidence, in: root), size: size)
                    report.depthFrameCount += 1
                    if let confidence = frame.confidence {
                        guard confidence.path == "frames/\(m.id)/confidence.u8", try payload(confidence, in: root).count == size.width * size.height else {
                            throw CaptureError.invalid("Confidence payload mismatch.")
                        }
                    }
                } else if frame.depth != nil || frame.confidence != nil { throw CaptureError.invalid("Unspecified depth payload.") }
            } catch { report.errors.append("\(frame.metadata.id): \(error.localizedDescription)") }
        }
        if manifest.frames.contains(where: { $0.metadata.lensCalibration != nil && $0.metadata.depthRectification == "not_applied" }) {
            report.warnings.append("Lens calibration is preserved; pinhole replay is approximate until distortion correction is applied.")
        }
        if manifest.frames.contains(where: { !$0.metadata.quality.headPoseAvailable }) {
            report.warnings.append("Head-relative poses are unavailable. Do not fuse frames as a stationary head.")
        }
        let committed = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("frames").path)) ?? []
        let orphanCount = committed.filter { UUID(uuidString: $0) != nil && !ids.contains($0) }.count
        if orphanCount > 0 {
            report.warnings.append("\(orphanCount) committed frame(s) are absent from the manifest. Preserve the original folder for recovery; normal export includes only indexed frames.")
        }
        return report
    }
}
