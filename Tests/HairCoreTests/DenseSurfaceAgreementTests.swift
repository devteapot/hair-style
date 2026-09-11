import XCTest
@testable import HairCore

final class DenseSurfaceAgreementTests: XCTestCase {
    private func surface(_ points: [Point3D], source: Bool, normal: Point3D = Point3D(x:0,y:0,z:-1)) -> ObservedSurface {
        let frame = SurfaceFrameEvidence(captureID:source ? "a" : "b",frameID:source ? "s" : "t",
            frameSHA256:String(repeating:source ? "a" : "b",count:64),maskSHA256:String(repeating:"c",count:64),source:.syntheticFixture,
            referenceFromCamera:.identity,registration:nil,retainedSamples:points.count,skippedSamples:0)
        return ObservedSurface(requestSHA256:String(repeating:"d",count:64),source:.syntheticFixture,
            vertices:points.enumerated().map { i,p in SurfaceVertex(position:p,normal:normal,observations:[SurfaceObservation(frameIndex:0,depthPixelIndex:i)]) },
            triangles:[],frames:[frame],notes:[])
    }
    private func registration() throws -> CapturedRegistrationReport {
        let points = [Point3D(x:0,y:0,z:0),Point3D(x:0.03,y:0,z:0),Point3D(x:0,y:0.03,z:0),Point3D(x:0.03,y:0.03,z:0),
                      Point3D(x:0.01,y:0.01,z:0),Point3D(x:0.02,y:0.01,z:0),Point3D(x:0.01,y:0.02,z:0)]
        let pairs = points.enumerated().map { i,p in LandmarkPair(id:"\(i)",source:p,target:p) }
        let r = try RigidRegistration.register(RegistrationInput(sourceFrameID:"a/s",targetFrameID:"b/t",evidenceSource:.syntheticFixture,
            fitPairs:Array(pairs.prefix(4)),validationPairs:Array(pairs.suffix(3))))
        return CapturedRegistrationReport(sourceFrameSHA256:String(repeating:"a",count:64),targetFrameSHA256:String(repeating:"b",count:64),
            selectionSHA256:String(repeating:"e",count:64),minimumConfidence:1,sourceLensCorrection:false,targetLensCorrection:false,registration:r)
    }
    func testReportsUnmatchedCoverageInBothDirectionsWithoutTrimming() throws {
        let points = [Point3D(x:0,y:0,z:0.2),Point3D(x:0.01,y:0,z:0.2),Point3D(x:0.02,y:0,z:0.2)]
        let result = try DenseSurfaceAgreement.compare(source:surface(points,source:true),
            target:surface(points+[Point3D(x:0.12,y:0,z:0.2)],source:false),registration:registration())
        XCTAssertEqual(result.sourceToTarget.maximumMeters,0,accuracy:1e-12)
        XCTAssertEqual(result.targetToSource.maximumMeters,0.1,accuracy:1e-12)
        XCTAssertEqual(result.targetToSource.p95Meters,0.1,accuracy:1e-12)
        XCTAssertEqual(result.targetToSource.fractionWithin3mm,0.75)
        XCTAssertEqual(result.targetToSource.residuals.count,4)
    }
    func testNearestSearchMatchesBruteForceAndPreservesResidualSigns() throws {
        let points: [Point3D] = (0..<80).map { i in
            let x = Double((i*17)%79)*0.001
            let y = Double((i*31)%83)*0.001
            let z = 0.2+Double(i%7)*0.001
            return Point3D(x:x,y:y,z:z)
        }
        let target = points.map { $0 + Point3D(x:0.0003,y:0.0002,z:0.002) }
        let result = try DenseSurfaceAgreement.compare(source:surface(points,source:true),target:surface(target,source:false),registration:registration())
        for r in result.sourceToTarget.residuals {
            let expected = target.map { ($0-points[r.sampleIndex]).length }.min()!
            XCTAssertEqual(r.distanceMeters,expected,accuracy:1e-12)
            XCTAssertEqual(r.signedPlaneDistanceMeters,target[r.nearestIndex].z-points[r.sampleIndex].z,accuracy:1e-12)
        }
    }
    func testTransformsNormalsAsDirectionsAndRejectsMismatchedEvidence() throws {
        let points = [Point3D(x:0,y:0,z:0.2),Point3D(x:0.01,y:0,z:0.2),Point3D(x:0.02,y:0.01,z:0.2)]
        var r = try registration()
        r.registration.targetFromSource = RigidTransform(rowMajor:[0,0,1,0.03, 0,1,0,0.02, -1,0,0,0.01, 0,0,0,1])
        let moved = points.map { r.registration.targetFromSource.apply($0) }
        let source = surface(points,source:true), target = surface(moved,source:false,normal:Point3D(x:-1,y:0,z:0))
        let result = try DenseSurfaceAgreement.compare(source:source,target:target,registration:r)
        XCTAssertEqual(result.sourceToTarget.maximumMeters,0,accuracy:1e-12)
        XCTAssertTrue(result.sourceToTarget.residuals.allSatisfy { abs($0.normalDot-1)<1e-12 })
        r.sourceFrameSHA256 = "wrong"
        XCTAssertThrowsError(try DenseSurfaceAgreement.compare(source:source,target:target,registration:r))
    }
}
