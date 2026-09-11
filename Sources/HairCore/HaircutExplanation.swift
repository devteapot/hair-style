import Foundation

public struct HairRegionExplanation: Codable, Sendable {
    public var region: HairRegion
    public var guideCount: Int
    public var minimumLengthMeters: Double
    public var maximumLengthMeters: Double
    public var limit: RegionalLengthLimit
    public var availableLengthMeters: Double?
    public var availableLengthOrigin: ObservationOrigin
    public var requiresGrowth: Bool
}

/// Describes validated parameters, without inferring aesthetic suitability.
public struct HaircutExplanation: Codable, Sendable {
    public var haircutSHA256: String
    public var revision: Int
    public var mode: DesignMode
    public var generationOrigin: HairGenerationOrigin
    public var regions: [HairRegionExplanation]
    public var lastEdit: HairEdit?
    public var stylingAssumptions: [String]
    public var stylingPreferences: StylingPreferences? = nil
    public var physicalFeasibilityVerified: Bool = false

    public static func build(input: HairDesignInput, haircut: HaircutRevision) throws -> Self {
        let validation = try HaircutValidator.validate(input: input, haircut: haircut)
        var regions: [HairRegionExplanation] = []
        for region in HairRegion.allCases {
            let guides = haircut.guides.filter { $0.region == region }
            guard !guides.isEmpty, let limit = input.brief.lengthLimits.first(where: { $0.region == region }) else { continue }
            let lengths = try guides.map { try HaircutValidator.arcLength($0.points) }
            let observation = input.hairProfile.regions.first { $0.region == region }
            let trusted = observation.map {
                [.observed, .userSupplied].contains($0.origin) && [.high, .medium].contains($0.quality)
            } ?? false
            let available = trusted ? observation?.maximumAvailableMeters : nil
            regions.append(HairRegionExplanation(region: region, guideCount: guides.count,
                minimumLengthMeters: lengths.min()!, maximumLengthMeters: lengths.max()!, limit: limit,
                availableLengthMeters: available,
                availableLengthOrigin: available == nil ? .unknown : observation!.origin,
                requiresGrowth: validation.growthRegions.contains(region)))
        }
        return Self(haircutSHA256: validation.haircutSHA256, revision: haircut.revision,
            mode: input.brief.mode, generationOrigin: haircut.generation.origin, regions: regions,
            lastEdit: haircut.edit, stylingAssumptions: input.brief.stylingAssumptions,
            stylingPreferences: input.brief.stylingPreferences)
    }
}
