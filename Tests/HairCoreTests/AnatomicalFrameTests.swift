import XCTest
@testable import HairCore

final class AnatomicalFrameTests: XCTestCase {
    private func fixture() throws -> (ObservedSurface, AnatomicalSelection, [Point3D]) {
        let points = [Point3D(x: 0.03,y: 0,z: 0), Point3D(x: -0.03,y: 0,z: 0),
                      Point3D(x: 0.008,y: 0.05,z: 0), Point3D(x: 0,y: -0.015,z: 0.025)]
        // Independently specified 90-degree rotation about Z plus translation.
        let vertices = points.enumerated().map { i,p in
            SurfaceVertex(position: Point3D(x: -p.y+0.1,y: p.x-0.2,z: p.z+0.5),
                          normal: Point3D(x: -1,y: 0,z: 0), observations: [SurfaceObservation(frameIndex: 0,depthPixelIndex: i)])
        }
        let evidence = SurfaceFrameEvidence(captureID: UUID().uuidString, frameID: UUID().uuidString,
            frameSHA256: String(repeating: "a",count: 64), maskSHA256: String(repeating: "b",count: 64),
            source: .syntheticFixture, referenceFromCamera: .identity, registration: nil, retainedSamples: 4, skippedSamples: 0)
        let surface = ObservedSurface(requestSHA256: String(repeating: "c",count: 64), source: .syntheticFixture,
            vertices: vertices, triangles: [[0,1,2],[0,3,1],[0,2,3]], frames: [evidence], notes: ["Synthetic landmarks, not a face scan"])
        let selection = AnatomicalSelection(surfaceSHA256: try HairArtifactHash.digest(surface),
            anatomicalLeftEyeVertex: 0, anatomicalRightEyeVertex: 1, superiorVertex: 2, anteriorVertex: 3, method: "synthetic landmark correspondence")
        return (surface,selection,points)
    }

    func testTranslationMovesWholeCapAndKeepsObservedFaceFixed() throws {
        let (surface,selection,_)=try fixture()
        let envelope=try ScalpCompletion.suggestedEnvelope(surface:surface,selection:selection)
        var request=ScalpCompletionRequest(selection:selection,subjectSessionID:"fixture",scalpID:"scalp",revision:1,envelope:envelope)
        let before=try ScalpCompletion.build(surface:surface,request:request)
        let shift=Point3D(x:0.003,y:0.005,z:-0.002)
        request.envelope=try envelope.translated(by:shift)
        let after=try ScalpCompletion.build(surface:surface,request:request)
        XCTAssertEqual(try HairArtifactHash.digest(before.observed),try HairArtifactHash.digest(after.observed))
        XCTAssertEqual(before.scalp.triangles,after.scalp.triangles)
        for (a,b) in zip(before.scalp.vertices,after.scalp.vertices) {
            XCTAssertLessThan((b-a-shift).length,1e-12)
        }
        XCTAssertFalse(after.acceptedForHeadFitting)
        XCTAssertThrowsError(try envelope.translated(by:Point3D(x:.nan,y:0,z:0)))
    }

    func testScalpCompletionHasOneOpenBoundaryAndPreservesObservedEvidence() throws {
        let (surface,selection,_)=try fixture()
        let envelope=try ScalpCompletion.suggestedEnvelope(surface:surface,selection:selection)
        let request=ScalpCompletionRequest(selection:selection,subjectSessionID:"fixture",scalpID:"scalp",revision:1,envelope:envelope)
        let result=try ScalpCompletion.build(surface:surface,request:request)
        let canonical=try AnatomicalFrame.canonicalize(surface,selection:selection)
        XCTAssertEqual(try HairArtifactHash.digest(result.observed),try HairArtifactHash.digest(canonical))
        XCTAssertFalse(result.acceptedForHeadFitting)
        XCTAssertTrue(result.requiresShapeAndHairlineReview)
        XCTAssertTrue(result.scalp.triangleOrigins.allSatisfy { $0 == .synthetic })
        var edges:[String:Int]=[:]
        for triangle in result.scalp.triangles {
            for i in 0..<3 {
                let a=triangle[i],b=triangle[(i+1)%3]
                edges["\(min(a,b))-\(max(a,b))",default:0]+=1
            }
        }
        XCTAssertTrue(edges.values.allSatisfy { $0==1 || $0==2 })
        XCTAssertEqual(edges.values.filter { $0==1 }.count,64)
        XCTAssertEqual(result.scalp.vertices.count-edges.count+result.scalp.triangles.count,1)
        XCTAssertEqual(result.scalp.vertices[result.boundaryVertexIndices[0]].y,envelope.frontBoundaryY,accuracy:1e-12)
        XCTAssertEqual(result.scalp.vertices[result.boundaryVertexIndices[32]].y,envelope.backBoundaryY,accuracy:1e-12)
        for vertex in result.scalp.vertices {
            let p=vertex-envelope.center,r=envelope.radii
            XCTAssertEqual(p.x*p.x/(r.x*r.x)+p.y*p.y/(r.y*r.y)+p.z*p.z/(r.z*r.z),1,accuracy:1e-10)
        }
    }

    func testScalpEnvelopeEditChangesGeometryWithoutChangingFaceOrProvenance() throws {
        let (surface,selection,_)=try fixture()
        let envelope=try ScalpCompletion.suggestedEnvelope(surface:surface,selection:selection)
        var request=ScalpCompletionRequest(selection:selection,subjectSessionID:"fixture",scalpID:"scalp",revision:1,envelope:envelope)
        let before=try ScalpCompletion.build(surface:surface,request:request)
        request.envelope.radii.x *= 1.1
        request.envelope.origin = .userSupplied
        request.envelope.method = "Explicit width correction in test"
        request.revision=2
        let after=try ScalpCompletion.build(surface:surface,request:request)
        XCTAssertNotEqual(try HairArtifactHash.digest(before.scalp),try HairArtifactHash.digest(after.scalp))
        XCTAssertEqual(try HairArtifactHash.digest(before.observed),try HairArtifactHash.digest(after.observed))
        XCTAssertEqual(before.scalp.triangles,after.scalp.triangles)
        XCTAssertEqual(before.scalp.triangleOrigins,after.scalp.triangleOrigins)
        XCTAssertFalse(after.acceptedForHeadFitting)
    }

    func testScalpCompletionRejectsInvalidEnvelopeAndMeasurementClaims() throws {
        let (surface,selection,_)=try fixture()
        let envelope=try ScalpCompletion.suggestedEnvelope(surface:surface,selection:selection)
        let request=ScalpCompletionRequest(selection:selection,subjectSessionID:"fixture",scalpID:"scalp",revision:1,envelope:envelope)
        var invalid=request;invalid.envelope.origin = .observed
        XCTAssertThrowsError(try ScalpCompletion.build(surface:surface,request:invalid))
        invalid=request;invalid.envelope.radii.x = .nan
        XCTAssertThrowsError(try ScalpCompletion.build(surface:surface,request:invalid))
        invalid=request;invalid.envelope.frontBoundaryY=1
        XCTAssertThrowsError(try ScalpCompletion.build(surface:surface,request:invalid))
        invalid=request;invalid.selection.surfaceSHA256=String(repeating:"f",count:64)
        XCTAssertThrowsError(try ScalpCompletion.build(surface:surface,request:invalid))
    }

    func testScalpReviewHistoryPreservesSourceAndRejectsBrokenRevisions() throws {
        let (source,selection,_)=try fixture()
        let envelope=try ScalpCompletion.suggestedEnvelope(surface:source,selection:selection)
        let request=ScalpCompletionRequest(selection:selection,subjectSessionID:"fixture",scalpID:"scalp",revision:1,envelope:envelope)
        let original=ScalpReviewDocument(source:source,revisions:[request])
        var edit=envelope;edit.radii.x+=0.002;edit.origin = .userSupplied
        let changed=try original.appending(envelope:edit)
        let decoded=try ManifestCoding.decoder().decode(ScalpReviewDocument.self,from:ManifestCoding.encoder().encode(changed))
        XCTAssertEqual(try decoded.latestResult().scalp.revision,2)
        XCTAssertEqual(try HairArtifactHash.digest(decoded.source),try HairArtifactHash.digest(original.source))
        XCTAssertEqual(try HairArtifactHash.digest(decoded.revisions[0]),try HairArtifactHash.digest(request))
        var corrupt=decoded;corrupt.revisions[1].revision=4
        XCTAssertThrowsError(try corrupt.latestResult())
        corrupt=decoded;corrupt.revisions[1].subjectSessionID="different-subject"
        XCTAssertThrowsError(try corrupt.latestResult())
        corrupt=decoded;corrupt.revisions[0].envelope.origin = .observed
        XCTAssertThrowsError(try corrupt.latestResult())
    }

    func testRecoversKnownAnatomicalCoordinatesWithoutScaleOrEvidenceLoss() throws {
        let (surface,selection,expected) = try fixture()
        let result = try AnatomicalFrame.canonicalize(surface, selection: selection)
        for (i,p) in expected.enumerated() {
            XCTAssertLessThan((result.vertices[i].position-p).length,1e-12)
            XCTAssertLessThan((result.referenceFromCanonical.apply(result.vertices[i].position)-surface.vertices[i].position).length,1e-12)
            XCTAssertEqual(result.vertices[i].normal.y,1,accuracy:1e-12)
            XCTAssertEqual(result.vertices[i].normal.x,0,accuracy:1e-12)
            XCTAssertEqual(result.vertices[i].observations[0].depthPixelIndex,i)
        }
        XCTAssertEqual(result.eyeLandmarkSeparationMeters,0.06,accuracy:1e-12)
        XCTAssertEqual(result.triangles,surface.triangles)
        XCTAssertEqual(try HairArtifactHash.digest(result.sourceFrameEvidence),try HairArtifactHash.digest(surface.frames))
        XCTAssertFalse(result.completeHead); XCTAssertFalse(result.inferredScalp)
        XCTAssertEqual(result.source,.syntheticFixture)
    }

    func testRejectsSwappedAnatomicalSidesAndIncorrectSourceHash() throws {
        let (surface,selection,_) = try fixture()
        var swapped = selection; swapped.anatomicalLeftEyeVertex = 1; swapped.anatomicalRightEyeVertex = 0
        XCTAssertThrowsError(try AnatomicalFrame.canonicalize(surface,selection:swapped))
        var stale = selection; stale.surfaceSHA256 = String(repeating:"0",count:64)
        XCTAssertThrowsError(try AnatomicalFrame.canonicalize(surface,selection:stale))
        var duplicate = selection; duplicate.superiorVertex = 0
        XCTAssertThrowsError(try AnatomicalFrame.canonicalize(surface,selection:duplicate))
    }

    func testRejectsUnstablePlaneAndMalformedGeometry() throws {
        var (surface,selection,_) = try fixture()
        // Nondegenerate mesh, but only 1 mm of superior separation is unstable.
        surface.vertices[2].position = Point3D(x: 0.099,y: -0.192,z: 0.5)
        selection.surfaceSHA256 = try HairArtifactHash.digest(surface)
        XCTAssertThrowsError(try AnatomicalFrame.canonicalize(surface,selection:selection))
        (surface,selection,_) = try fixture()
        surface.triangles[0][0] = Int.max
        selection.surfaceSHA256 = try HairArtifactHash.digest(surface)
        XCTAssertThrowsError(try AnatomicalFrame.canonicalize(surface,selection:selection))
        (surface,selection,_) = try fixture()
        surface.vertices[0].observations[0].frameIndex = 8
        selection.surfaceSHA256 = try HairArtifactHash.digest(surface)
        XCTAssertThrowsError(try AnatomicalFrame.canonicalize(surface,selection:selection))
    }
}
