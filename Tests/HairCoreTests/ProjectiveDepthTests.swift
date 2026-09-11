import XCTest
@testable import HairCore

final class ProjectiveDepthTests: XCTestCase {
    private var frame: FrameMetadata {
        FrameMetadata(id:"target",imageTimestamp:1,depthTimestamp:1,imageSize:PixelSize(8,4),
            depthSize:PixelSize(4,2),intrinsics:Intrinsics(fx:2,fy:2,cx:0,cy:0,referenceSize:PixelSize(8,4)),
            depthRectification:"synthetic_pinhole")
    }
    private var request: ProjectiveDepthRequest {
        .init(frameID:"target",mask:SurfaceMask(size:PixelSize(4,2),provenance:.syntheticFixture,
            method:"test mask",includedRuns:[MaskRun(start:0,count:3),MaskRun(start:4,count:4)]),cameraFromSurface:.identity)
    }
    func testAccountsForAllSamplesAndPreservesSignedDisagreements() throws {
        let points = [Point3D(x:0,y:0,z:-1), Point3D(x:3,y:0,z:0.5),
            Point3D(x:1.5,y:0,z:0.5), Point3D(x:0,y:0.5,z:0.5),
            Point3D(x:0.5,y:0,z:0.5), Point3D(x:0,y:0,z:0.5),
            Point3D(x:0,y:0,z:0.52), Point3D(x:0,y:0,z:0.48)]
        let r = try ProjectiveDepthAgreement.evaluate(points:points,frame:frame,
            depth:[0.5,0.5,0.5,0.5,.nan,0.5,0.5,0.5],confidence:Data([2,0,2,2,2,2,2,2]),request:request)
        XCTAssertEqual(r.map(\.state),[.behindCamera,.outsideImage,.outsideMask,.missingDepth,
            .lowConfidence,.consistent,.behindObservedSurface,.inFrontOfObservedSurface])
        XCTAssertEqual(r[6].signedDifferenceMeters!,0.02,accuracy:1e-9)
        XCTAssertEqual(r[7].signedDifferenceMeters!,-0.02,accuracy:1e-9)
        XCTAssertEqual(r[4].targetDepthPixelIndex,1) // Intrinsics scaled from RGB to depth.
        XCTAssertNotNil(r[4].signedDifferenceMeters)
    }
    func testTransformDirectionAndUnsafeCalibrationRejection() throws {
        var req = request
        req.cameraFromSurface = RigidTransform(rowMajor:[1,0,0,0,0,1,0,0,0,0,1,0.5,0,0,0,1])
        let p = [Point3D(x:0,y:0,z:0)]
        let d = [Float](repeating:0.5,count:8)
        XCTAssertEqual(try ProjectiveDepthAgreement.evaluate(points:p,frame:frame,depth:d,confidence:nil,request:req)[0].state,.consistent)
        var f = frame; f.depthTimestamp = 0.9
        XCTAssertThrowsError(try ProjectiveDepthAgreement.evaluate(points:p,frame:f,depth:d,confidence:nil,request:req))
        f = frame; f.depthRectification = "raw_distorted"
        XCTAssertThrowsError(try ProjectiveDepthAgreement.evaluate(points:p,frame:f,depth:d,confidence:nil,request:req))
        req.cameraFromSurface.rowMajor[11] = Double.greatestFiniteMagnitude
        XCTAssertThrowsError(try ProjectiveDepthAgreement.evaluate(points:p,frame:frame,depth:d,confidence:nil,request:req))
    }
}
