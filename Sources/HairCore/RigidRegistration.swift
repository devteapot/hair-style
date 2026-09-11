import Foundation

public struct LandmarkPair: Codable, Sendable {
    public var id: String
    public var source: Point3D
    public var target: Point3D
    public init(id: String, source: Point3D, target: Point3D) {
        self.id = id; self.source = source; self.target = target
    }
}

/// Correspondences must be in meters and must already exclude hair/obstructions.
/// This algorithm cannot establish that two landmarks belong to the same person.
public struct RegistrationInput: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var sourceFrameID: String
    public var targetFrameID: String
    public var evidenceSource: CaptureSource
    public var fitPairs: [LandmarkPair]
    public var validationPairs: [LandmarkPair]
    public init(sourceFrameID: String, targetFrameID: String, evidenceSource: CaptureSource,
                fitPairs: [LandmarkPair], validationPairs: [LandmarkPair]) {
        self.sourceFrameID = sourceFrameID; self.targetFrameID = targetFrameID
        self.evidenceSource = evidenceSource; self.fitPairs = fitPairs; self.validationPairs = validationPairs
    }
}

public struct RegistrationThresholds: Codable, Sendable {
    public var inlierMeters: Double = 0.005
    public var minimumInlierFraction: Double = 0.6
    public var validationMedianMeters: Double = 0.004
    public var validationP95Meters: Double = 0.010
    public init() { }
}

public struct LandmarkResidual: Codable, Sendable {
    public var id: String
    public var meters: Double
}

public struct RegistrationReport: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var method: String = "horn_rigid_ransac_v1"
    public var inputSHA256: String
    public var sourceFrameID: String
    public var targetFrameID: String
    public var evidenceSource: CaptureSource
    public var targetFromSource: RigidTransform
    public var inlierIDs: [String]
    public var outlierIDs: [String]
    public var fittingResiduals: [LandmarkResidual]
    public var validationResiduals: [LandmarkResidual]
    public var validationMedianMeters: Double
    public var validationP95Meters: Double
    public var thresholds: RegistrationThresholds
    public var accepted: Bool
    public var notes: [String]
}

public enum RigidRegistration {
    public static func register(_ input: RegistrationInput,
                                thresholds: RegistrationThresholds = RegistrationThresholds()) throws -> RegistrationReport {
        guard input.schemaVersion == 1, !input.sourceFrameID.isEmpty, !input.targetFrameID.isEmpty,
              input.sourceFrameID != input.targetFrameID else { throw CaptureError.invalid("Registration requires distinct named coordinate frames and schema v1.") }
        guard (4...200).contains(input.fitPairs.count), (3...200).contains(input.validationPairs.count) else {
            throw CaptureError.invalid("Use 4–200 fitting pairs and 3–200 separate validation pairs.")
        }
        guard thresholds.inlierMeters.isFinite, thresholds.inlierMeters > 0,
              (0.5...1).contains(thresholds.minimumInlierFraction),
              thresholds.validationMedianMeters.isFinite, thresholds.validationMedianMeters > 0,
              thresholds.validationP95Meters.isFinite, thresholds.validationP95Meters >= thresholds.validationMedianMeters else {
            throw CaptureError.invalid("Invalid registration thresholds.")
        }
        let all = input.fitPairs + input.validationPairs
        guard all.allSatisfy({ !$0.id.isEmpty && $0.source.finite && $0.target.finite }),
              Set(all.map(\.id)).count == all.count else {
            throw CaptureError.invalid("Landmark IDs must be distinct across fitting and validation; coordinates must be finite.")
        }
        // Distinct IDs alone do not establish separate samples or prevent duplicated votes.
        for i in all.indices {
            for j in (i+1)..<all.count {
                if (all[i].source - all[j].source).length < 1e-9 || (all[i].target - all[j].target).length < 1e-9 {
                    throw CaptureError.invalid("Use distinct landmark samples, including across fitting and validation.")
                }
            }
        }
        guard spread(input.fitPairs.map(\.source)), spread(input.fitPairs.map(\.target)),
              spread(input.validationPairs.map(\.source)), spread(input.validationPairs.map(\.target)) else {
            throw CaptureError.invalid("Landmarks are coincident, collinear or too narrowly distributed for registration.")
        }
        let required = max(4, Int(ceil(Double(input.fitPairs.count) * thresholds.minimumInlierFraction)))
        var bestIndices: [Int] = []
        var bestError = Double.infinity
        for indices in samples(count: input.fitPairs.count) {
            let subset = indices.map { input.fitPairs[$0] }
            guard let transform = try? solve(subset) else { continue }
            let errors = input.fitPairs.map { (transform.apply($0.source) - $0.target).length }
            let inliers = errors.indices.filter { errors[$0] <= thresholds.inlierMeters }
            let sum = inliers.reduce(0.0) { $0 + errors[$1] * errors[$1] }
            if inliers.count > bestIndices.count || (inliers.count == bestIndices.count && sum < bestError) {
                bestIndices = inliers; bestError = sum
            }
        }
        guard bestIndices.count >= required else { throw CaptureError.invalid("No consistent rigid alignment. Check correspondences, scale, subject motion and capture overlap.") }
        // Refit the consensus and reclassify until stable; fail if refinement loses support.
        var transform = try solve(bestIndices.map { input.fitPairs[$0] })
        var stabilized = false
        for _ in 0..<8 {
            let next = input.fitPairs.indices.filter { (transform.apply(input.fitPairs[$0].source) - input.fitPairs[$0].target).length <= thresholds.inlierMeters }
            guard next.count >= required else { throw CaptureError.invalid("Refined registration lost landmark support.") }
            if next == bestIndices { stabilized = true; break }
            bestIndices = next
            transform = try solve(bestIndices.map { input.fitPairs[$0] })
        }
        guard stabilized else { throw CaptureError.invalid("Rigid-fit consensus did not stabilize; inspect the correspondences.") }
        let residuals = input.fitPairs.map { LandmarkResidual(id: $0.id, meters: (transform.apply($0.source) - $0.target).length) }
        let validation = input.validationPairs.map { LandmarkResidual(id: $0.id, meters: (transform.apply($0.source) - $0.target).length) }
        let sorted = validation.map(\.meters).sorted()
        let median = sorted.count % 2 == 0 ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
        let p95 = sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]
        let accepted = median <= thresholds.validationMedianMeters && p95 <= thresholds.validationP95Meters
        let inlierSet = Set(bestIndices)
        var notes = ["Validation landmarks were not used to fit or select the transform.",
                     "Rigid alignment preserves metric scale; no rescaling or nonrigid warping was applied.",
                     "This report checks supplied landmark geometry, not head reconstruction quality or subject identity."]
        if input.evidenceSource == .syntheticFixture { notes.append("Synthetic evidence: not a physical scan accuracy measurement.") }
        if input.validationPairs.count < 20 { notes.append("With fewer than 20 validation samples, nearest-rank p95 is the maximum error; this is not a population estimate.") }
        if !accepted { notes.append("Independent validation failed. Do not publish this transform for fusion.") }
        return RegistrationReport(inputSHA256: EvidenceHash.sha256(try ManifestCoding.encoder().encode(input)),
            sourceFrameID: input.sourceFrameID, targetFrameID: input.targetFrameID, evidenceSource: input.evidenceSource,
            targetFromSource: transform, inlierIDs: bestIndices.map { input.fitPairs[$0].id },
            outlierIDs: input.fitPairs.indices.filter { !inlierSet.contains($0) }.map { input.fitPairs[$0].id },
            fittingResiduals: residuals, validationResiduals: validation, validationMedianMeters: median,
            validationP95Meters: p95, thresholds: thresholds, accepted: accepted, notes: notes)
    }

    /// Horn's quaternion solution for a proper rigid rotation, with no scale term.
    private static func solve(_ pairs: [LandmarkPair]) throws -> RigidTransform {
        guard pairs.count >= 3, spread(pairs.map(\.source)), spread(pairs.map(\.target)) else {
            throw CaptureError.invalid("Degenerate rigid-fit sample.")
        }
        let sourceMean = pairs.reduce(Point3D.zero) { $0 + $1.source } / Double(pairs.count)
        let targetMean = pairs.reduce(Point3D.zero) { $0 + $1.target } / Double(pairs.count)
        var s = [Double](repeating: 0, count: 9)
        for pair in pairs {
            let a = (pair.source - sourceMean).components, b = (pair.target - targetMean).components
            for row in 0..<3 { for col in 0..<3 { s[row * 3 + col] += a[row] * b[col] } }
        }
        let xx = s[0], xy = s[1], xz = s[2], yx = s[3], yy = s[4], yz = s[5], zx = s[6], zy = s[7], zz = s[8]
        let n = [
            xx+yy+zz, yz-zy, zx-xz, xy-yx,
            yz-zy, xx-yy-zz, xy+yx, zx+xz,
            zx-xz, xy+yx, -xx+yy-zz, yz+zy,
            xy-yx, zx+xz, yz+zy, -xx-yy+zz
        ]
        let q = largestEigenvector(n)
        let w = q[0], x = q[1], y = q[2], z = q[3]
        var transform = RigidTransform(rowMajor: [
            1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w), 0,
            2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w), 0,
            2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y), 0,
            0, 0, 0, 1
        ])
        let offset = targetMean - transform.apply(sourceMean)
        transform.rowMajor[3] = offset.x; transform.rowMajor[7] = offset.y; transform.rowMajor[11] = offset.z
        guard transform.isValid else { throw CaptureError.invalid("Rigid fit produced an invalid transform.") }
        return transform
    }

    /// Jacobi diagonalization handles 180-degree rotations and negative eigenvalues
    /// without the sign/degeneracy limitations of naive power iteration.
    private static func largestEigenvector(_ input: [Double]) -> [Double] {
        var a = input
        var v = RigidTransform.identity.rowMajor
        for _ in 0..<80 {
            var p = 0, q = 1
            for i in 0..<4 { for j in (i+1)..<4 { if abs(a[i*4+j]) > abs(a[p*4+q]) { p = i; q = j } } }
            if abs(a[p*4+q]) < 1e-15 { break }
            let angle = 0.5 * atan2(2 * a[p*4+q], a[q*4+q] - a[p*4+p])
            let c = cos(angle), s = sin(angle)
            for row in 0..<4 {
                let ap = a[row*4+p], aq = a[row*4+q]
                a[row*4+p] = c*ap - s*aq; a[row*4+q] = s*ap + c*aq
            }
            for col in 0..<4 {
                let ap = a[p*4+col], aq = a[q*4+col]
                a[p*4+col] = c*ap - s*aq; a[q*4+col] = s*ap + c*aq
            }
            for row in 0..<4 {
                let vp = v[row*4+p], vq = v[row*4+q]
                v[row*4+p] = c*vp - s*vq; v[row*4+q] = s*vp + c*vq
            }
        }
        let index = (0..<4).max { a[$0*4+$0] < a[$1*4+$1] }!
        let result = (0..<4).map { v[$0*4+index] }
        let norm = sqrt(result.reduce(0) { $0 + $1*$1 })
        return result.map { $0 / norm }
    }

    private static func spread(_ points: [Point3D]) -> Bool {
        guard points.count >= 3 else { return false }
        let anchor = points[0]
        let furthest = points.max { ($0 - anchor).length < ($1 - anchor).length }!
        let line = furthest - anchor
        guard line.length >= 0.005 else { return false }
        return points.contains { line.cross($0 - anchor).length / line.length >= 0.002 }
    }

    private static func samples(count: Int) -> [[Int]] {
        if count <= 16 {
            var result: [[Int]] = []
            for a in 0..<(count-2) { for b in (a+1)..<(count-1) { for c in (b+1)..<count { result.append([a,b,c]) } } }
            return result
        }
        var state: UInt64 = 0x484149525343414e
        var result: [[Int]] = [], used = Set<String>()
        while result.count < 512 {
            var selection = Set<Int>()
            while selection.count < 3 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                selection.insert(Int((state >> 32) % UInt64(count)))
            }
            let sample = selection.sorted()
            if used.insert(sample.map(String.init).joined(separator: ",")).inserted { result.append(sample) }
        }
        return result
    }
}

extension Point3D {
    static let zero = Point3D(x: 0, y: 0, z: 0)
    var finite: Bool { [x, y, z].allSatisfy(\.isFinite) }
    var components: [Double] { [x, y, z] }
    var length: Double { sqrt(x*x + y*y + z*z) }
    static func + (a: Self, b: Self) -> Self { Self(x: a.x+b.x, y: a.y+b.y, z: a.z+b.z) }
    static func - (a: Self, b: Self) -> Self { Self(x: a.x-b.x, y: a.y-b.y, z: a.z-b.z) }
    static func / (a: Self, b: Double) -> Self { Self(x: a.x/b, y: a.y/b, z: a.z/b) }
    func cross(_ b: Self) -> Self { Self(x: y*b.z-z*b.y, y: z*b.x-x*b.z, z: x*b.y-y*b.x) }
}
