import XCTest
@testable import HairCore

final class RenderTimingTests: XCTestCase {
    func testOverflowKeepsCompleteCountersButLabelsRetainedPercentiles() throws {
        var recorder = try RenderTimingRecorder(haircutSHA256: String(repeating:"a",count:64), capacity:2)
        for (time,thermal) in [(10.0,"nominal"),(10.01,"nominal"),(10.03,"fair"),(10.1,"critical")] {
            recorder.append(timestamp:time,thermalState:thermal)
        }
        let r = recorder.report()
        XCTAssertEqual(r.observedCallbackCount,4); XCTAssertEqual(r.samples.count,2)
        XCTAssertEqual(r.droppedTelemetrySamples,1); XCTAssertEqual(r.observedIntervalsOver40ms,1)
        XCTAssertEqual(r.callbackThermalCounts,["nominal":2,"fair":1,"critical":1])
        XCTAssertEqual(r.meanCallbackRateHz!,30,accuracy:1e-8)
        XCTAssertEqual(r.retainedP95IntervalSeconds!,0.02,accuracy:1e-8)
        XCTAssertFalse(r.gpuCompletionMeasured); XCTAssertFalse(r.presentationMeasured); XCTAssertFalse(r.sustainedPerformanceVerified)
    }
    func testInvalidTimesEmptyAndSingleSample() throws {
        var recorder = try RenderTimingRecorder(haircutSHA256:String(repeating:"b",count:64))
        XCTAssertNil(recorder.report().meanCallbackRateHz)
        for time in [Double.nan,-1,2,2,1,Double.infinity] { recorder.append(timestamp:time,thermalState:"unsupported") }
        let r=recorder.report();XCTAssertEqual(r.observedCallbackCount,1)
        XCTAssertEqual(r.callbackThermalCounts,["unknown":1]);XCTAssertNil(r.meanCallbackRateHz)
        XCTAssertThrowsError(try RenderTimingRecorder(haircutSHA256:"bad"))
    }
    func testOldTimingReportsDecodeAndNewReportsRetainBothIdentities() throws {
        var display=try LiveTimingRecorder(haircutSHA256:String(repeating:"c",count:64))
        display.append(timestamp:1,newCameraFrame:false,overlayState:nil,thermalState:"nominal")
        var r=display.report()
        let old=try ManifestCoding.decoder().decode(LiveTimingReport.self,from:ManifestCoding.encoder().encode(r))
        XCTAssertNil(old.rendererCallbacks)
        var rendering=try RenderTimingRecorder(haircutSHA256:r.haircutSHA256)
        rendering.append(timestamp:1,thermalState:"nominal");rendering.append(timestamp:1.02,thermalState:"fair")
        r.rendererCallbacks=rendering.report()
        let new=try ManifestCoding.decoder().decode(LiveTimingReport.self,from:ManifestCoding.encoder().encode(r))
        XCTAssertEqual(new.rendererCallbacks?.haircutSHA256,new.haircutSHA256)
        XCTAssertEqual(new.rendererCallbacks?.observedCallbackCount,2)
    }
}
