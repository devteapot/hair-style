import Foundation

public enum FaceConditioningMode: String, Codable, Sendable { case personal, genericAblation }
public struct FaceConditionedBriefRequest: Codable, Sendable {
    public var schemaVersion = 1
    public var chinVertex: Int
    public var mode: FaceConditioningMode
    /// Explicit experiment constants, not population measurements or user preferences.
    public var referenceProportion = 1.25
    public var referenceFringeLengthMeters = 0.04
}
public struct FaceConditionedBriefResult: Codable, Sendable {
    public var method = "chin_eye_ratio_fringe_policy_research_v1"
    public var request: FaceConditionedBriefRequest
    public var requestSHA256: String
    public var sourceInputSHA256: String
    public var scalpReviewSHA256: String
    public var eyeSeparationMeters: Double
    public var chinBelowEyePlaneMeters: Double
    public var observedProportion: Double
    public var appliedProportion: Double
    public var proposedFringeLengthMeters: Double
    public var constrainedFringeLengthMeters: Double
    public var input: HairDesignInput
    public var aestheticQualityVerified = false
    public var physicalFeasibilityVerified = false
    public var notes: [String]
}

/// A bounded regional policy for controlled personalization experiments. It does
/// not diagnose face shape or establish which style is aesthetically preferable.
public enum FaceConditionedBrief {
    public static func compile(input: HairDesignInput, review: ScalpReviewDocument,
                               request: FaceConditionedBriefRequest) throws -> FaceConditionedBriefResult {
        try HaircutValidator.validateInput(input)
        let head=try review.latestResult()
        guard head.scalp.subjectSessionID==input.scalp.subjectSessionID,
              head.scalp.coordinateConvention==input.scalp.coordinateConvention,
              head.scalp.sourceSHA256.allSatisfy(input.scalp.sourceSHA256.contains),
              try HairArtifactHash.digest(head.scalp.vertices)==HairArtifactHash.digest(input.scalp.vertices),
              head.scalp.triangles==input.scalp.triangles,head.scalp.triangleOrigins==input.scalp.triangleOrigins,
              request.schemaVersion==1,(0.8...2).contains(request.referenceProportion),
              (0.01...0.10).contains(request.referenceFringeLengthMeters),
              head.observed.vertices.indices.contains(request.chinVertex),
              head.observed.triangles.contains(where: { $0.contains(request.chinVertex) }) else {
            throw CaptureError.invalid("Face policy requires matching scalp evidence, a connected chin selection and bounded constants.")
        }
        let chin=head.observed.vertices[request.chinVertex].position
        let width=head.observed.eyeLandmarkSeparationMeters,height = -chin.y
        guard abs(chin.x)<width*0.3,(0.04...0.18).contains(height),(0.6...3).contains(height/width) else {
            throw CaptureError.invalid("Selected chin is outside the provisional central lower-face bounds.")
        }
        let proportion=height/width
        let applied=request.mode == .personal ? proportion : request.referenceProportion
        // The bounded response is a declared experimental styling rule. It is
        // independent of global guide/scalp fitting and can be ablated on one head.
        let factor=max(0.75,min(1.25,applied/request.referenceProportion))
        let proposed=request.referenceFringeLengthMeters*factor
        guard let index=input.brief.lengthLimits.firstIndex(where: { $0.region == .fringe }) else {
            throw CaptureError.invalid("Missing fringe constraints.")
        }
        let previous=input.brief.lengthLimits[index]
        let constrained=min(previous.maximumMeters,max(previous.minimumMeters,proposed))
        var result=input
        result.brief.lengthLimits[index].maximumMeters=constrained
        if constrained<previous.maximumMeters { result.brief.lengthLimits[index].origin = .defaultValue }
        result.brief.stylingAssumptions.append("Experimental chin-to-eye fringe policy; reference constants are defaults, not inferred preferences. Natural-hair feasibility and aesthetic suitability remain unverified.")
        try HaircutValidator.validateInput(result)
        return FaceConditionedBriefResult(request:request,requestSHA256:try HairArtifactHash.digest(request),
            sourceInputSHA256:try HairArtifactHash.digest(input),scalpReviewSHA256:try HairArtifactHash.digest(review),
            eyeSeparationMeters:width,chinBelowEyePlaneMeters:height,observedProportion:proportion,appliedProportion:applied,
            proposedFringeLengthMeters:proposed,constrainedFringeLengthMeters:constrained,input:result,
            notes:["Chin and eye selections are landmark estimates on depth-backed vertices, not validated anatomical measurements.",
                   "Only the fringe length cap changes. Source scalp, natural-hair observations, seed, envelope guard and other regional constraints are retained.",
                   "Reference proportion and length define a comparison policy, not population norms or a proven flattering style.",
                   "Unknown natural-hair properties stay unknown. This experiment does not complete personal-style recommendation or head validation."])
    }
}
