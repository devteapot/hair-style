import XCTest
@testable import HairCore

final class TemporaryExportCleanupTests: XCTestCase {
    func testRemovesOnlyOwnedRegularExportsWithoutFollowingLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let owned = ["capture-\(UUID().uuidString).zip", "live-timing-\(UUID().uuidString).json"]
        let retained = ["capture-not-an-id.zip", "capture-\(UUID().uuidString).json", "unrelated.zip", "scalp-review.json"]
        for name in owned + retained { try Data("fixture".utf8).write(to: root.appendingPathComponent(name)) }
        let folder = root.appendingPathComponent("capture-\(UUID().uuidString).zip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let nested = folder.appendingPathComponent(owned[0]); try Data().write(to: nested)
        let link = root.appendingPathComponent("capture-\(UUID().uuidString).zip")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent(retained[0]))
        XCTAssertEqual(try TemporaryExportCleanup.removeAbandonedExports(in: root), 2)
        for name in retained { XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        XCTAssertEqual(try TemporaryExportCleanup.removeAbandonedExports(in: root), 0)
    }
}
