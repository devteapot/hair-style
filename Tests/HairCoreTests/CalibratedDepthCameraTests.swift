import XCTest
@testable import HairCore

final class CalibratedDepthCameraTests: XCTestCase {
    private func frame(table: [Float] = [0.1,0.1,0.1]) -> FrameMetadata {
        var frame = FrameMetadata(imageTimestamp: 1, depthTimestamp: 1, imageSize: PixelSize(640,480),
            depthSize: PixelSize(320,240), intrinsics: Intrinsics(fx: 500, fy: 500, cx: 320, cy: 240, referenceSize: PixelSize(640,480)),
            depthRectification: "not_applied")
        frame.lensCalibration = LensCalibration(centerX: 310, centerY: 230, lookupTable: nil, inverseLookupTable: table,
            extrinsicRowMajor: [1,0,0,0,0,1,0,0,0,0,1,0], pixelSizeMillimeters: 0.001)
        return frame
    }
    func testRawProjectionMatchesIndependentConstantRadialMap() throws {
        let frame = frame(), camera = try CalibratedDepthCamera(frame: frame)
        let pixel = PixelPoint(x: 240,y: 80), depth = 0.4
        let m = 1+Double(Float(0.1))
        let rectifiedX = 310+(480-310)*m, rectifiedY = 230+(160-230)*m
        let expected = Point3D(x: (rectifiedX-320)*depth/500,y: (rectifiedY-240)*depth/500,z: depth)
        let point = try camera.point(pixel: pixel, depth: depth)
        XCTAssertLessThan((point-expected).length,1e-12)
        let projected = try XCTUnwrap(camera.pixel(point: expected))
        XCTAssertEqual(projected.x,pixel.x,accuracy:1e-7); XCTAssertEqual(projected.y,pixel.y,accuracy:1e-7)
    }
    func testNonlinearMapRoundTripsCornersAndInteriorAtNativeDepthResolution() throws {
        let camera = try CalibratedDepthCamera(frame: frame(table: [0,-0.015,-0.025,-0.012]))
        for x in [0.0,12.3,155,278.2,319] { for y in [0.0,25.5,115,238.9] {
            let input = PixelPoint(x:x,y:y), p = try camera.point(pixel:input,depth:0.3)
            let output = try XCTUnwrap(camera.pixel(point:p))
            XCTAssertEqual(output.x,x,accuracy:1e-7); XCTAssertEqual(output.y,y,accuracy:1e-7)
        } }
        XCTAssertNil(camera.pixel(point:Point3D(x:0,y:0,z:-1)))
        XCTAssertNil(camera.pixel(point:Point3D(x:100,y:0,z:0.2)))
    }
    func testRejectsFoldedLensMissingCalibrationAndTiming() throws {
        XCTAssertThrowsError(try CalibratedDepthCamera(frame:frame(table:[0,-0.8,-0.8])))
        var bad = frame();bad.lensCalibration = nil
        XCTAssertThrowsError(try CalibratedDepthCamera(frame:bad))
        bad = frame();bad.depthTimestamp = 0.8
        XCTAssertThrowsError(try CalibratedDepthCamera(frame:bad))
        bad = frame();bad.mirrored = true
        XCTAssertThrowsError(try CalibratedDepthCamera(frame:bad))
    }
}
