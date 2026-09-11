import Foundation

/// Editable construction parameters, not anatomical measurements or a learned shape prior.
public struct ScalpEnvelope: Codable, Sendable {
    public var center: Point3D
    public var radii: Point3D
    public var frontBoundaryY: Double
    public var sideBoundaryY: Double
    public var backBoundaryY: Double
    public var origin: ObservationOrigin
    public var method: String

    /// Translate the entire inferred cap without changing its shape or boundary angles.
    public func translated(by offset: Point3D) throws -> ScalpEnvelope {
        guard offset.finite else { throw CaptureError.invalid("Scalp translation must be finite.") }
        var result = self
        result.center = center + offset
        result.frontBoundaryY += offset.y
        result.sideBoundaryY += offset.y
        result.backBoundaryY += offset.y
        return result
    }
}

public struct ScalpCompletionRequest: Codable, Sendable {
    public var schemaVersion = 1
    public var selection: AnatomicalSelection
    public var subjectSessionID: String
    public var scalpID: String
    public var revision: Int
    public var envelope: ScalpEnvelope
}

public struct ScalpCompletionResult: Codable, Sendable {
    public var schemaVersion = 1
    public var method = "editable_ellipsoid_scalp_candidate_v1"
    public var requestSHA256: String
    public var request: ScalpCompletionRequest
    /// The observed face stays separate, with its original pixel evidence and topology.
    public var observed: CanonicalObservedSurface
    public var scalp: ScalpProfile
    public var boundaryVertexIndices: [Int]
    public var acceptedForHeadFitting = false
    public var requiresShapeAndHairlineReview = true
    public var notes: [String]
}

public enum ScalpCompletion {
    /// An explicitly heuristic starting envelope. Only scale and the front anchor
    /// depend on the observed landmarks; unseen cranial shape is not measured.
    public static func suggestedEnvelope(surface: ObservedSurface, selection: AnatomicalSelection) throws -> ScalpEnvelope {
        let canonical=try AnatomicalFrame.canonicalize(surface,selection:selection)
        let scale=canonical.eyeLandmarkSeparationMeters/0.064
        let superior=canonical.vertices[selection.superiorVertex].position
        let radii=Point3D(x:0.078*scale,y:0.110*scale,z:0.095*scale)
        let centerY=0.025*scale
        let frontY=min(centerY+radii.y*0.75,max(0.055*scale,superior.y+0.015*scale))
        let normalized=(frontY-centerY)/radii.y
        let centerZ=superior.z-radii.z*sqrt(1-normalized*normalized)
        return ScalpEnvelope(center:Point3D(x:0,y:centerY,z:centerZ),radii:radii,
            frontBoundaryY:frontY,sideBoundaryY:0,backBoundaryY:-0.065*scale,
            origin:.defaultValue,
            method:"Heuristic dimensions scaled by eye-landmark separation; anterior boundary aligned in depth to the selected superior point. Not a population model or measured skull/hairline.")
    }

    public static func build(surface: ObservedSurface, request: ScalpCompletionRequest) throws -> ScalpCompletionResult {
        guard request.schemaVersion==1,!request.subjectSessionID.isEmpty,!request.scalpID.isEmpty,request.revision>=1 else {
            throw CaptureError.invalid("Scalp completion requires explicit identity and revision.")
        }
        let observed=try AnatomicalFrame.canonicalize(surface,selection:request.selection)
        let e=request.envelope
        guard e.center.finite,e.center.length<0.5,e.radii.finite,
              [e.radii.x,e.radii.y,e.radii.z].allSatisfy({ (0.025...0.25).contains($0) }),
              [.defaultValue,.userSupplied].contains(e.origin),!e.method.isEmpty,
              [e.frontBoundaryY,e.sideBoundaryY,e.backBoundaryY].allSatisfy({
                  $0.isFinite && abs(($0-e.center.y)/e.radii.y)<0.95
              }) else { throw CaptureError.invalid("Invalid inferred scalp envelope or unsupported measurement claim.") }
        let meridians=64,rings=24
        var vertices=[Point3D(x:e.center.x,y:e.center.y+e.radii.y,z:e.center.z)]
        for ring in 1...rings {
            for column in 0..<meridians {
                let phi=Double(column)*2*Double.pi/Double(meridians),c=cos(phi)
                let boundary=e.sideBoundaryY+max(0,c)*(e.frontBoundaryY-e.sideBoundaryY)+max(0,-c)*(e.backBoundaryY-e.sideBoundaryY)
                let theta=Double(ring)/Double(rings)*acos((boundary-e.center.y)/e.radii.y)
                vertices.append(Point3D(x:e.center.x+e.radii.x*sin(theta)*sin(phi),
                    y:e.center.y+e.radii.y*cos(theta),z:e.center.z+e.radii.z*sin(theta)*cos(phi)))
            }
        }
        func index(_ ring:Int,_ column:Int)->Int { 1+(ring-1)*meridians+column%meridians }
        var triangles:[[Int]]=[]
        for column in 0..<meridians { triangles.append([0,index(1,column),index(1,column+1)]) }
        for ring in 1..<rings {
            for column in 0..<meridians {
                let a=index(ring,column),b=index(ring+1,column),c=index(ring+1,column+1),d=index(ring,column+1)
                triangles.append([a,b,c]);triangles.append([a,c,d])
            }
        }
        // Catch accidental inversion/degeneration before guides can bind to this surface.
        for t in triangles {
            let a=vertices[t[0]],b=vertices[t[1]],c=vertices[t[2]],p=(a+b+c)/3-e.center
            let outward=Point3D(x:p.x/(e.radii.x*e.radii.x),y:p.y/(e.radii.y*e.radii.y),z:p.z/(e.radii.z*e.radii.z))
            guard (b-a).cross(c-a).dot(outward)>1e-10 else { throw CaptureError.invalid("Scalp candidate contains inverted or degenerate triangles.") }
        }
        let sourceHash=try HairArtifactHash.digest(surface),canonicalHash=try HairArtifactHash.digest(observed)
        let scalp=ScalpProfile(id:request.scalpID,revision:request.revision,subjectSessionID:request.subjectSessionID,
            vertices:vertices,triangles:triangles,
            triangleOrigins:Array(repeating:observed.source == .syntheticFixture ? .synthetic : .inferred,count:triangles.count),
            sourceSHA256:[sourceHash,canonicalHash,try HairArtifactHash.digest(request)],
            method:"Editable ellipsoid cap; all scalp geometry inferred. Boundary is a construction limit, not an observed hairline.")
        return ScalpCompletionResult(requestSHA256:try HairArtifactHash.digest(request),request:request,
            observed:observed,scalp:scalp,boundaryVertexIndices:(0..<meridians).map { index(rings,$0) },
            notes:["Observed facial geometry is retained separately and is not smoothed, deformed or relabelled as scalp.",
                "Every cap triangle is inferred (or synthetic for fixture input); hidden scalp and follicles were not measured.",
                "No hair, bun or clip surface is fitted as skull geometry. Envelope dimensions are editable assumptions.",
                "The cap boundary is not a measured hairline. Side/back shape, scalp-face seam, ears and neck remain unresolved.",
                "Not a watertight completed head, not an accepted anatomical fit, and not a personalized haircut."])
    }
}

/// Portable review document. Revisions preserve one observed source and anatomical selection.
public struct ScalpReviewDocument: Codable, Sendable {
    public var schemaVersion = 1
    public var source: ObservedSurface
    public var revisions: [ScalpCompletionRequest]
    public init(source:ObservedSurface,revisions:[ScalpCompletionRequest]) { self.source=source;self.revisions=revisions }
    public func latestResult() throws -> ScalpCompletionResult {
        guard schemaVersion==1,(1...20).contains(revisions.count),let first=revisions.first else {
            throw CaptureError.invalid("Scalp review requires 1–20 revisions.")
        }
        let selectionHash=try HairArtifactHash.digest(first.selection)
        var result:ScalpCompletionResult?
        for (index,revision) in revisions.enumerated() {
            guard revision.scalpID==first.scalpID,revision.subjectSessionID==first.subjectSessionID,
                  first.revision<=Int.max-index,revision.revision==first.revision+index,
                  try HairArtifactHash.digest(revision.selection)==selectionHash else {
                throw CaptureError.invalid("Scalp revisions must retain subject, source landmarks and consecutive revision numbers.")
            }
            result=try ScalpCompletion.build(surface:source,request:revision)
        }
        return result!
    }
    public func appending(envelope:ScalpEnvelope) throws -> ScalpReviewDocument {
        _=try latestResult()
        var next=revisions.last!
        guard next.revision<Int.max,revisions.count<20 else { throw CaptureError.invalid("This preview supports at most 20 scalp revisions.") }
        next.revision+=1;next.envelope=envelope
        _=try ScalpCompletion.build(surface:source,request:next)
        var copy=self;copy.revisions.append(next);return copy
    }
}
