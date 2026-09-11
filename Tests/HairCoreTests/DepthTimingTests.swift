import XCTest
@testable import HairCore

final class DepthTimingTests: XCTestCase {
    func testGeometryRequiresSourceTimestampAgreementDespiteQualityClaim() throws {
        var frame = FrameMetadata(imageTimestamp: 1, depthTimestamp: 1, imageSize: PixelSize(2,2),
            depthSize: PixelSize(2,2), intrinsics: Intrinsics(fx: 2,fy: 2,cx: 0,cy: 0,referenceSize: PixelSize(2,2)),
            quality: FrameQuality(synchronizationDeltaSeconds: 0))
        frame.depthRectification = "synthetic_pinhole"
        let point = PixelPoint(x: 1,y: 1), values: [Float] = [0.5,0.5,0.5,0.5]
        _ = try CalibratedLandmarks.sample(point, frame: frame, values: values)
        frame.depthTimestamp = 1 - 1.0/15
        XCTAssertThrowsError(try CalibratedLandmarks.sample(point, frame: frame, values: values))
        frame.depthTimestamp = nil
        XCTAssertThrowsError(try CalibratedLandmarks.requireSynchronizedDepth(frame))
        frame.depthTimestamp = 1.005
        XCTAssertNoThrow(try CalibratedLandmarks.requireSynchronizedDepth(frame))
    }
}
