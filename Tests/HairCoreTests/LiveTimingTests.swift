import XCTest
@testable import HairCore

final class LiveTimingTests: XCTestCase {
    func testIntervalsCameraArrivalsAndBoundedTelemetry() throws {
        var recorder = try LiveTimingRecorder(haircutSHA256: String(repeating: "a", count: 64), capacity: 3)
        recorder.append(timestamp: 10, newCameraFrame: true, overlayState: .acquiring, thermalState: "nominal")
        recorder.append(timestamp: 10.01, newCameraFrame: true, overlayState: .visible, thermalState: "nominal")
        recorder.append(timestamp: 10.03, newCameraFrame: false, overlayState: .visible, thermalState: "fair")
        recorder.append(timestamp: 10.09, newCameraFrame: true, overlayState: .trackingLost, thermalState: "serious")
        recorder.append(timestamp: 10.1, newCameraFrame: false, overlayState: nil, thermalState: "critical")
        let report = recorder.report()
        XCTAssertEqual(report.samples.count, 3)
        XCTAssertEqual(report.droppedTelemetrySamples, 1)
        XCTAssertEqual(report.newCameraFrameCount, 2)
        XCTAssertEqual(report.intervalsOver40ms, 1)
        XCTAssertEqual(report.medianIntervalSeconds!, 0.02, accuracy: 1e-8)
        XCTAssertEqual(report.p95IntervalSeconds!, 0.06, accuracy: 1e-8)
        XCTAssertEqual(report.durationSeconds, 0.1, accuracy: 1e-8)
        XCTAssertFalse(report.sustainedPerformanceVerified)
    }
    func testInvalidAndOutOfOrderTimesDoNotCorruptIntervals() throws {
        var recorder = try LiveTimingRecorder(haircutSHA256: String(repeating: "b", count: 64))
        for time in [Double.nan, -1, 1, 0.9, 1, 1.01] {
            recorder.append(timestamp: time, newCameraFrame: false, overlayState: nil, thermalState: "unexpected")
        }
        let report = recorder.report()
        XCTAssertEqual(report.samples.count, 1)
        XCTAssertEqual(report.samples[0].thermalState, "unknown")
        XCTAssertEqual(report.samples[0].displayIntervalSeconds, 0.01, accuracy: 1e-8)
    }
}
