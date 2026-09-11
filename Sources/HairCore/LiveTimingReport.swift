import Foundation

public struct LiveTimingSample: Codable, Sendable {
    public var elapsedSeconds: Double
    public var displayIntervalSeconds: Double
    public var newCameraFrame: Bool
    public var overlayState: LiveOverlayState?
    public var thermalState: String
}

/// Display-link scheduling telemetry, not GPU completion or achieved render FPS.
/// Deliberately excludes camera images, face landmarks and transforms.
public struct LiveTimingReport: Codable, Sendable {
    public var schemaVersion = 1
    public var method = "display_link_intervals_v1"
    public var haircutSHA256: String
    public var samples: [LiveTimingSample]
    public var droppedTelemetrySamples: Int
    public var durationSeconds: Double
    public var medianIntervalSeconds: Double?
    public var p95IntervalSeconds: Double?
    public var intervalsOver40ms: Int
    public var newCameraFrameCount: Int
    public var sustainedPerformanceVerified = false
}

public struct LiveTimingRecorder: Sendable {
    private let haircutSHA256: String
    private let capacity: Int
    private var samples: [LiveTimingSample] = []
    private var start: Double?
    private var previous: Double?
    private var dropped = 0
    public init(haircutSHA256: String, capacity: Int = 36_000) throws {
        guard HairArtifactHash.valid(haircutSHA256), (1...100_000).contains(capacity) else {
            throw CaptureError.invalid("Invalid timing report identity or sample budget.")
        }
        self.haircutSHA256 = haircutSHA256; self.capacity = capacity
    }
    public mutating func append(timestamp: Double, newCameraFrame: Bool,
                                overlayState: LiveOverlayState?, thermalState: String) {
        guard timestamp.isFinite, timestamp >= 0 else { return }
        guard let previous else { start = timestamp; self.previous = timestamp; return }
        guard timestamp > previous else { return }
        self.previous = timestamp
        guard samples.count < capacity else { dropped += 1; return }
        samples.append(LiveTimingSample(elapsedSeconds: timestamp - start!, displayIntervalSeconds: timestamp - previous,
            newCameraFrame: newCameraFrame, overlayState: overlayState,
            thermalState: ["nominal", "fair", "serious", "critical"].contains(thermalState) ? thermalState : "unknown"))
    }
    public func report() -> LiveTimingReport {
        let sorted = samples.map(\.displayIntervalSeconds).sorted()
        func percentile(_ fraction: Double) -> Double? {
            guard !sorted.isEmpty else { return nil }
            return sorted[max(0, Int(ceil(Double(sorted.count) * fraction)) - 1)]
        }
        return LiveTimingReport(haircutSHA256: haircutSHA256, samples: samples, droppedTelemetrySamples: dropped,
            durationSeconds: (previous ?? 0) - (start ?? 0), medianIntervalSeconds: percentile(0.5),
            p95IntervalSeconds: percentile(0.95), intervalsOver40ms: samples.filter { $0.displayIntervalSeconds > 0.04 }.count,
            newCameraFrameCount: samples.filter(\.newCameraFrame).count)
    }
}
