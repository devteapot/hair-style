import XCTest
@testable import HairCore

final class FaceLandmarkTests: XCTestCase {
    func testUprightNormalizationMapsBackToNativeSensorForAllQuarterTurns() throws {
        // Native point (30,20) in a non-square 200x100 image. Derive its upright
        // lower-left normalized coordinates independently for each rotation.
        let cases: [(ImageQuarterTurn,PixelPoint)] = [(.none,PixelPoint(x:0.15,y:0.8)),
            (.clockwise90,PixelPoint(x:0.8,y:0.85)), (.clockwise180,PixelPoint(x:0.85,y:0.2)),
            (.clockwise270,PixelPoint(x:0.2,y:0.15))]
        for (rotation,normalized) in cases {
            let result = try LandmarkCoordinates.nativePixel(normalized, size: PixelSize(200,100), rotation: rotation)
            XCTAssertEqual(result.x,30,accuracy:1e-10); XCTAssertEqual(result.y,20,accuracy:1e-10)
        }
        XCTAssertThrowsError(try LandmarkCoordinates.nativePixel(PixelPoint(x: -0.1,y:0), size: PixelSize(200,100), rotation: .none))
        XCTAssertThrowsError(try LandmarkCoordinates.nativePixel(PixelPoint(x: .nan,y:0), size: PixelSize(200,100), rotation: .none))
    }

    func testVisionRunsOnVerifiedSyntheticImageAndDoesNotInventAFace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try SyntheticCapture.create(in: root)
        let manifest = try CaptureBundle.load(bundle)
        let report = try FaceLandmarkExtractor.extract(bundle: bundle, frameID: manifest.frames[0].metadata.id, rotation: .none)
        XCTAssertEqual(report.status,.noFace); XCTAssertEqual(report.faceCount,0); XCTAssertTrue(report.points.isEmpty)
        XCTAssertEqual(report.source,.syntheticFixture)
        XCTAssertEqual(report.frameSHA256,try HairArtifactHash.digest(manifest.frames[0]))
        XCTAssertEqual(report.rotationToUpright,.none)
        XCTAssertThrowsError(try FaceLandmarkExtractor.extract(bundle: bundle, frameID: "missing", rotation: .none))
    }
}
