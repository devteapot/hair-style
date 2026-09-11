import XCTest
@testable import HairCore

final class CalibratedLandmarkTests: XCTestCase {
    private func lens() -> LensCalibration {
        LensCalibration(centerX: 40, centerY: 30, lookupTable: [-0.1,-0.1], inverseLookupTable: [0.1,0.1],
                        extrinsicRowMajor: [1,0,0,0, 0,1,0,0, 0,0,1,0], pixelSizeMillimeters: 0.001)
    }

    func testUsesInverseTableForSensorToRectilinearPointAndDistortionCenter() throws {
        let result = try LensGeometry.undistort(PixelPoint(x: 50, y: 40), lens: lens(), referenceSize: PixelSize(100,80))
        XCTAssertEqual(result.x, 51, accuracy: 1e-7)
        XCTAssertEqual(result.y, 41, accuracy: 1e-7)
        let center = try LensGeometry.undistort(PixelPoint(x: 40, y: 30), lens: lens(), referenceSize: PixelSize(100,80))
        XCTAssertEqual(center.x, 40); XCTAssertEqual(center.y, 30)
        var invalid = lens(); invalid.inverseLookupTable = nil
        XCTAssertThrowsError(try LensGeometry.undistort(PixelPoint(x: 50, y: 40), lens: invalid, referenceSize: PixelSize(100,80)))
        var varying = lens(); varying.inverseLookupTable = [0,0.1,0.2]
        let interpolated = try LensGeometry.undistort(PixelPoint(x: 70,y: 30), lens: varying, referenceSize: PixelSize(100,80))
        XCTAssertEqual(interpolated.x, 40 + 30 * (1 + 0.2 * 30 / hypot(60,50)), accuracy: 1e-6)
        let corner = try LensGeometry.undistort(PixelPoint(x: 100,y: 80), lens: varying, referenceSize: PixelSize(100,80))
        XCTAssertEqual(corner.x, 112, accuracy: 1e-6)
    }

    func testImageRayScalingCorrectionAndDepthConfidence() throws {
        let frame = FrameMetadata(imageTimestamp: 1, depthTimestamp: 1, imageSize: PixelSize(200,160),
            depthSize: PixelSize(10,8), intrinsics: Intrinsics(fx: 100, fy: 100, cx: 50, cy: 40, referenceSize: PixelSize(100,80)),
            lensCalibration: lens())
        let values = [Float](repeating: 0.5, count: 80)
        let p = try CalibratedLandmarks.sample(PixelPoint(x: 100,y: 80), frame: frame, values: values)
        XCTAssertEqual(p.x, 0.005, accuracy: 1e-8)
        XCTAssertEqual(p.y, 0.005, accuracy: 1e-8)
        XCTAssertEqual(p.z, 0.5)
        XCTAssertThrowsError(try CalibratedLandmarks.sample(PixelPoint(x: 100,y: 80), frame: frame, values: values, confidence: Data(repeating: 0, count: 80)))
        XCTAssertThrowsError(try CalibratedLandmarks.sample(PixelPoint(x: -1,y: 80), frame: frame, values: values))
        var mirrored = frame; mirrored.mirrored = true
        XCTAssertThrowsError(try CalibratedLandmarks.sample(PixelPoint(x: 100,y: 80), frame: mirrored, values: values))
    }

    func testCapturedBundleRegistrationBindsEvidenceAndRejectsMissingDepth() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let front = try SyntheticCapture.create(in: root, kind: .frontFace)
        let rear = try SyntheticCapture.create(in: root, kind: .rearHead)
        let a = try CaptureBundle.load(front), b = try CaptureBundle.load(rear)
        func pair(_ x: Double, _ y: Double, _ id: String) -> PixelLandmarkPair {
            PixelLandmarkPair(id: id, source: PixelPoint(x: x,y: y), target: PixelPoint(x: x,y: y))
        }
        var selection = CaptureLandmarkSelection(sourceFrameID: a.frames[0].metadata.id, targetFrameID: b.frames[0].metadata.id,
            fitPairs: [pair(10,10,"a"), pair(40,10,"b"), pair(10,35,"c"), pair(40,35,"d")],
            validationPairs: [pair(15,12,"e"), pair(50,12,"f"), pair(30,40,"g")])
        let report = try CalibratedLandmarks.register(sourceBundle: front, targetBundle: rear, selection: selection)
        XCTAssertTrue(report.registration.accepted)
        XCTAssertEqual(report.registration.evidenceSource, .syntheticFixture)
        XCTAssertEqual(report.sourceFrameSHA256.count, 64)
        XCTAssertNotEqual(report.sourceFrameSHA256, report.targetFrameSHA256)
        selection.fitPairs[0].source.x = 0 // fixture's left edge deliberately contains NaN
        XCTAssertThrowsError(try CalibratedLandmarks.register(sourceBundle: front, targetBundle: rear, selection: selection))
    }
}
