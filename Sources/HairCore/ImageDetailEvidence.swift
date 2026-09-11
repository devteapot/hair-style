import Foundation
import CoreImage
import CoreGraphics

/// An image-content diagnostic, not a calibrated blur detector or scan acceptance gate.
/// Samples the centered square spanning 60% of the shorter image dimension at 128².
/// Statistics use sRGB-encoded RGB luma (0.2126 R + 0.7152 G + 0.0722 B), in 0...1.
public struct ImageDetailEvidence: Codable, Sendable {
    public var method: String = "center60_srgb128_laplacian4_v1"
    public var meanLuma: Double
    public var lumaStandardDeviation: Double
    public var laplacianVariance: Double

    public var isValid: Bool {
        method == "center60_srgb128_laplacian4_v1" &&
        meanLuma.isFinite && (0...1).contains(meanLuma) &&
        lumaStandardDeviation.isFinite && (0...0.500001).contains(lumaStandardDeviation) &&
        laplacianVariance.isFinite && (0...16).contains(laplacianVariance)
    }

    public static func measure(image: CIImage, context: CIContext) throws -> Self {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isNull, extent.width.isFinite, extent.height.isFinite,
              extent.width >= 128, extent.height >= 128 else {
            throw CaptureError.invalid("Image detail needs a finite image at least 128 pixels across.")
        }
        let side = min(extent.width, extent.height) * 0.6
        let crop = CGRect(x: extent.midX - side/2, y: extent.midY - side/2, width: side, height: side)
        let sample = image.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: 128/side, y: 128/side))
        var rgba = [UInt8](repeating: 0, count: 128 * 128 * 4)
        rgba.withUnsafeMutableBytes { bytes in
            context.render(sample, toBitmap: bytes.baseAddress!, rowBytes: 128 * 4,
                           bounds: CGRect(x: 0, y: 0, width: 128, height: 128), format: .RGBA8,
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        let luma = stride(from: 0, to: rgba.count, by: 4).map {
            (0.2126 * Double(rgba[$0]) + 0.7152 * Double(rgba[$0+1]) + 0.0722 * Double(rgba[$0+2])) / 255
        }
        return try statistics(luma)
    }

    /// Fixed sample dimensions keep the diagnostic comparable within this method.
    static func statistics(_ luma: [Double]) throws -> Self {
        guard luma.count == 128 * 128, luma.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw CaptureError.invalid("Image detail requires 128 × 128 normalized luma samples.")
        }
        let mean = luma.reduce(0, +) / Double(luma.count)
        let variance = luma.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(luma.count)
        var sum = 0.0, sumSquares = 0.0
        for y in 1..<127 {
            for x in 1..<127 {
                let i = y * 128 + x
                let value = luma[i-1] + luma[i+1] + luma[i-128] + luma[i+128] - 4 * luma[i]
                sum += value; sumSquares += value * value
            }
        }
        let count = Double(126 * 126)
        return Self(meanLuma: mean, lumaStandardDeviation: sqrt(variance),
                    laplacianVariance: max(0, sumSquares/count - (sum/count) * (sum/count)))
    }
}
