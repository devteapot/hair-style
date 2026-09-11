import XCTest
@testable import HairCore

final class SurfaceComponentTests: XCTestCase {
    private var triangles: [[Int]] {
        // 101 connected vertices, plus a separate three-vertex fragment.
        (1..<100).map { [0,$0,$0+1] } + [[200,201,202]]
    }
    func testRetainsSeedComponentAndReportsEveryExcludedPixel() throws {
        let result = try SurfaceConnectedComponent.select(triangles:triangles,
            selection:SurfaceComponentSelection(seedDepthPixelIndex:50))
        XCTAssertEqual(result.componentVertexCounts,[101,3])
        XCTAssertEqual(result.originalSampleCount,104)
        XCTAssertEqual(result.retainedSampleCount,101)
        XCTAssertEqual(result.excludedDepthPixelIndices,[200,201,202])
    }
    func testWrongSeedAndExcessRemovalFailInsteadOfSelectingLargestSilently() throws {
        XCTAssertThrowsError(try SurfaceConnectedComponent.select(triangles:triangles,
            selection:SurfaceComponentSelection(seedDepthPixelIndex:200)))
        XCTAssertThrowsError(try SurfaceConnectedComponent.select(triangles:triangles,
            selection:SurfaceComponentSelection(seedDepthPixelIndex:999)))
        XCTAssertThrowsError(try SurfaceConnectedComponent.select(triangles:triangles,
            selection:SurfaceComponentSelection(seedDepthPixelIndex:50,maximumRemovedFraction:0)))
    }
    func testConnectedRegionAndInvalidInputs() throws {
        let report = try SurfaceConnectedComponent.select(triangles:[[0,1,2],[2,3,4]],selection:.init(seedDepthPixelIndex:4))
        XCTAssertEqual(report.retainedSampleCount,5); XCTAssertTrue(report.excludedDepthPixelIndices.isEmpty)
        XCTAssertThrowsError(try SurfaceConnectedComponent.select(triangles:[[0,0,1]],selection:.init(seedDepthPixelIndex:0)))
        XCTAssertThrowsError(try SurfaceConnectedComponent.select(triangles:triangles,selection:.init(seedDepthPixelIndex:0,maximumRemovedFraction:.nan)))
    }
}
