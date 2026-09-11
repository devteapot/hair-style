import Foundation

public struct LiveMeshSettings: Codable, Sendable {
    public var radialSides: Int
    public var radiusScale: Double
    public static let modelReview = LiveMeshSettings(radialSides: 3, radiusScale: 8)
}

public struct LiveLandmarkSelection: Codable, Sendable {
    public var id: String
    public var canonicalPoint: Point3D
    public var faceVertexIndex: Int
    public init(id: String, canonicalPoint: Point3D, faceVertexIndex: Int) {
        self.id = id; self.canonicalPoint = canonicalPoint; self.faceVertexIndex = faceVertexIndex
    }
}
public struct LivePreviewPackage: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var input: HairDesignInput
    public var haircut: HaircutRevision
    public var fitLandmarks: [LiveLandmarkSelection]
    public var validationLandmarks: [LiveLandmarkSelection]
    /// Absent in legacy packages: six sides and physical radius, as before.
    public var meshSettings: LiveMeshSettings?
    public var faceTopologySHA256: String?
    public var faceVertexCount: Int?
    public init(input: HairDesignInput, haircut: HaircutRevision, fitLandmarks: [LiveLandmarkSelection],
                validationLandmarks: [LiveLandmarkSelection]) {
        self.input = input; self.haircut = haircut; self.fitLandmarks = fitLandmarks
        self.validationLandmarks = validationLandmarks
    }
    public func prepareMesh() throws -> CompiledHairMesh {
        let points = fitLandmarks + validationLandmarks
        if faceTopologySHA256 != nil || faceVertexCount != nil {
            guard let topology = faceTopologySHA256, HairArtifactHash.valid(topology),
                  let count = faceVertexCount, (7...10_000).contains(count),
                  points.allSatisfy({ (0..<count).contains($0.faceVertexIndex) }) else {
                throw CaptureError.invalid("Invalid tracker topology binding.")
            }
        }
        guard schemaVersion == 1, (4...200).contains(fitLandmarks.count), (3...200).contains(validationLandmarks.count),
              Set(points.map(\.id)).count == points.count,
              Set(points.map(\.faceVertexIndex)).count == points.count,
              points.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 128 && $0.faceVertexIndex >= 0 &&
                  $0.faceVertexIndex < 10_000 && $0.canonicalPoint.finite && $0.canonicalPoint.length <= 0.5 }) else {
            throw CaptureError.invalid("Invalid live package or landmark correspondence selections.")
        }
        // Identity registration checks distinctness/spread before a camera is opened.
        let pairs = points.map { LandmarkPair(id: $0.id, source: $0.canonicalPoint, target: $0.canonicalPoint) }
        _ = try RigidRegistration.register(RegistrationInput(sourceFrameID: "personal_canonical", targetFrameID: "preflight_copy",
            evidenceSource: input.scalp.triangleOrigins.contains(.synthetic) ? .syntheticFixture : .sensor,
            fitPairs: Array(pairs.prefix(fitLandmarks.count)), validationPairs: Array(pairs.suffix(validationLandmarks.count))))
        return try HairMeshCompiler.compile(input: input, haircut: haircut,
            radialSides: meshSettings?.radialSides ?? 6, radiusScale: meshSettings?.radiusScale ?? 1)
    }

    public func validateTrackerTopology(vertexCount: Int, triangles: [[Int]]) throws {
        if let expected = faceVertexCount, expected != vertexCount {
            throw CaptureError.invalid("Tracker vertex count changed. Select alignment points again.")
        }
        if let expected = faceTopologySHA256, expected != (try HairArtifactHash.digest(triangles)) {
            throw CaptureError.invalid("Tracker topology changed. Select alignment points again.")
        }
    }
}
