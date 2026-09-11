import Foundation
import AVFoundation
import ARKit
import UIKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import HairCore

enum DeviceCapabilities {
    static func report() -> DeviceReport {
        var system = utsname(); uname(&system)
        let model = withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let front = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
        let hasDepth = front?.formats.contains { !$0.supportedDepthDataFormats.isEmpty } ?? false
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return DeviceReport(model: model, osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            hasTrueDepth: hasDepth, hasRearSceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            hasFaceTracking: ARFaceTrackingConfiguration.isSupported, isSimulator: simulator)
    }
}

enum CameraEvidence {
    static func imageJPEG(_ pixelBuffer: CVPixelBuffer, context: CIContext, exif: [String:Any] = [:]) throws -> Data {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw CaptureError.invalid("Image conversion failed.")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CaptureError.invalid("Image encoder unavailable.")
        }
        CGImageDestinationAddImage(destination, cgImage, CaptureImageMetadata.jpegProperties(exif:exif) as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.invalid("Image encoding failed.") }
        return data as Data
    }

    static func depth(_ buffer: CVPixelBuffer) throws -> (Data, FrameQuality) {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32 else {
            throw CaptureError.invalid("Expected float32 depth in meters.")
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw CaptureError.invalid("Depth buffer unavailable.") }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var values = [Float](); values.reserveCapacity(width * height)
        for row in 0..<height {
            let start = base.advanced(by: row * stride).assumingMemoryBound(to: Float.self)
            values.append(contentsOf: UnsafeBufferPointer(start: start, count: width))
        }
        let quality = DepthGeometry.quality(values)
        return (DepthGeometry.encode(values), FrameQuality(validDepthFraction: quality.fraction, medianDepthMeters: quality.median))
    }

    static func confidence(_ buffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var data = Data()
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            data.append(base.advanced(by: row * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self), count: CVPixelBufferGetWidth(buffer))
        }
        return data
    }

    static func size(_ buffer: CVPixelBuffer) -> PixelSize {
        PixelSize(CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer))
    }

    static func intrinsics(_ matrix: simd_float3x3, referenceSize: PixelSize) -> Intrinsics {
        Intrinsics(fx: Double(matrix[0,0]), fy: Double(matrix[1,1]), cx: Double(matrix[2,0]), cy: Double(matrix[2,1]), referenceSize: referenceSize)
    }

    static func worldFromOptical(_ arCamera: simd_float4x4) -> RigidTransform {
        // ARKit camera: x right, y up, -z forward. Optical: x right, y down, +z forward.
        let opticalToAR = simd_float4x4(diagonal: SIMD4<Float>(1, -1, -1, 1))
        let matrix = arCamera * opticalToAR
        return RigidTransform(rowMajor: (0..<4).flatMap { row in (0..<4).map { Double(matrix[$0, row]) } })
    }

    static func lens(_ calibration: AVCameraCalibrationData) -> LensCalibration {
        func floats(_ data: Data?) -> [Float]? {
            data.map { bytes in bytes.withUnsafeBytes { raw in
                (0..<(raw.count / 4)).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
            } }
        }
        let extrinsic = calibration.extrinsicMatrix
        return LensCalibration(centerX: calibration.lensDistortionCenter.x, centerY: calibration.lensDistortionCenter.y,
            lookupTable: floats(calibration.lensDistortionLookupTable), inverseLookupTable: floats(calibration.inverseLensDistortionLookupTable),
            extrinsicRowMajor: (0..<3).flatMap { row in (0..<4).map { Double(extrinsic[$0, row]) } },
            pixelSizeMillimeters: Double(calibration.pixelSize))
    }
}
