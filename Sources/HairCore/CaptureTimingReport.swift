import Foundation

public struct CaptureTimingReport: Codable, Sendable {
    public var method = "saved_image_timestamp_intervals_v1"
    public var captureID: String
    public var manifestSHA256: String
    public var requestedRateHz: Double
    public var frameCount: Int
    /// In manifest order; non-positive entries are retained as timing errors.
    public var intervalsSeconds: [Double]
    public var nonIncreasingFrameIndices: [Int]
    public var elapsedSeconds: Double?
    public var observedRateHz: Double?
    public var medianIntervalSeconds: Double?
    public var p95IntervalSeconds: Double?
    public var maximumIntervalSeconds: Double?
    /// Diagnostic threshold only, not a count of camera or writer dropped frames.
    public var gapsOverTwiceRequestedInterval: Int

    public static func analyze(_ manifest: CaptureManifest) throws -> Self {
        let times = manifest.frames.map { $0.metadata.imageTimestamp }
        guard manifest.requestedSampleRateHz.isFinite, manifest.requestedSampleRateHz > 0,
              times.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw CaptureError.invalid("Capture timing requires finite nonnegative timestamps and a positive requested rate.")
        }
        let intervals = zip(times.dropFirst(), times).map { $0 - $1 }
        let invalid = intervals.enumerated().filter { $0.element <= 0 }.map { $0.offset + 1 }
        let sorted = intervals.filter { $0 > 0 }.sorted()
        let duration = times.count >= 2 && invalid.isEmpty ? times.last! - times.first! : nil
        func percentile(_ fraction: Double) -> Double? {
            guard !sorted.isEmpty else { return nil }
            return sorted[max(0, Int(ceil(Double(sorted.count) * fraction)) - 1)]
        }
        return Self(captureID: manifest.id, manifestSHA256: try HairArtifactHash.digest(manifest),
            requestedRateHz: manifest.requestedSampleRateHz, frameCount: times.count,
            intervalsSeconds: intervals, nonIncreasingFrameIndices: invalid,
            elapsedSeconds: duration, observedRateHz: duration.map { Double(intervals.count) / $0 },
            medianIntervalSeconds: percentile(0.5), p95IntervalSeconds: percentile(0.95),
            maximumIntervalSeconds: sorted.last,
            gapsOverTwiceRequestedInterval: intervals.filter { $0 > 2 / manifest.requestedSampleRateHz + 1e-8 }.count)
    }
}
