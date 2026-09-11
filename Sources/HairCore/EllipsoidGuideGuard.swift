import Foundation

public struct EllipsoidGuideGuardRequest: Codable, Sendable {
    public var scalpSHA256: String
    public var envelope: ScalpEnvelope
    /// Allows mesh chord discretization without moving attached roots.
    public var permittedInsetMeters: Double
    public var maximumPointCorrectionMeters: Double
}

public struct EllipsoidGuideGuardReport: Codable, Sendable {
    public var method = "continuous_inferred_ellipsoid_guard_v1"
    public var requestSHA256: String
    public var changedGuideIDs: [String]
    public var changedPointCount: Int
    public var maximumPointCorrectionMeters: Double
    public var minimumNormalizedRadiusBefore: Double
    public var minimumNormalizedRadiusAfter: Double
    public var radialPenetrationUpperBoundMeters: Double
    public var rootsPreserved: Bool = true
    public var continuousEnvelopeCheckPassed: Bool = true
    public var physicalClearanceVerified: Bool = false
    public var notes: [String]
}

/// A conservative geometric constraint for this explicit inferred envelope.
/// Checks the continuous centerline against an inner, uniformly scaled
/// ellipsoid; does not assert that the estimated volume is the person's skull.
public enum EllipsoidGuideGuard {
    public static func validateScalp(_ scalp:ScalpProfile,request:EllipsoidGuideGuardRequest) throws {
        let envelope = request.envelope, radius = envelope.radii
        guard request.scalpSHA256 == (try HairArtifactHash.digest(scalp)),
              envelope.center.finite, envelope.center.length < 0.5, radius.finite,
              [radius.x,radius.y,radius.z].allSatisfy({ (0.025...0.25).contains($0) }),
              [.defaultValue,.userSupplied].contains(envelope.origin), !envelope.method.isEmpty,
              request.permittedInsetMeters.isFinite, (0...0.002).contains(request.permittedInsetMeters),
              request.maximumPointCorrectionMeters.isFinite, (0...0.005).contains(request.maximumPointCorrectionMeters) else {
            throw CaptureError.invalid("Invalid inferred-envelope guard or stale scalp.")
        }
        func normalized(_ p: Point3D) -> Point3D {
            let q = p-envelope.center
            return Point3D(x:q.x/radius.x,y:q.y/radius.y,z:q.z/radius.z)
        }
        guard !scalp.vertices.isEmpty, scalp.vertices.allSatisfy({ $0.finite && abs(normalized($0).length-1) < 1e-6 }) else {
            throw CaptureError.invalid("Guard envelope does not match the scalp's construction surface.")
        }
    }

    /// Validation never repairs a saved or edited artifact.
    public static func check(guides:[HairGuide],scalp:ScalpProfile,request:EllipsoidGuideGuardRequest) throws -> EllipsoidGuideGuardReport {
        var validation=request;validation.maximumPointCorrectionMeters=0
        var report=try apply(guides:guides,scalp:scalp,request:validation).report
        report.requestSHA256=try HairArtifactHash.digest(request)
        return report
    }

    public static func apply(guides: [HairGuide], scalp: ScalpProfile,
                             request: EllipsoidGuideGuardRequest) throws -> (guides: [HairGuide], report: EllipsoidGuideGuardReport) {
        try validateScalp(scalp,request:request)
        guard (1...10_000).contains(guides.count),guides.reduce(0,{$0+$1.points.count})<=1_000_000 else {
            throw CaptureError.invalid("Envelope guard exceeds guide budget.")
        }
        let envelope=request.envelope,radius=envelope.radii
        func normalized(_ p:Point3D)->Point3D {
            let q=p-envelope.center
            return Point3D(x:q.x/radius.x,y:q.y/radius.y,z:q.z/radius.z)
        }
        let largestRadius = max(radius.x,max(radius.y,radius.z))
        let minimumRadius = 1-request.permittedInsetMeters/largestRadius
        func segmentMinimum(_ a: Point3D, _ b: Point3D) throws -> Double {
            let a = normalized(a), b = normalized(b), d = b-a
            guard a.finite,b.finite,d.dot(d)>1e-20 else { throw CaptureError.invalid("Invalid guard segment.") }
            let t = min(1,max(0,-a.dot(d)/d.dot(d)))
            return (a+d*t).length
        }
        var result=guides, changedIDs:[String]=[], pointCount=0, maximumCorrection=0.0
        var minimumBefore=Double.infinity,minimumAfter=Double.infinity
        for index in guides.indices {
            let original=guides[index].points
            guard (2...512).contains(original.count),original.allSatisfy({$0.finite && $0.length<=3}),
                  normalized(original[0]).length >= minimumRadius-1e-12 else {
                throw CaptureError.invalid("An attached root lies inside the guard; revise the scalp or correspondence.")
            }
            var points=original
            for segment in 1..<points.count { minimumBefore=min(minimumBefore,try segmentMinimum(points[segment-1],points[segment])) }
            var converged=false
            for _ in 0..<32 {
                var corrected=false
                for segment in 1..<points.count {
                    let distance=try segmentMinimum(points[segment-1],points[segment])
                    if distance < minimumRadius-1e-12 {
                        guard distance>1e-9 else { throw CaptureError.invalid("Guide crosses the center of the inferred envelope.") }
                        // Scaling both endpoints scales the entire normalized
                        // segment. For the first segment, keep its root fixed
                        // and converge by repeated bounded endpoint updates.
                        let factor=(minimumRadius+1e-10)/distance
                        for pointIndex in [segment-1,segment] where pointIndex>0 {
                            let moved=envelope.center+(points[pointIndex]-envelope.center)*factor
                            guard (moved-original[pointIndex]).length <= request.maximumPointCorrectionMeters+1e-12 else {
                                throw CaptureError.invalid("Guide \(guides[index].id) needs excessive envelope correction; regenerate or revise its fit.")
                            }
                            points[pointIndex]=moved
                        }
                        corrected=true
                    }
                }
                if !corrected { converged=true;break }
            }
            guard converged else { throw CaptureError.invalid("Envelope correction did not converge within its bounded iteration budget.") }
            var changed=false
            for p in points.indices {
                let distance=(points[p]-original[p]).length
                if distance>1e-12 { pointCount+=1;changed=true }
                maximumCorrection=max(maximumCorrection,distance)
            }
            for segment in 1..<points.count { minimumAfter=min(minimumAfter,try segmentMinimum(points[segment-1],points[segment])) }
            result[index].points=points
            if changed { changedIDs.append(guides[index].id) }
        }
        guard minimumAfter>=minimumRadius-1e-12 else { throw CaptureError.invalid("Continuous envelope check failed after correction.") }
        return (result,EllipsoidGuideGuardReport(requestSHA256:try HairArtifactHash.digest(request),
            changedGuideIDs:changedIDs,changedPointCount:pointCount,maximumPointCorrectionMeters:maximumCorrection,
            minimumNormalizedRadiusBefore:minimumBefore,minimumNormalizedRadiusAfter:minimumAfter,
            radialPenetrationUpperBoundMeters:max(0,1-minimumAfter)*largestRadius,
            notes:["Analytic minimum checked over every full polyline segment; roots remain exactly unchanged.",
                "Uses the full inferred ellipsoid, including volume outside the open scalp cap.",
                "Inset accounts for triangle-chord roots; it is not a measured accuracy tolerance.",
                "Centerlines only; strand radius, face/ear clearance, self-collision and physical validity remain separate checks."]))
    }
}
