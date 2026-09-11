import XCTest
@testable import HairCore

final class MaskedDepthDenoisingTests: XCTestCase {
    func testReducesKnownPlanarNoiseWithoutChangingHoleOrExcludedSamples() throws {
        let size=PixelSize(20,20)
        var depth=(0..<400).map { i in Float(0.5+((i+i/20)%2==0 ? 0.0008 : -0.0008)) }
        var usable=[Bool](repeating:true,count:400)
        depth[210] = .nan; usable[210]=false
        depth[211] = 0.6; usable[211]=false
        let original=depth
        let result=try MaskedDepthDenoising.apply(depth,usable:usable,size:size,settings:.init())
        XCTAssertTrue(result.values[210].isNaN);XCTAssertEqual(result.values[211],0.6)
        let valid=(0..<400).filter { usable[$0] }
        let before=valid.reduce(0.0) { $0+pow(Double(original[$1])-0.5,2) }
        let after=valid.reduce(0.0) { $0+pow(Double(result.values[$1])-0.5,2) }
        XCTAssertLessThan(after,before*0.2)
        XCTAssertLessThanOrEqual(result.maximumAdjustmentMeters,0.001)
        XCTAssertEqual(depth[211],original[211])
    }

    func testPreservesStepAndIsolatedSurfaceRatherThanBridgingDepthDiscontinuity() throws {
        let size=PixelSize(20,20)
        var depth=(0..<400).map { Float($0%20<10 ? 0.5 : 0.53) }
        depth[210]=0.6
        let result=try MaskedDepthDenoising.apply(depth,usable:[Bool](repeating:true,count:400),size:size,settings:.init())
        XCTAssertEqual(result.values,depth)
        XCTAssertGreaterThan(result.counts["denoisingRejectedNeighborSamples"]!,0)
        XCTAssertGreaterThan(result.counts["denoisingInsufficientNeighbors"]!,0)
    }

    func testClampBoundsFloatRoundingAndRejectsInvalidParameters() throws {
        let size=PixelSize(9,9);var depth=[Float](repeating:0.5015,count:81);depth[40]=0.5
        var settings=DepthDenoisingSettings();settings.maximumAdjustmentMeters=0.0001
        let result=try MaskedDepthDenoising.apply(depth,usable:[Bool](repeating:true,count:81),size:size,settings:settings)
        XCTAssertGreaterThan(result.values[40],depth[40])
        XCTAssertLessThanOrEqual(result.maximumAdjustmentMeters,settings.maximumAdjustmentMeters)
        XCTAssertGreaterThan(result.counts["denoisingClampedPixels"]!,0)
        settings.rangeSigmaMeters = .nan
        XCTAssertThrowsError(try MaskedDepthDenoising.apply(depth,usable:[Bool](repeating:true,count:81),size:size,settings:settings))
        settings = .init();depth[0] = .nan
        XCTAssertThrowsError(try MaskedDepthDenoising.apply(depth,usable:[Bool](repeating:true,count:81),size:size,settings:settings))
    }
}
