import Foundation

/// Whole-millimeter targets for a regional trim that never extends a guide.
/// Geometry and anatomy still require validation when applying the edit.
public struct HairTrimOptions: Sendable {
    public let targetRangeMillimeters: ClosedRange<Double>?
    private let longestGuideMeters: Double

    public init(input: HairDesignInput, haircut: HaircutRevision, region: HairRegion) throws {
        guard let limit = input.brief.lengthLimits.first(where: { $0.region == region }),
              limit.minimumMeters.isFinite, limit.maximumMeters.isFinite,
              limit.minimumMeters >= 0, limit.minimumMeters <= limit.maximumMeters else {
            throw CaptureError.invalid("Missing or invalid regional trim limits.")
        }
        let lengths = try haircut.guides.filter { $0.region == region }.map { try HaircutValidator.arcLength($0.points) }
        guard let shortest = lengths.min(), let longest = lengths.max(), shortest.isFinite, longest.isFinite else {
            throw CaptureError.invalid("The selected region has no valid guide lengths.")
        }
        longestGuideMeters = longest
        let lower = ceil(max(0.001, limit.minimumMeters) * 1000 - 1e-6)
        // Match the editor's 1 nm non-extension tolerance at an integer boundary.
        let upper = floor(min(1.5, min(limit.maximumMeters + 1e-9, shortest + 1e-9)) * 1000)
        targetRangeMillimeters = lower <= upper ? lower...upper : nil
    }

    public func canTrim(toMillimeters value: Double) -> Bool {
        guard value.isFinite, value == value.rounded(), let range = targetRangeMillimeters,
              range.contains(value) else { return false }
        return longestGuideMeters > value / 1000 + 1e-9
    }

    public func clampedTarget(_ value: Double) -> Double? {
        guard let range = targetRangeMillimeters else { return nil }
        return value.isFinite ? min(range.upperBound, max(range.lowerBound, value.rounded())) : range.upperBound
    }
}
