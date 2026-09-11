import Foundation

/// Explicit user preferences. Nil means unanswered, never inferred consent or a measurement.
public struct StylingPreferences: Codable, Sendable, Equatable {
    public var maximumDailyMinutes: Int?
    public var allowsHeatTools: Bool?
    public var allowsStylingProducts: Bool?
    public var preserveNaturalTexture: Bool?
    public init(maximumDailyMinutes: Int? = nil, allowsHeatTools: Bool? = nil,
                allowsStylingProducts: Bool? = nil, preserveNaturalTexture: Bool? = nil) {
        self.maximumDailyMinutes=maximumDailyMinutes;self.allowsHeatTools=allowsHeatTools
        self.allowsStylingProducts=allowsStylingProducts;self.preserveNaturalTexture=preserveNaturalTexture
    }
    public func validate() throws {
        guard maximumDailyMinutes != nil || allowsHeatTools != nil || allowsStylingProducts != nil || preserveNaturalTexture != nil,
              maximumDailyMinutes.map({ (0...180).contains($0) }) ?? true else {
            throw CaptureError.invalid("Styling preferences need at least one answer and a daily time limit from 0 to 180 minutes.")
        }
    }
}
