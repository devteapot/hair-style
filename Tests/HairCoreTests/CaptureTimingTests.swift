import XCTest
@testable import HairCore

final class CaptureTimingTests: XCTestCase {
    func testReportsSavedCadenceAndPreservesInvalidOrdering() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try SyntheticCapture.create(in: root)
        var manifest = try CaptureBundle.load(bundle)
        manifest.requestedSampleRateHz = 15
        for (i, time) in [10.0, 10.1, 10.4].enumerated() { manifest.frames[i].metadata.imageTimestamp = time }
        let report = try CaptureTimingReport.analyze(manifest)
        XCTAssertEqual(report.observedRateHz!, 5, accuracy: 1e-8)
        XCTAssertEqual(report.p95IntervalSeconds!, 0.3, accuracy: 1e-8)
        XCTAssertEqual(report.gapsOverTwiceRequestedInterval, 1)
        manifest.frames[1].metadata.imageTimestamp = 10
        let duplicate = try CaptureTimingReport.analyze(manifest)
        XCTAssertNil(duplicate.observedRateHz)
        XCTAssertEqual(duplicate.nonIncreasingFrameIndices, [1])
        manifest.frames = []
        XCTAssertNil(try CaptureTimingReport.analyze(manifest).observedRateHz)
    }
}
