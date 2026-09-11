import XCTest
import CoreImage
@testable import HairCore

final class ImageDetailTests: XCTestCase {
    func testSyntheticBlurReducesDetailWithoutChangingMean() throws {
        let sharp = (0..<(128*128)).map { ($0 % 128) < 64 ? 0.0 : 1.0 }
        let blurred = (0..<(128*128)).map { min(1.0, max(0.0, Double(($0 % 128) - 56) / 16)) }
        let a = try ImageDetailEvidence.statistics(sharp)
        let b = try ImageDetailEvidence.statistics(blurred)
        XCTAssertGreaterThan(a.laplacianVariance, b.laplacianVariance * 100)
        XCTAssertEqual(a.meanLuma, b.meanLuma, accuracy: 0.005)
        let rotated = (0..<(128*128)).map { ($0 / 128) < 64 ? 0.0 : 1.0 }
        XCTAssertEqual(a.laplacianVariance, try ImageDetailEvidence.statistics(rotated).laplacianVariance, accuracy: 1e-12)
        let flat = try ImageDetailEvidence.statistics(Array(repeating: 0.25, count: 128*128))
        XCTAssertEqual(flat.laplacianVariance, 0)
        XCTAssertEqual(flat.lumaStandardDeviation, 0)
        XCTAssertEqual(flat.meanLuma, 0.25)
        XCTAssertTrue(flat.isValid) // Textureless content is not an invalid capture.
    }

    func testCameraSamplingUsesCenterCropAndExplicitSRGB() throws {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let black = CIImage(color: .black).cropped(to: CGRect(x: 40, y: 20, width: 640, height: 512))
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 200, y: 116, width: 320, height: 320))
        let sample = try ImageDetailEvidence.measure(image: gray.composited(over: black), context: context)
        XCTAssertEqual(sample.meanLuma, 0.5, accuracy: 0.005)
        XCTAssertEqual(sample.lumaStandardDeviation, 0, accuracy: 1e-6)
        XCTAssertEqual(sample.laplacianVariance, 0, accuracy: 1e-6)
        XCTAssertThrowsError(try ImageDetailEvidence.measure(image: CIImage(color: .black), context: context))
    }

    func testCompatibilityAndValidation() throws {
        let old = FrameMetadata(imageTimestamp: 1, imageSize: PixelSize(640, 480))
        let encoded = try ManifestCoding.encoder().encode(old)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("imageDetail"))
        var frame = try ManifestCoding.decoder().decode(FrameMetadata.self, from: encoded)
        XCTAssertNil(frame.quality.imageDetail)
        frame.quality.imageDetail = try ImageDetailEvidence.statistics(Array(repeating: 0, count: 128*128))
        let restored = try ManifestCoding.decoder().decode(FrameMetadata.self, from: ManifestCoding.encoder().encode(frame))
        XCTAssertEqual(restored.quality.imageDetail?.method, "center60_srgb128_laplacian4_v1")
        try CaptureBundle.validate(restored)
        frame.quality.imageDetail?.laplacianVariance = -1
        XCTAssertThrowsError(try CaptureBundle.validate(frame))
        frame.quality.imageDetail?.laplacianVariance = .nan
        XCTAssertThrowsError(try CaptureBundle.validate(frame))
        frame.quality.imageDetail = restored.quality.imageDetail
        frame.quality.imageDetail?.method = "claimed_blur_accuracy"
        XCTAssertThrowsError(try CaptureBundle.validate(frame))
        XCTAssertThrowsError(try ImageDetailEvidence.statistics([0]))
        XCTAssertThrowsError(try ImageDetailEvidence.statistics(Array(repeating: .nan, count: 128*128)))
    }
}
