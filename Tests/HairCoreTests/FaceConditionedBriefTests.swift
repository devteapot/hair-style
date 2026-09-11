import XCTest
@testable import HairCore

final class FaceConditionedBriefTests: XCTestCase {
    private func fixture(chinHeight: Double = 0.10) throws -> (HairDesignInput,ScalpReviewDocument) {
        let seed=try SyntheticHaircut.create();var input=seed.0
        let points=[Point3D(x:0.032,y:0,z:0),Point3D(x:-0.032,y:0,z:0),Point3D(x:0,y:0.05,z:0),
                    Point3D(x:0,y:-0.015,z:0.025),Point3D(x:0,y:-chinHeight,z:0)]
        let vertices=points.enumerated().map { SurfaceVertex(position:$0.element,normal:Point3D(x:0,y:0,z:1),observations:[SurfaceObservation(frameIndex:0,depthPixelIndex:$0.offset)]) }
        let frame=SurfaceFrameEvidence(captureID:UUID().uuidString,frameID:UUID().uuidString,frameSHA256:String(repeating:"a",count:64),maskSHA256:String(repeating:"b",count:64),source:.syntheticFixture,referenceFromCamera:.identity,registration:nil,retainedSamples:5,skippedSamples:0)
        let surface=ObservedSurface(requestSHA256:String(repeating:"c",count:64),source:.syntheticFixture,vertices:vertices,triangles:[[0,1,2],[0,3,1],[0,4,3],[1,3,4]],frames:[frame],notes:["Synthetic ratio test"])
        let selection=AnatomicalSelection(surfaceSHA256:try HairArtifactHash.digest(surface),anatomicalLeftEyeVertex:0,anatomicalRightEyeVertex:1,superiorVertex:2,anteriorVertex:3,method:"Synthetic feature identities")
        let envelope=try ScalpCompletion.suggestedEnvelope(surface:surface,selection:selection)
        let request=ScalpCompletionRequest(selection:selection,subjectSessionID:input.scalp.subjectSessionID,scalpID:UUID().uuidString,revision:1,envelope:envelope)
        let review=ScalpReviewDocument(source:surface,revisions:[request]);input.scalp=try review.latestResult().scalp
        input.brief.scalpSHA256=try HairArtifactHash.digest(input.scalp)
        return (input,review)
    }
    func testPersonalPolicyChangesRegionalCapWithoutChangingFittedHeadOrOtherRegions() throws {
        let (input,review)=try fixture()
        let personal=try FaceConditionedBrief.compile(input:input,review:review,request:.init(chinVertex:4,mode:.personal))
        let generic=try FaceConditionedBrief.compile(input:input,review:review,request:.init(chinVertex:4,mode:.genericAblation))
        XCTAssertEqual(personal.constrainedFringeLengthMeters,0.05,accuracy:1e-9)
        XCTAssertEqual(generic.constrainedFringeLengthMeters,0.04,accuracy:1e-9)
        XCTAssertEqual(try HairArtifactHash.digest(personal.input.scalp),try HairArtifactHash.digest(generic.input.scalp))
        XCTAssertEqual(try HairArtifactHash.digest(personal.input.hairProfile),try HairArtifactHash.digest(input.hairProfile))
        for before in input.brief.lengthLimits where before.region != .fringe {
            let after=personal.input.brief.lengthLimits.first { $0.region==before.region }!
            XCTAssertEqual(before.maximumMeters,after.maximumMeters)
        }
        XCTAssertFalse(personal.aestheticQualityVerified);XCTAssertFalse(personal.physicalFeasibilityVerified)
    }
    func testCurrentLengthAndGuidedRangeStillTakePrecedence() throws {
        var (input,review)=try fixture()
        let i=input.brief.lengthLimits.firstIndex { $0.region == .fringe }!
        input.brief.mode = .guided
        input.brief.lengthLimits[i].minimumMeters=0.015;input.brief.lengthLimits[i].maximumMeters=0.02
        input.brief.lengthLimits[i].origin = .userSupplied
        let result=try FaceConditionedBrief.compile(input:input,review:review,request:.init(chinVertex:4,mode:.personal))
        XCTAssertEqual(result.constrainedFringeLengthMeters,0.02)
        XCTAssertEqual(result.input.brief.lengthLimits[i].origin,.userSupplied)
    }
    func testRejectsMismatchedScalpAndInvalidChin() throws {
        var (input,review)=try fixture()
        XCTAssertThrowsError(try FaceConditionedBrief.compile(input:input,review:review,request:.init(chinVertex:2,mode:.personal)))
        input.scalp.id="different"
        XCTAssertThrowsError(try FaceConditionedBrief.compile(input:input,review:review,request:.init(chinVertex:4,mode:.personal)))
    }
}
