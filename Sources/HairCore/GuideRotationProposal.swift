import Foundation

public struct GuideRotationDecision: Codable, Sendable {
    public var guideID: String
    public var checkedCandidates: Int
    public var passingCandidates: Int
    public var axis: String?
    public var degrees: Double?
    public var maximumPointMovementMeters: Double?
}

public struct GuideRotationProposalResult: Codable, Sendable {
    public var method = "bounded_fixed_root_rotation_v1"
    public var sourceHaircutSHA256: String
    public var anatomySHA256: String
    public var haircut: HaircutRevision
    public var decisions: [GuideRotationDecision]
    public var clearance: GuideClearanceReport
    public var acceptedForPersonalHaircut = false
    public var notes: [String]
}

/// Research proposal only: preserve guide shape and length while testing orientation.
public enum GuideRotationProposal {
    public static func propose(input: HairDesignInput, haircut: HaircutRevision,
                               anatomy: GuideClearanceInput, includeDiagonalAxes: Bool = false, includeDenseAxes: Bool = false) throws -> GuideRotationProposalResult {
        let evaluate = try GuideClearance.preparedEvaluator(input: input, anatomy: anatomy)
        let baseline = try evaluate(haircut)
        guard baseline.rootViolations?.isEmpty == true else {
            throw CaptureError.invalid("Resolve fixed-root conflicts before curve rotation.")
        }
        let conflicts = Set(baseline.violations.map(\.guideID))
        guard conflicts.count <= 128 else { throw CaptureError.invalid("Rotation proposal exceeds its 128-guide search budget.") }
        var output = haircut
        output.id = UUID().uuidString; output.revision = 1; output.parentSHA256 = nil; output.edit = nil
        output.generation.method = "bounded_fixed_root_rotation_v1:" + baseline.haircutSHA256 + "; source: " + haircut.generation.method
        var axes: [(String,Point3D)] = [("x",Point3D(x:1,y:0,z:0)),("y",Point3D(x:0,y:1,z:0)),("z",Point3D(x:0,y:0,z:1))]
        if includeDiagonalAxes || includeDenseAxes {
            for x in -1...1 { for y in -1...1 { for z in -1...1 {
                guard [x,y,z].filter({ $0 != 0 }).count > 1,
                      x > 0 || (x == 0 && y > 0) || (x == 0 && y == 0 && z > 0) else { continue }
                axes.append(("(\(x),\(y),\(z))",Point3D(x:Double(x),y:Double(y),z:Double(z))))
            } } }
        }
        if includeDenseAxes {
            // Equal-area hemisphere sampling; signed angles cover either axis direction.
            for i in 0..<64 {
                let y = (Double(i)+0.5)/64, radius = sqrt(1-y*y)
                let angle = Double(i)*Double.pi*(3-sqrt(5))
                axes.append(("hemisphere_\(i)",Point3D(x:radius*cos(angle),y:y,z:radius*sin(angle))))
            }
        }
        var decisions: [GuideRotationDecision] = []
        for index in haircut.guides.indices where conflicts.contains(haircut.guides[index].id) {
            try Task.checkCancellation()
            let original = haircut.guides[index]
            var decision = GuideRotationDecision(guideID: original.id, checkedCandidates: 0, passingCandidates: 0)
            var best: (Double, HairGuide)?
            for (axis,vector) in axes {
                for degrees in [-20.0,-15,-10,-5,5,10,15,20] {
                    decision.checkedCandidates += 1
                    var guide = original
                    guide.points = rotated(original.points, axis: vector, degrees: degrees)
                    let movement = zip(guide.points,original.points).map { ($0-$1).length }.max() ?? 0
                    guard movement <= 0.02 else { continue }
                    var isolated = output; isolated.guides = [guide]
                    do {
                        let result = try evaluate(isolated)
                        guard result.surfaceChecksPassed else { continue }
                        decision.passingCandidates += 1
                        if best == nil || movement < best!.0 {
                            best = (movement,guide); decision.axis = axis; decision.degrees = degrees
                            decision.maximumPointMovementMeters = movement
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch { continue } // Invalid geometry/envelope candidates cannot be selected.
                }
            }
            if let best { output.guides[index] = best.1 }
            decisions.append(decision)
        }
        let final = try evaluate(output)
        return GuideRotationProposalResult(sourceHaircutSHA256: baseline.haircutSHA256,
            anatomySHA256: baseline.anatomySHA256, haircut: output, decisions: decisions, clearance: final,
            notes: ["Tested \(axes.count*8) rigid orientations per conflicting guide, at most 20 degrees and 20 mm point movement.",
                    "All roots, guide identities, relative curve shapes and lengths are retained; unaffected guides are unchanged.",
                    "Candidates must pass canonical geometry and exact supplied-anatomy segment checks; final validation includes every guide.",
                    "Neighbor continuity, growth direction, interpolated strands, missing anatomy and physical/aesthetic fit remain unverified."])
    }

    static func rotated(_ points: [Point3D], axis: Point3D, degrees: Double) -> [Point3D] {
        guard let root = points.first else { return [] }
        let radians = degrees * .pi / 180, c = cos(radians), s = sin(radians)
        let unit = axis.unit
        return points.enumerated().map { i, point in
            if i == 0 { return root }
            let p = point-root
            // Rodrigues rotation: supports unit and non-unit supplied axes.
            return root+p*c+unit.cross(p)*s+unit*(unit.dot(p)*(1-c))
        }
    }
}
