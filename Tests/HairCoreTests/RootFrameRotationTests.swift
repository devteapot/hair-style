import XCTest
@testable import HairCore

final class RootFrameRotationTests: XCTestCase {
    func testKnownRotationPreservesShapeLengthAndExactAttachment() throws {
        let envelope = ScalpEnvelope(center: Point3D(x: 0,y: 0,z: 0), radii: Point3D(x: 0.1,y: 0.1,z: 0.1),
            frontBoundaryY: 0,sideBoundaryY: 0,backBoundaryY: 0,origin: .defaultValue,method: "test")
        let points = [Point3D(x: 0.1,y: 0,z: 0),Point3D(x: 0.11,y: 0.01,z: 0),Point3D(x: 0.12,y: 0.03,z: 0.01)]
        let target = Point3D(x: 0,y: 0.1,z: 0)
        let result = try RootFrameRotation.attach(points: points,to: target,envelope: envelope,maximumAngle: .pi/2)
        XCTAssertEqual(result.angle, .pi/2, accuracy: 1e-12)
        for (source, actual) in zip(points,result.points) {
            XCTAssertEqual(actual.x, -source.y, accuracy: 1e-12)
            XCTAssertEqual(actual.y, source.x, accuracy: 1e-12)
            XCTAssertEqual(actual.z, source.z, accuracy: 1e-12)
        }
        XCTAssertEqual(try HaircutValidator.arcLength(points), try HaircutValidator.arcLength(result.points), accuracy: 1e-12)
        XCTAssertThrowsError(try RootFrameRotation.attach(points: points,to: target,envelope: envelope,maximumAngle: .pi/4))
        XCTAssertThrowsError(try RootFrameRotation.attach(points: points,to: envelope.center,envelope: envelope,maximumAngle: .pi/2))
    }
}
