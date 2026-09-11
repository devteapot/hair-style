import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Exercises serialization and coordinate handling, never substitutes for a sensor capture.
public enum SyntheticCapture {
    public static func create(in root: URL, kind: CaptureKind = .rearHead) throws -> URL {
        let report = DeviceReport(model: "asymmetric-synthetic-fixture", osVersion: "fixture-v1", build: "1",
            hasTrueDepth: false, hasRearSceneDepth: false, hasFaceTracking: false, isSimulator: true)
        let writer = try CaptureBundleWriter(root: root, subjectSessionID: "synthetic-calibration",
            kind: kind, source: .syntheticFixture, device: report, consentVersion: "synthetic-no-subject")
        let size = PixelSize(64, 48)
        let k = Intrinsics(fx: 60, fy: 60, cx: 31.5, cy: 23.5, referenceSize: size)
        for index in 0..<3 {
            var depth = [Float](repeating: 0.5, count: size.width * size.height)
            var pixels = [UInt8](repeating: 255, count: size.width * size.height * 4)
            for y in 0..<size.height {
                for x in 0..<size.width {
                    let offset = y * size.width + x
                    let raised = x < 22 && y < 18
                    depth[offset] = raised ? 0.42 : 0.5
                    if x == 0 { depth[offset] = .nan }
                    pixels[offset * 4] = raised ? 224 : 32
                    pixels[offset * 4 + 1] = raised ? 78 : 155
                    pixels[offset * 4 + 2] = raised ? 45 : 150
                }
            }
            let jpeg = try jpeg(pixels, size: size)
            let q = DepthGeometry.quality(depth)
            var pose = RigidTransform.identity
            pose.rowMajor[3] = Double(index) * 0.01
            let metadata = FrameMetadata(imageTimestamp: Double(index + 1), depthTimestamp: Double(index + 1),
                imageSize: size, depthSize: size, intrinsics: k, depthFiltered: false,
                depthRectification: "synthetic_pinhole", worldFromOpticalCamera: kind == .rearHead ? pose : nil,
                poseSource: kind == .rearHead ? "synthetic_camera_to_fixture" : "unavailable",
                quality: FrameQuality(validDepthFraction: q.fraction, medianDepthMeters: q.median,
                    synchronizationDeltaSeconds: 0, trackingState: "synthetic",
                    notes: ["Plane with an off-center raised patch; not a face."]))
            try writer.append(metadata: metadata, imageJPEG: jpeg, depth: DepthGeometry.encode(depth),
                              confidence: Data(repeating: 2, count: depth.count))
        }
        try writer.finish(note: "Generated for format and projection tests. No physical accuracy evidence.")
        return writer.url
    }

    private static func jpeg(_ rgba: [UInt8], size: PixelSize) throws -> Data {
        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: size.width, height: size.height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: size.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                  decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw CaptureError.invalid("Could not create fixture image.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CaptureError.invalid("Could not create JPEG encoder.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.invalid("JPEG encoding failed.") }
        return output as Data
    }
}
