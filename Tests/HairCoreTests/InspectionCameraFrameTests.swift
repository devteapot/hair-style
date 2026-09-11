import XCTest
@testable import HairCore

final class InspectionCameraFrameTests: XCTestCase {
    func testEveryCornerFitsWideAndTallViewports() throws {
        let points = [-0.1,0.1].flatMap { x in [-0.15,0.15].flatMap { y in [-0.06,0.06].map { z in Point3D(x:x,y:y,z:z) } } }
        let frame = try InspectionCameraFrame(points: points)
        let right = Point3D(x:0,y:1,z:0).cross(frame.towardCamera).unit
        let up = frame.towardCamera.cross(right).unit
        for (w,h) in [(400.0,320.0),(200.0,500.0),(800.0,200.0)] {
            let scale = try frame.scale(viewportWidth:w,viewportHeight:h)
            var maximum = 0.0
            for point in points {
                let delta = point-frame.target
                let x = abs(delta.dot(right))/(scale*w/h), y = abs(delta.dot(up))/scale
                maximum = max(maximum,max(x,y))
                XCTAssertLessThanOrEqual(x,0.850000001); XCTAssertLessThanOrEqual(y,0.850000001)
            }
            XCTAssertEqual(maximum,0.85,accuracy:1e-10)
        }
        let shift = Point3D(x:2,y:-3,z:4)
        let shifted = try InspectionCameraFrame(points:points.map { $0+shift })
        XCTAssertLessThan((shifted.target-frame.target-shift).length,1e-12)
        XCTAssertEqual(shifted.halfWidth,frame.halfWidth,accuracy:1e-12)
    }

    func testDegenerateGeometryAndInvalidViewport() throws {
        let single = try InspectionCameraFrame(points:[Point3D(x:0,y:0,z:0)])
        XCTAssertEqual(try single.scale(viewportWidth:100,viewportHeight:100),0.001)
        XCTAssertThrowsError(try single.scale(viewportWidth:0,viewportHeight:100))
        XCTAssertThrowsError(try single.scale(viewportWidth:100,viewportHeight:.nan))
        XCTAssertThrowsError(try InspectionCameraFrame(points:[]))
        XCTAssertThrowsError(try InspectionCameraFrame(points:[Point3D(x:.infinity,y:0,z:0)]))
    }
}
