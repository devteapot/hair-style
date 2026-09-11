import XCTest
@testable import HairCore

final class RegistrationTests: XCTestCase {
    private let fit = [
        Point3D(x: -0.06, y: 0.02, z: 0.5), Point3D(x: 0.04, y: 0.03, z: 0.51),
        Point3D(x: -0.02, y: -0.07, z: 0.48), Point3D(x: 0.01, y: -0.01, z: 0.45),
        Point3D(x: -0.08, y: -0.03, z: 0.53), Point3D(x: 0.07, y: -0.04, z: 0.52)
    ]
    private let heldOut = [
        Point3D(x: -0.035, y: 0.045, z: 0.52), Point3D(x: 0.035, y: 0.046, z: 0.525),
        Point3D(x: 0.003, y: -0.09, z: 0.505), Point3D(x: 0.026, y: -0.032, z: 0.465)
    ]
    private func input(transform: RigidTransform = .identity) -> RegistrationInput {
        RegistrationInput(sourceFrameID: "front", targetFrameID: "rear", evidenceSource: .syntheticFixture,
            fitPairs: fit.enumerated().map { LandmarkPair(id: "fit-\($0.offset)", source: $0.element, target: transform.apply($0.element)) },
            validationPairs: heldOut.enumerated().map { LandmarkPair(id: "validation-\($0.offset)", source: $0.element, target: transform.apply($0.element)) })
    }

    func testKnownRotationTranslationAndOppositeRotation() throws {
        for angle in [0.0, 0.73, Double.pi, -2.1] {
            let c = cos(angle), s = sin(angle)
            let expected = RigidTransform(rowMajor: [c,0,s,0.2, 0,1,0,-0.1, -s,0,c,0.06, 0,0,0,1])
            let report = try RigidRegistration.register(input(transform: expected))
            XCTAssertTrue(report.accepted)
            XCTAssertTrue(report.targetFromSource.isValid)
            for (actual, value) in zip(report.targetFromSource.rowMajor, expected.rowMajor) { XCTAssertEqual(actual, value, accuracy: 1e-9) }
            XCTAssertLessThan(report.validationP95Meters, 1e-9)
        }
    }

    func testOutlierRejectedWithoutPullingTransform() throws {
        var request = input()
        request.fitPairs[3].target = Point3D(x: 0.3, y: 0.1, z: 0.7)
        let report = try RigidRegistration.register(request)
        XCTAssertTrue(report.accepted)
        XCTAssertEqual(report.outlierIDs, ["fit-3"])
        XCTAssertLessThan(report.validationP95Meters, 1e-9)
    }

    func testHeldOutDisagreementDoesNotChangeFitAndFailsGate() throws {
        var request = input()
        request.validationPairs[0].target.x += 0.025
        let report = try RigidRegistration.register(request)
        XCTAssertFalse(report.accepted)
        XCTAssertGreaterThan(report.validationP95Meters, 0.02)
        for (actual, expected) in zip(report.targetFromSource.rowMajor, RigidTransform.identity.rowMajor) { XCTAssertEqual(actual, expected, accuracy: 1e-9) }
    }

    func testScaleMismatchNotHiddenByRescaling() throws {
        var request = input()
        for i in request.fitPairs.indices { request.fitPairs[i].target = Point3D(x: fit[i].x * 2, y: fit[i].y * 2, z: fit[i].z * 2) }
        XCTAssertThrowsError(try RigidRegistration.register(request))
    }

    func testValidationLeakageAndDegenerateInputRejected() throws {
        var request = input()
        request.validationPairs[0] = request.fitPairs[0]
        XCTAssertThrowsError(try RigidRegistration.register(request))
        request.validationPairs[0].id = "new-name-same-data"
        XCTAssertThrowsError(try RigidRegistration.register(request))
        request = input()
        for i in request.fitPairs.indices {
            let p = Point3D(x: Double(i) * 0.01, y: 0, z: 0.5)
            request.fitPairs[i].source = p; request.fitPairs[i].target = p
        }
        XCTAssertThrowsError(try RigidRegistration.register(request))
        request = input(); request.fitPairs[0].source.z = .nan
        XCTAssertThrowsError(try RigidRegistration.register(request))
        request = input(); request.fitPairs[1].source = request.fitPairs[0].source
        XCTAssertThrowsError(try RigidRegistration.register(request))
    }

    func testNoisyDataAndLargeDeterministicSampleSet() throws {
        var request = input()
        request.fitPairs = (0..<30).map { i in
            let p = Point3D(x: sin(Double(i))*0.07, y: cos(Double(i)*0.4)*0.08, z: 0.5+sin(Double(i)*0.7)*0.025)
            return LandmarkPair(id: "dense-\(i)", source: p,
                target: Point3D(x: p.x + sin(Double(i))*0.0002, y: p.y, z: p.z))
        }
        let a = try RigidRegistration.register(request), b = try RigidRegistration.register(request)
        XCTAssertTrue(a.accepted)
        XCTAssertLessThan(a.validationP95Meters, 0.001)
        XCTAssertEqual(a.targetFromSource, b.targetFromSource)
        XCTAssertEqual(a.inputSHA256, b.inputSHA256)
    }
}
