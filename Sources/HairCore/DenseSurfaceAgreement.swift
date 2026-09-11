import Foundation

public struct DenseSurfaceResidual: Codable, Sendable {
    public var sampleIndex: Int
    public var nearestIndex: Int
    public var distanceMeters: Double
    public var signedPlaneDistanceMeters: Double
    public var normalDot: Double
}

public struct DenseDirectionSummary: Codable, Sendable {
    public var sampleCount: Int
    public var medianMeters: Double
    public var p95Meters: Double
    public var maximumMeters: Double
    public var fractionWithin3mm: Double
    public var fractionWithin10mm: Double
    public var fractionWithOpposingNormals: Double
    public var residuals: [DenseSurfaceResidual]
}

public struct DenseSurfaceAgreementReport: Codable, Sendable {
    public var schemaVersion = 1
    public var method = "bidirectional_nearest_observed_sample_v1"
    public var sourceSurfaceSHA256: String
    public var targetSurfaceSHA256: String
    public var registrationSHA256: String
    public var sourceToTarget: DenseDirectionSummary
    public var targetToSource: DenseDirectionSummary
    public var notes: [String]
}

/// Diagnostic only: never refits the supplied transform or discards outliers.
public enum DenseSurfaceAgreement {
    public static func compare(source: ObservedSurface, target: ObservedSurface,
                               registration: CapturedRegistrationReport) throws -> DenseSurfaceAgreementReport {
        let transform = registration.registration.targetFromSource
        guard source.frames.count == 1, target.frames.count == 1,
              source.frames[0].frameSHA256 == registration.sourceFrameSHA256,
              target.frames[0].frameSHA256 == registration.targetFrameSHA256,
              registration.registration.sourceFrameID == "\(source.frames[0].captureID)/\(source.frames[0].frameID)",
              registration.registration.targetFrameID == "\(target.frames[0].captureID)/\(target.frames[0].frameID)",
              registration.registration.accepted, transform.isValid,
              source.frames[0].referenceFromCamera.rowMajor == RigidTransform.identity.rowMajor,
              target.frames[0].referenceFromCamera.rowMajor == RigidTransform.identity.rowMajor,
              source.coordinateConvention == "reference_optical_x_right_y_down_z_forward_meters",
              source.coordinateConvention == target.coordinateConvention,
              !source.completeHead, !target.completeHead,
              !source.includesInferredAnatomy, !target.includesInferredAnatomy else {
            throw CaptureError.invalid("Dense comparison requires two single-view observed surfaces and their matching accepted captured registration.")
        }
        func validate(_ surface: ObservedSurface) throws {
            guard (3...250_000).contains(surface.vertices.count), surface.vertices.allSatisfy({
                $0.position.finite && $0.position.length <= 10 && $0.normal.finite && abs($0.normal.length-1) < 0.01
            }) else { throw CaptureError.invalid("Dense comparison requires finite metric points and unit normals within its processing bounds.") }
        }
        try validate(source); try validate(target)
        let origin = transform.apply(.zero)
        let moved = source.vertices.map { Sample(point:transform.apply($0.position), normal:(transform.apply($0.normal)-origin).unit) }
        let fixed = target.vertices.map { Sample(point:$0.position,normal:$0.normal) }
        return DenseSurfaceAgreementReport(
            sourceSurfaceSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(source)),
            targetSurfaceSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(target)),
            registrationSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(registration)),
            sourceToTarget: direction(moved,fixed), targetToSource: direction(fixed,moved),
            notes:["Transform is fixed from the captured landmark registration; no ICP, trimming or additional fitting is performed.",
                   "Both directions include all supplied samples, including mask boundaries and unmatched regions. No distance censoring is applied.",
                   "Nearest samples are geometric neighbors, not verified anatomical correspondences. Pixel density and mask coverage affect distances.",
                   "Dense pixels can be correlated with each other and the landmark samples; this is not independent ground truth or a precision claim.",
                   "Signed point-to-plane distances and normal agreement use the nearest sample's local normal, which may be noisy.",
                   "Diagnostic report only. It does not accept a fitting surface, verify subject identity, or authenticate externally supplied JSON."])
    }

    private struct Sample { var point: Point3D; var normal: Point3D }
    private struct Node { var sample: Int; var axis: Int; var left: Int?; var right: Int? }
    private struct Tree {
        var points: [Sample]
        var nodes: [Node] = []
        var root: Int?
        init(_ points: [Sample]) {
            self.points = points
            self.root = nil
            self.root = build(Array(points.indices),depth:0)
        }
        static func coordinate(_ p: Point3D, _ axis: Int) -> Double {
            axis == 0 ? p.x : axis == 1 ? p.y : p.z
        }
        mutating func build(_ indices: [Int], depth: Int) -> Int? {
            guard !indices.isEmpty else { return nil }
            let axis = depth%3
            let sorted = indices.sorted {
                let a = Self.coordinate(points[$0].point,axis), b = Self.coordinate(points[$1].point,axis)
                return a == b ? $0 < $1 : a < b
            }
            let mid = sorted.count/2, index = nodes.count
            nodes.append(Node(sample:sorted[mid],axis:axis,left:nil,right:nil))
            let left = build(Array(sorted[..<mid]),depth:depth+1)
            let right = build(Array(sorted[(mid+1)...]),depth:depth+1)
            nodes[index].left = left; nodes[index].right = right
            return index
        }
        func nearest(_ p: Point3D) -> Int {
            var best = 0, distance = Double.infinity
            func visit(_ index: Int?) {
                guard let index, distance > 0 else { return }
                let node = nodes[index], q = points[node.sample].point, delta = p-q
                let d = delta.dot(delta)
                if d < distance || (d == distance && node.sample < best) { best = node.sample; distance = d }
                let axisDistance = Self.coordinate(p,node.axis)-Self.coordinate(q,node.axis)
                visit(axisDistance < 0 ? node.left : node.right)
                if axisDistance*axisDistance <= distance { visit(axisDistance < 0 ? node.right : node.left) }
            }
            visit(root)
            return best
        }
    }
    private static func direction(_ source: [Sample], _ target: [Sample]) -> DenseDirectionSummary {
        let tree = Tree(target)
        let residuals = source.enumerated().map { i,p -> DenseSurfaceResidual in
            let index = tree.nearest(p.point), q = target[index], delta = p.point-q.point
            return DenseSurfaceResidual(sampleIndex:i,nearestIndex:index,distanceMeters:delta.length,
                signedPlaneDistanceMeters:delta.dot(q.normal),normalDot:p.normal.dot(q.normal))
        }
        let sorted = residuals.map(\.distanceMeters).sorted(), count = Double(sorted.count)
        let mid = sorted.count/2
        return DenseDirectionSummary(sampleCount:sorted.count,
            medianMeters: sorted.count%2 == 0 ? (sorted[mid-1]+sorted[mid])/2 : sorted[mid],
            p95Meters:sorted[max(0,Int(ceil(count*0.95))-1)],maximumMeters:sorted.last!,
            fractionWithin3mm:Double(sorted.filter { $0 <= 0.003 }.count)/count,
            fractionWithin10mm:Double(sorted.filter { $0 <= 0.01 }.count)/count,
            fractionWithOpposingNormals:Double(residuals.filter { $0.normalDot < 0 }.count)/count,
            residuals:residuals)
    }
}
