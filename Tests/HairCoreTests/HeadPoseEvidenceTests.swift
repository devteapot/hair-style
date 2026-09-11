import XCTest
@testable import HairCore

final class HeadPoseEvidenceTests:XCTestCase {
    func testPoseClaimsRequireTimedIdentifiedEvidenceAndRoundTrip() throws {
        var frame=FrameMetadata(imageTimestamp:1,imageSize:PixelSize(640,480))
        try CaptureBundle.validate(frame)
        frame.quality.headPoseAvailable=true
        XCTAssertThrowsError(try CaptureBundle.validate(frame))
        frame.headPose=HeadPoseEvidence(headFromOpticalCamera:.identity,timestamp:1,anchorID:UUID().uuidString)
        try CaptureBundle.validate(frame)
        let replay=try ManifestCoding.decoder().decode(FrameMetadata.self,from:ManifestCoding.encoder().encode(frame))
        XCTAssertEqual(replay.headPose?.anchorID,frame.headPose?.anchorID)
        try CaptureBundle.validate(replay)
        frame.depthTimestamp = 0.98
        XCTAssertThrowsError(try CaptureBundle.validate(frame))
        frame.depthTimestamp = 0.995
        try CaptureBundle.validate(frame)
        frame.depthTimestamp = nil
        frame.headPose?.timestamp=1.1
        XCTAssertThrowsError(try CaptureBundle.validate(frame))
        frame.headPose?.timestamp=1;frame.headPose?.source="measured_skull"
        XCTAssertThrowsError(try CaptureBundle.validate(frame))
        frame.headPose?.source="arkit_face_tracking";frame.headPose?.anchorID="unknown"
        XCTAssertThrowsError(try CaptureBundle.validate(frame))
    }
}
