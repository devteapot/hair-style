import XCTest
@testable import HairCore

final class HairTrimOptionsTests: XCTestCase {
    private func fixture(minimum: Double = 0.04, lengths: [Double] = [0.04, 0.06]) throws -> (HairDesignInput, HaircutRevision) {
        var (input, haircut) = try SyntheticHaircut.create()
        input.brief.lengthLimits[0].minimumMeters = minimum
        haircut.briefSHA256 = try HairArtifactHash.digest(input.brief)
        let guide = haircut.guides[0]
        haircut.guides = lengths.enumerated().map { i, length in
            var g = guide; g.id = "fringe-\(i)"
            g.points = [guide.points[0], guide.points[0] + Point3D(x: 0, y: length, z: 0)]
            return g
        } + [haircut.guides[1]]
        return (input, haircut)
    }

    func testTrimAtShortestGuideLengthChangesLongerGuidesAndKeepsRoots() throws {
        let (input, base) = try fixture()
        let options = try HairTrimOptions(input: input, haircut: base, region: .fringe)
        XCTAssertEqual(options.targetRangeMillimeters, 40...40)
        XCTAssertTrue(options.canTrim(toMillimeters: 40))
        XCTAssertFalse(options.canTrim(toMillimeters: 39))
        XCTAssertFalse(options.canTrim(toMillimeters: 41))
        let edit = HairEdit(baseSHA256: try HairArtifactHash.digest(base), operation: .shortenToLength, region: .fringe, value: 0.04)
        let result = try HaircutEditor.apply(edit, to: base, input: input)
        XCTAssertEqual(result.changedGuideIDs, ["fringe-1"])
        XCTAssertEqual(result.haircut.guides.map(\.root.normalOffsetMeters), base.guides.map(\.root.normalOffsetMeters))
        try HaircutEditor.verifyTransition(from: base, to: result.haircut, input: input)
        XCTAssertFalse(try HairTrimOptions(input: input, haircut: result.haircut, region: .fringe).canTrim(toMillimeters: 40))
    }

    func testFractionalBoundsRoundingAndUnavailableTargets() throws {
        let (input, cut) = try fixture(minimum: 0.029, lengths: [0.0314, 0.06])
        let options = try HairTrimOptions(input: input, haircut: cut, region: .fringe)
        XCTAssertEqual(options.targetRangeMillimeters, 29...31)
        XCTAssertEqual(options.clampedTarget(10), 29)
        XCTAssertEqual(options.clampedTarget(70), 31)
        XCTAssertFalse(options.canTrim(toMillimeters: .nan))
        XCTAssertFalse(options.canTrim(toMillimeters: 30.5))
        let (narrow, short) = try fixture(minimum: 0.0404, lengths: [0.0405, 0.05])
        XCTAssertNil(try HairTrimOptions(input: narrow, haircut: short, region: .fringe).targetRangeMillimeters)
        XCTAssertThrowsError(try HairTrimOptions(input: input, haircut: cut, region: .nape))
    }
}
