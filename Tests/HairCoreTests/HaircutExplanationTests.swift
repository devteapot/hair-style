import XCTest
@testable import HairCore

final class HaircutExplanationTests: XCTestCase {
    func testUnknownIsNotConvertedToAnObservedLength() throws {
        let (input, cut) = try SyntheticHaircut.create()
        let report = try HaircutExplanation.build(input: input, haircut: cut)
        XCTAssertNil(report.regions.first { $0.region == .fringe }!.availableLengthMeters)
        XCTAssertEqual(report.regions.first { $0.region == .crown }!.availableLengthOrigin, .userSupplied)
        XCTAssertFalse(report.physicalFeasibilityVerified)
        XCTAssertEqual(report.generationOrigin, .syntheticFixture)
    }
    func testExplainsExactEditedRevisionAndRejectsStaleSource() throws {
        var (input, cut) = try SyntheticHaircut.create()
        let original = try HaircutExplanation.build(input: input, haircut: cut)
        let edit = HairEdit(baseSHA256: original.haircutSHA256, operation: .shortenToLength, region: .fringe, value: 0.04)
        let result = try HaircutEditor.apply(edit, to: cut, input: input)
        let report = try HaircutExplanation.build(input: input, haircut: result.haircut)
        XCTAssertNotEqual(report.haircutSHA256, original.haircutSHA256)
        XCTAssertEqual(report.revision, 2)
        XCTAssertEqual(report.regions.first { $0.region == .fringe }!.maximumLengthMeters, 0.04, accuracy: 1e-8)
        XCTAssertEqual(report.lastEdit?.region, .fringe)
        input.brief.seed += 1
        XCTAssertThrowsError(try HaircutExplanation.build(input: input, haircut: cut))
    }
}
