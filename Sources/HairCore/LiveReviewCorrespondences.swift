import Foundation

/// A user-frozen neutral tracker mesh. Kept in memory by the native alignment
/// flow; no camera image, Face ID template or biometric identity is requested.
public struct LiveFaceReference: Codable, Sendable {
    public var vertices: [Point3D]
    public var triangles: [[Int]]
    public init(vertices: [Point3D], triangles: [[Int]]) {
        self.vertices = vertices; self.triangles = triangles
    }
    public func validate() throws {
        guard (7...10_000).contains(vertices.count), (1...30_000).contains(triangles.count),
              vertices.allSatisfy({ $0.finite && $0.length <= 0.5 }),
              triangles.allSatisfy({ $0.count == 3 && Set($0).count == 3 && $0.allSatisfy(vertices.indices.contains) }) else {
            throw CaptureError.invalid("The neutral face reference has invalid geometry.")
        }
    }
    public var topologySHA256: String { get throws { try HairArtifactHash.digest(triangles) } }
}

public struct LiveReviewPointPair: Codable, Sendable {
    public var observedVertex: Int
    public var faceVertex: Int
    public init(observedVertex: Int, faceVertex: Int) {
        self.observedVertex = observedVertex; self.faceVertex = faceVertex
    }
}

public struct LiveReviewAlignmentResult: Sendable {
    public var package: LivePreviewPackage
    public var referenceRegistration: RegistrationReport
}

public enum LiveReviewCorrespondences {
    /// First four fit a rigid transform; the other three are held out of fitting.
    public static let labels = ["Nose tip", "Chin tip", "Your left outer eye corner", "Your right outer eye corner",
                                "Your left mouth corner", "Your right mouth corner", "Nose bridge between the eyes"]

    public static func prepare(input: HairDesignInput, haircut: HaircutRevision,
                               observed: CanonicalObservedSurface, reference: LiveFaceReference,
                               pairs: [LiveReviewPointPair]) throws -> LiveReviewAlignmentResult {
        try reference.validate()
        guard input.scalp.sourceSHA256.contains(try HairArtifactHash.digest(observed)),
              observed.coordinateConvention == input.scalp.coordinateConvention,
              !observed.inferredScalp, !observed.completeHead,
              pairs.count == labels.count,
              Set(pairs.map(\.observedVertex)).count == pairs.count,
              Set(pairs.map(\.faceVertex)).count == pairs.count else {
            throw CaptureError.invalid("Select seven distinct matching points on this haircut's recorded face and the neutral reference.")
        }
        let observedUsed = Set(observed.triangles.flatMap { $0 })
        let referenceUsed = Set(reference.triangles.flatMap { $0 })
        let selections = try pairs.enumerated().map { index, pair in
            guard observed.vertices.indices.contains(pair.observedVertex), reference.vertices.indices.contains(pair.faceVertex),
                  observedUsed.contains(pair.observedVertex), referenceUsed.contains(pair.faceVertex),
                  !observed.vertices[pair.observedVertex].observations.isEmpty else {
                throw CaptureError.invalid("Alignment points must lie on the recorded face and tracker mesh, never the inferred scalp.")
            }
            return LiveLandmarkSelection(id: "manual_\(index)", canonicalPoint: observed.vertices[pair.observedVertex].position,
                                         faceVertexIndex: pair.faceVertex)
        }
        let correspondences = selections.map { LandmarkPair(id: $0.id, source: $0.canonicalPoint, target: reference.vertices[$0.faceVertexIndex]) }
        let report = try RigidRegistration.register(RegistrationInput(sourceFrameID: "personal_canonical", targetFrameID: "ar_face_local",
            evidenceSource: observed.source, fitPairs: Array(correspondences.prefix(4)), validationPairs: Array(correspondences.suffix(3))))
        guard report.accepted else {
            throw CaptureError.invalid("The three held-out points disagree with the alignment. Correct the points or improve the face scan.")
        }
        var package = LivePreviewPackage(input: input, haircut: haircut, fitLandmarks: Array(selections.prefix(4)),
                                         validationLandmarks: Array(selections.suffix(3)))
        package.meshSettings = .modelReview
        package.faceTopologySHA256 = try reference.topologySHA256
        package.faceVertexCount = reference.vertices.count
        // Revalidate canonical identity, guard and bounds before transferring a
        // selected revision. Neither the guides nor the observed face are warped.
        _ = try package.prepareMesh()
        return LiveReviewAlignmentResult(package: package, referenceRegistration: report)
    }
}
