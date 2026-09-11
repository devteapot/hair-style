import Foundation

public enum CaptureKind: String, Codable, CaseIterable, Sendable {
    case frontFace = "front_face"
    case rearHead = "rear_head"
    case naturalHair = "natural_hair"
    case detail
}

public enum CaptureSource: String, Codable, Sendable {
    case sensor
    case syntheticFixture = "synthetic_fixture"
}

public enum CaptureStatus: String, Codable, Sendable {
    case recording, completed, interrupted
}

public struct PixelSize: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public init(_ width: Int, _ height: Int) { self.width = width; self.height = height }
    public var isValid: Bool { width > 0 && height > 0 && width <= 8192 && height <= 8192 }
}

public struct Intrinsics: Codable, Equatable, Sendable {
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double
    public var referenceSize: PixelSize
    public init(fx: Double, fy: Double, cx: Double, cy: Double, referenceSize: PixelSize) {
        self.fx = fx; self.fy = fy; self.cx = cx; self.cy = cy; self.referenceSize = referenceSize
    }
    public func scaled(to size: PixelSize) -> Intrinsics {
        let sx = Double(size.width) / Double(referenceSize.width)
        let sy = Double(size.height) / Double(referenceSize.height)
        return Intrinsics(fx: fx * sx, fy: fy * sy, cx: cx * sx, cy: cy * sy, referenceSize: size)
    }
    public var isValid: Bool {
        referenceSize.isValid && [fx, fy, cx, cy].allSatisfy(\.isFinite) && fx > 0 && fy > 0
    }
}

/// A rigid transform stored row-major. Translation is in meters.
public struct RigidTransform: Codable, Equatable, Sendable {
    public var rowMajor: [Double]
    public init(rowMajor: [Double]) { self.rowMajor = rowMajor }
    public static let identity = RigidTransform(rowMajor: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1])
    public var isValid: Bool {
        guard rowMajor.count == 16, rowMajor.allSatisfy(\.isFinite) else { return false }
        let m = rowMajor
        guard abs(m[12]) < 1e-6, abs(m[13]) < 1e-6, abs(m[14]) < 1e-6, abs(m[15] - 1) < 1e-6 else { return false }
        for i in 0..<3 {
            for j in 0..<3 {
                let dot = (0..<3).reduce(0.0) { $0 + m[i * 4 + $1] * m[j * 4 + $1] }
                if abs(dot - (i == j ? 1 : 0)) > 1e-3 { return false }
            }
        }
        let determinant = m[0] * (m[5]*m[10] - m[6]*m[9]) - m[1] * (m[4]*m[10] - m[6]*m[8]) + m[2] * (m[4]*m[9] - m[5]*m[8])
        return abs(determinant - 1) < 1e-3
    }
    public func apply(_ p: Point3D) -> Point3D {
        let m = rowMajor
        return Point3D(x: m[0]*p.x + m[1]*p.y + m[2]*p.z + m[3],
                       y: m[4]*p.x + m[5]*p.y + m[6]*p.z + m[7],
                       z: m[8]*p.x + m[9]*p.y + m[10]*p.z + m[11])
    }
}

public struct Point3D: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
}

public struct LensCalibration: Codable, Sendable {
    public var centerX: Double
    public var centerY: Double
    public var lookupTable: [Float]?
    public var inverseLookupTable: [Float]?
    public var extrinsicRowMajor: [Double]
    public var pixelSizeMillimeters: Double
    public init(centerX: Double, centerY: Double, lookupTable: [Float]?, inverseLookupTable: [Float]?,
                extrinsicRowMajor: [Double], pixelSizeMillimeters: Double) {
        self.centerX = centerX; self.centerY = centerY; self.lookupTable = lookupTable
        self.inverseLookupTable = inverseLookupTable; self.extrinsicRowMajor = extrinsicRowMajor
        self.pixelSizeMillimeters = pixelSizeMillimeters
    }
}

public struct DeviceReport: Codable, Sendable {
    public var model: String
    public var osVersion: String
    public var build: String
    public var hasTrueDepth: Bool
    public var hasRearSceneDepth: Bool
    public var hasFaceTracking: Bool
    public var isSimulator: Bool
    public var eligible: Bool { hasTrueDepth && hasRearSceneDepth && hasFaceTracking && !isSimulator }
    public init(model: String, osVersion: String, build: String, hasTrueDepth: Bool,
                hasRearSceneDepth: Bool, hasFaceTracking: Bool, isSimulator: Bool) {
        self.model = model; self.osVersion = osVersion; self.build = build
        self.hasTrueDepth = hasTrueDepth; self.hasRearSceneDepth = hasRearSceneDepth
        self.hasFaceTracking = hasFaceTracking; self.isSimulator = isSimulator
    }
}

public struct FrameQuality: Codable, Sendable {
    public var validDepthFraction: Double?
    public var medianDepthMeters: Double?
    public var synchronizationDeltaSeconds: Double?
    public var trackingState: String
    public var headPoseAvailable: Bool
    public var notes: [String]
    public init(validDepthFraction: Double? = nil, medianDepthMeters: Double? = nil,
                synchronizationDeltaSeconds: Double? = nil, trackingState: String = "unavailable",
                headPoseAvailable: Bool = false, notes: [String] = []) {
        self.validDepthFraction = validDepthFraction; self.medianDepthMeters = medianDepthMeters
        self.synchronizationDeltaSeconds = synchronizationDeltaSeconds; self.trackingState = trackingState
        self.headPoseAvailable = headPoseAvailable; self.notes = notes
    }
}

/// Tracker estimate, distinct from measured depth and from world-camera tracking.
public struct HeadPoseEvidence: Codable, Sendable {
    public var headFromOpticalCamera: RigidTransform
    public var timestamp: Double
    public var anchorID: String
    public var source: String
    public init(headFromOpticalCamera: RigidTransform, timestamp: Double, anchorID: String,
                source: String = "arkit_face_tracking") {
        self.headFromOpticalCamera=headFromOpticalCamera;self.timestamp=timestamp
        self.anchorID=anchorID;self.source=source
    }
}

public struct FrameMetadata: Codable, Sendable {
    public var id: String
    public var imageTimestamp: Double
    public var depthTimestamp: Double?
    public var imageSize: PixelSize
    public var depthSize: PixelSize?
    public var intrinsics: Intrinsics?
    public var lensCalibration: LensCalibration?
    /// Source buffer convention, independent of UI/device orientation.
    public var pixelOrientation: String
    public var mirrored: Bool
    public var depthEncoding: String?
    public var depthFiltered: Bool?
    public var depthRectification: String
    public var sourceImagePixelFormat: UInt32?
    public var sourceDepthPixelFormat: UInt32?
    public var nominalCameraFrameRate: Double?
    public var worldFromOpticalCamera: RigidTransform?
    public var poseSource: String
    public var quality: FrameQuality
    public var headPose: HeadPoseEvidence? = nil

    public init(id: String = UUID().uuidString, imageTimestamp: Double, depthTimestamp: Double? = nil,
                imageSize: PixelSize, depthSize: PixelSize? = nil, intrinsics: Intrinsics? = nil,
                lensCalibration: LensCalibration? = nil, pixelOrientation: String = "sensor_native",
                mirrored: Bool = false, depthFiltered: Bool? = nil,
                depthRectification: String = "not_applied", worldFromOpticalCamera: RigidTransform? = nil,
                poseSource: String = "unavailable", quality: FrameQuality = FrameQuality()) {
        self.id = id; self.imageTimestamp = imageTimestamp; self.depthTimestamp = depthTimestamp
        self.imageSize = imageSize; self.depthSize = depthSize; self.intrinsics = intrinsics
        self.lensCalibration = lensCalibration; self.pixelOrientation = pixelOrientation; self.mirrored = mirrored
        self.depthEncoding = depthSize == nil ? nil : "float32_little_endian_meters"
        self.depthFiltered = depthFiltered; self.depthRectification = depthRectification
        self.sourceImagePixelFormat = nil; self.sourceDepthPixelFormat = nil; self.nominalCameraFrameRate = nil
        self.worldFromOpticalCamera = worldFromOpticalCamera; self.poseSource = poseSource; self.quality = quality
    }
}

public struct FileEvidence: Codable, Sendable {
    public var path: String
    public var byteCount: Int
    public var sha256: String
    public init(path: String, byteCount: Int, sha256: String) {
        self.path = path; self.byteCount = byteCount; self.sha256 = sha256
    }
}

public struct StoredFrame: Codable, Sendable {
    public var metadata: FrameMetadata
    public var image: FileEvidence
    public var depth: FileEvidence?
    public var confidence: FileEvidence?
}

public struct CaptureManifest: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var id: String
    public var subjectSessionID: String
    public var kind: CaptureKind
    public var source: CaptureSource
    public var status: CaptureStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var consentVersion: String
    public var device: DeviceReport
    public var coordinateConvention: String = "optical_camera_x_right_y_down_z_forward_meters"
    public var requestedSampleRateHz: Double
    public var frames: [StoredFrame]
    public var notes: [String]
}

public enum CaptureError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public enum ManifestCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
}
