import XCTest
@testable import HairCore

final class GuideConflictOverlayTests: XCTestCase {
    func testExactEndpointsDeduplicationAndStaleReportRejection() throws {
        let (input,haircut)=try SyntheticHaircut.create()
        let anatomy=GuideClearanceInput(scalpSHA256:haircut.scalpSHA256,clearanceMeters:0.001,
            surfaces:[ClearanceSurface(region:.face,origin:.observed,sourceSHA256:String(repeating:"a",count:64),
                vertices:[Point3D(x:-0.4,y:0.12,z:-0.4),Point3D(x:0.4,y:0.12,z:-0.4),Point3D(x:0,y:0.12,z:0.4)],triangles:[[0,1,2]])])
        var report=try GuideClearance.check(input:input,haircut:haircut,anatomy:anatomy)
        XCTAssertFalse(report.violations.isEmpty)
        let markers=try GuideConflictOverlay.segments(haircut:haircut,report:report)
        XCTAssertEqual(markers.count,2)
        for marker in markers {
            let guide=haircut.guides.first { $0.id==marker.guideID }!
            XCTAssertEqual(marker.start.components,guide.points[marker.segmentIndex].components)
            XCTAssertEqual(marker.end.components,guide.points[marker.segmentIndex+1].components)
        }
        report.violations.append(report.violations[0])
        XCTAssertEqual(try GuideConflictOverlay.segments(haircut:haircut,report:report).count,2)
        var wrong=report;wrong.haircutSHA256=String(repeating:"0",count:64)
        XCTAssertThrowsError(try GuideConflictOverlay.segments(haircut:haircut,report:wrong))
        wrong=report;wrong.violations[0].segmentIndex = -1
        XCTAssertThrowsError(try GuideConflictOverlay.segments(haircut:haircut,report:wrong))
        wrong=report;wrong.violations[0].guideID="missing"
        XCTAssertThrowsError(try GuideConflictOverlay.segments(haircut:haircut,report:wrong))
    }
}
