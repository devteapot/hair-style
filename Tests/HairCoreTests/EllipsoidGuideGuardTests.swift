import XCTest
@testable import HairCore

final class EllipsoidGuideGuardTests: XCTestCase {
    private func fixture(_ points: [Point3D]) throws -> (ScalpProfile, HairGuide, EllipsoidGuideGuardRequest) {
        let scalp=ScalpProfile(id:UUID().uuidString,revision:1,subjectSessionID:"synthetic-envelope",
            vertices:[Point3D(x:0,y:0.1,z:0),Point3D(x:0.1,y:0,z:0),Point3D(x:0,y:0,z:0.1)],
            triangles:[[0,2,1]],triangleOrigins:[.synthetic],sourceSHA256:[String(repeating:"a",count:64)],method:"synthetic sphere vertices")
        let guide=HairGuide(id:"guard",region:.top,materialID:"test",root:ScalpBinding(triangleIndex:0,barycentric:[1,0,0],normalOffsetMeters:0),points:points)
        let envelope=ScalpEnvelope(center:Point3D(x:0,y:0,z:0),radii:Point3D(x:0.1,y:0.1,z:0.1),
            frontBoundaryY:0,sideBoundaryY:0,backBoundaryY:0,origin:.defaultValue,method:"synthetic test sphere")
        let request=EllipsoidGuideGuardRequest(scalpSHA256:try HairArtifactHash.digest(scalp),envelope:envelope,
            permittedInsetMeters:0.0005,maximumPointCorrectionMeters:0.002)
        return (scalp,guide,request)
    }

    func testDetectsBetweenVertexPenetrationAndPreservesRoot() throws {
        let (scalp,guide,request)=try fixture([Point3D(x:0,y:0.1,z:0),Point3D(x:-0.01,y:0.0994,z:0),
            Point3D(x:0.01,y:0.0994,z:0),Point3D(x:0.02,y:0.11,z:0)])
        XCTAssertTrue(guide.points.allSatisfy({$0.length>=0.0995}))
        let result=try EllipsoidGuideGuard.apply(guides:[guide],scalp:scalp,request:request)
        XCTAssertLessThan(result.report.minimumNormalizedRadiusBefore,0.995)
        XCTAssertGreaterThanOrEqual(result.report.minimumNormalizedRadiusAfter,0.995-1e-12)
        XCTAssertEqual(result.report.changedGuideIDs,["guard"])
        XCTAssertLessThan(result.report.maximumPointCorrectionMeters,0.002)
        XCTAssertEqual(try HairArtifactHash.digest(result.guides[0].root),try HairArtifactHash.digest(guide.root))
        XCTAssertEqual(result.guides[0].points[0].x,guide.points[0].x)
        XCTAssertEqual(result.guides[0].points[0].y,guide.points[0].y)
        XCTAssertEqual(result.guides[0].points[0].z,guide.points[0].z)
        XCTAssertFalse(result.report.physicalClearanceVerified)
        // Independent dense samples supplement the analytical result.
        for index in 1..<result.guides[0].points.count {
            let a=result.guides[0].points[index-1],b=result.guides[0].points[index]
            for sample in 0...1000 { XCTAssertGreaterThanOrEqual((a+(b-a)*Double(sample)/1000).length,0.0995-1e-12) }
        }
    }

    func testExteriorCurveIsBitwiseUnchanged() throws {
        let (scalp,guide,request)=try fixture([Point3D(x:0,y:0.1,z:0),Point3D(x:0.01,y:0.12,z:0)])
        let result=try EllipsoidGuideGuard.apply(guides:[guide],scalp:scalp,request:request)
        XCTAssertEqual(try HairArtifactHash.digest(result.guides[0]),try HairArtifactHash.digest(guide))
        XCTAssertEqual(result.report.changedPointCount,0)
    }

    func testBriefBindsGuardAndEditsCannotReintroducePenetration() throws {
        let north=Point3D(x:0,y:0.1,z:0),end=Point3D(x:0.06,y:0.075,z:-0.035)
        var points=[north]
        for index in 0...20 {
            let p=north+(end-north)*Double(index)/20
            points.append(p.unit*0.105)
        }
        let (scalp,guide,request)=try fixture(points)
        let profile=HairLengthProfile(id:UUID().uuidString,revision:1,subjectSessionID:scalp.subjectSessionID,regions:[])
        let brief=HairDesignBrief(id:UUID().uuidString,scalpSHA256:try HairArtifactHash.digest(scalp),
            hairProfileSHA256:try HairArtifactHash.digest(profile),mode:.autonomous,
            lengthLimits:[RegionalLengthLimit(region:.top,minimumMeters:0.001,maximumMeters:0.3,origin:.defaultValue)],
            allowGrowth:false,stylingAssumptions:[],seed:42,envelopeGuard:request)
        let input=HairDesignInput(scalp:scalp,hairProfile:profile,brief:brief)
        let haircut=HaircutRevision(id:UUID().uuidString,revision:1,scalpSHA256:brief.scalpSHA256,hairProfileSHA256:brief.hairProfileSHA256,
            briefSHA256:try HairArtifactHash.digest(brief),generation:HairGenerationRecord(origin:.syntheticFixture,method:"guarded fixture",version:"1",seed:42),
            materials:[HairMaterial(id:"test",linearRGB:[0.1,0.1,0.1],roughness:0.5,radiusMeters:0.00005)],guides:[guide])
        let validation=try HaircutValidator.validate(input:input,haircut:haircut)
        XCTAssertTrue(validation.checksCompleted.contains("continuous_inferred_envelope_centerline"))
        XCTAssertThrowsError(try HaircutEditor.apply(HairEdit(baseSHA256:validation.haircutSHA256,operation:.scaleLateralVolume,region:.top,value:0.5),to:haircut,input:input))
        let trimmed=try HaircutEditor.apply(HairEdit(baseSHA256:validation.haircutSHA256,operation:.shortenToLength,region:.top,value:0.02),to:haircut,input:input)
        XCTAssertEqual(trimmed.haircut.briefSHA256,haircut.briefSHA256)
        var altered=input;altered.brief.envelopeGuard?.permittedInsetMeters=0.001
        XCTAssertThrowsError(try HaircutValidator.validate(input:altered,haircut:haircut))
    }

    func testRejectsExcessiveCorrectionStaleOrDifferentEnvelopeAndRootMovement() throws {
        let (scalp,guide,initial)=try fixture([Point3D(x:0,y:0.1,z:0),Point3D(x:0,y:0.02,z:0)])
        XCTAssertThrowsError(try EllipsoidGuideGuard.apply(guides:[guide],scalp:scalp,request:initial))
        var request=initial;request.scalpSHA256=String(repeating:"b",count:64)
        XCTAssertThrowsError(try EllipsoidGuideGuard.apply(guides:[guide],scalp:scalp,request:request))
        request=initial;request.envelope.center.x=0.001
        XCTAssertThrowsError(try EllipsoidGuideGuard.apply(guides:[guide],scalp:scalp,request:request))
        request=initial;request.envelope.origin = .observed
        XCTAssertThrowsError(try EllipsoidGuideGuard.apply(guides:[guide],scalp:scalp,request:request))
        var detached=guide;detached.points[0].y=0.09
        XCTAssertThrowsError(try EllipsoidGuideGuard.apply(guides:[detached],scalp:scalp,request:initial))
    }
}
