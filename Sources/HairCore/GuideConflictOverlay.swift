import Foundation

public struct GuideConflictSegment: Sendable {
    public var guideID: String
    public var segmentIndex: Int
    public var start: Point3D
    public var end: Point3D
}

/// Diagnostic selection only; never changes or repairs the haircut.
public enum GuideConflictOverlay {
    public static func segments(haircut: HaircutRevision, report: GuideClearanceReport) throws -> [GuideConflictSegment] {
        guard report.haircutSHA256 == (try HairArtifactHash.digest(haircut)) else {
            throw CaptureError.invalid("Clearance markers belong to another haircut revision.")
        }
        guard Set(haircut.guides.map(\.id)).count == haircut.guides.count else { throw CaptureError.invalid("Duplicate guide identities cannot be highlighted.") }
        var indices: [String: Set<Int>] = [:]
        let guides=Dictionary(uniqueKeysWithValues:haircut.guides.map { ($0.id,$0) })
        for violation in report.violations {
            guard let guide=guides[violation.guideID],violation.segmentIndex>=0,
                  violation.segmentIndex<guide.points.count-1 else {
                throw CaptureError.invalid("Clearance marker refers to an unavailable guide segment.")
            }
            indices[guide.id,default:[]].insert(violation.segmentIndex)
        }
        return haircut.guides.flatMap { guide in
            (indices[guide.id] ?? []).sorted().map { index in
                GuideConflictSegment(guideID:guide.id,segmentIndex:index,start:guide.points[index],end:guide.points[index+1])
            }
        }
    }
}
