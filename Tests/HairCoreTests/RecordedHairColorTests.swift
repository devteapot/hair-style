import XCTest
@testable import HairCore

final class RecordedHairColorTests: XCTestCase {
    func testColorEditPreservesGeometryAndReplaysThroughRepository() throws {
        let (input, base) = try SyntheticHaircut.create()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = HaircutRepository(root: root)
        let hash = try repo.save(input: input, haircut: base)
        let color = RecordedHairColor(subjectSessionID: input.scalp.subjectSessionID,
            captureID: UUID().uuidString, frameID: UUID().uuidString,
            reportSHA256: String(repeating: "a", count: 64), imageSHA256: String(repeating: "b", count: 64), rgb: [0, 128, 255])
        let edit = HairEdit(baseSHA256: hash, operation: .matchRecordedColor, region: .fringe, value: 0, recordedColor: color)
        let result = try HaircutEditor.apply(edit, to: base, input: input)
        XCTAssertFalse(result.changedGuideIDs.isEmpty)
        for (old, new) in zip(base.guides, result.haircut.guides) {
            XCTAssertEqual(old.points, new.points)
            XCTAssertEqual(try HairArtifactHash.digest(old.root), try HairArtifactHash.digest(new.root))
            if old.region != .fringe { XCTAssertEqual(try HairArtifactHash.digest(old), try HairArtifactHash.digest(new)) }
        }
        let selected = result.haircut.guides.first { $0.region == .fringe }!
        let material = result.haircut.materials.first { $0.id == selected.materialID }!
        XCTAssertEqual(material.linearRGB[0], 0)
        XCTAssertEqual(material.linearRGB[1], 0.21586050011389926, accuracy: 1e-12)
        XCTAssertEqual(material.linearRGB[2], 1)
        let editedHash = try repo.save(input: input, haircut: result.haircut)
        XCTAssertEqual(try HairArtifactHash.digest(repo.load(id: base.id, sha256: editedHash).haircut), editedHash)
        XCTAssertEqual(try HairArtifactHash.digest(repo.load(id: base.id, sha256: hash).haircut), hash)
        let tube = try HairMeshCompiler.compile(input: input, haircut: result.haircut)
        let ribbon = try HairRibbonCompiler.compile(input: input, haircut: result.haircut)
        XCTAssertEqual(try HairArtifactHash.digest(tube.materials), try HairArtifactHash.digest(ribbon.materials))
        var foreign = edit; foreign.recordedColor?.subjectSessionID = "different-subject"
        XCTAssertThrowsError(try HaircutEditor.apply(foreign, to: base, input: input))
        var geometry = edit; geometry.operation = .shortenToLength; geometry.value = 0.05
        XCTAssertThrowsError(try HaircutEditor.apply(geometry, to: base, input: input))
        var duplicate = edit; duplicate.baseSHA256 = editedHash
        XCTAssertThrowsError(try HaircutEditor.apply(duplicate, to: result.haircut, input: input))
    }
}
