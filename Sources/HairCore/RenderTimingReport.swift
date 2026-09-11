import Foundation

public enum RenderTimingContext: String, Codable, Sendable {
    case liveCamera = "live_camera"
    case syntheticInspection = "synthetic_inspection"
}

public struct RenderTimingSample: Codable, Sendable {
    public var elapsedSeconds: Double
    public var callbackIntervalSeconds: Double
    public var thermalState: String
}

/// SceneKit callback cadence, not GPU completion, presentation, or achieved FPS.
public struct RenderTimingReport: Codable, Sendable {
    public var method = "scenekit_did_render_callback_intervals_v1"
    public var haircutSHA256: String
    public var context: RenderTimingContext
    public var observedCallbackCount: Int
    public var observationDurationSeconds: Double
    public var meanCallbackRateHz: Double?
    public var retainedMedianIntervalSeconds: Double?
    public var retainedP95IntervalSeconds: Double?
    public var observedIntervalsOver40ms: Int
    public var callbackThermalCounts: [String: Int]
    public var samples: [RenderTimingSample]
    public var droppedTelemetrySamples: Int
    public var gpuCompletionMeasured = false
    public var presentationMeasured = false
    public var sustainedPerformanceVerified = false
}

public struct RenderTimingRecorder: Sendable {
    private let haircutSHA256: String
    private let capacity: Int
    private let context: RenderTimingContext
    private var start: Double?
    private var previous: Double?
    private var count = 0
    private var over40 = 0
    private var thermalCounts: [String: Int] = [:]
    private var samples: [RenderTimingSample] = []
    private var dropped = 0

    public init(haircutSHA256: String, capacity: Int = 36_000, context: RenderTimingContext = .liveCamera) throws {
        guard HairArtifactHash.valid(haircutSHA256), (1...100_000).contains(capacity) else {
            throw CaptureError.invalid("Invalid rendering trace identity or sample budget.")
        }
        self.haircutSHA256 = haircutSHA256; self.capacity = capacity
        self.context = context
    }

    public mutating func append(timestamp: Double, thermalState: String) {
        guard timestamp.isFinite, timestamp >= 0, previous.map({ timestamp > $0 }) ?? true else { return }
        let thermal = ["nominal", "fair", "serious", "critical"].contains(thermalState) ? thermalState : "unknown"
        thermalCounts[thermal, default: 0] += 1; count += 1
        guard let previous else { start = timestamp; self.previous = timestamp; return }
        let interval = timestamp - previous; self.previous = timestamp
        if interval > 0.04 { over40 += 1 }
        guard samples.count < capacity else { dropped += 1; return }
        samples.append(RenderTimingSample(elapsedSeconds: timestamp-start!, callbackIntervalSeconds: interval, thermalState: thermal))
    }

    public func report() -> RenderTimingReport {
        let sorted = samples.map(\.callbackIntervalSeconds).sorted()
        func percentile(_ fraction: Double) -> Double? {
            sorted.isEmpty ? nil : sorted[max(0, Int(ceil(Double(sorted.count)*fraction))-1)]
        }
        let duration = (previous ?? 0)-(start ?? 0)
        return RenderTimingReport(haircutSHA256: haircutSHA256, context: context, observedCallbackCount: count,
            observationDurationSeconds: duration, meanCallbackRateHz: duration > 0 ? Double(count-1)/duration : nil,
            retainedMedianIntervalSeconds: percentile(0.5), retainedP95IntervalSeconds: percentile(0.95),
            observedIntervalsOver40ms: over40, callbackThermalCounts: thermalCounts,
            samples: samples, droppedTelemetrySamples: dropped)
    }
}
