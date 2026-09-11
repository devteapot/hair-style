import Foundation

public struct RequestedLengthRange: Codable, Sendable {
    public var region: HairRegion
    public var minimumMeters: Double
    public var maximumMeters: Double
    public init(region: HairRegion, minimumMeters: Double, maximumMeters: Double) {
        self.region = region; self.minimumMeters = minimumMeters; self.maximumMeters = maximumMeters
    }
}

/// Typed preferences are also the boundary for a future language-model adapter.
/// Descriptive text never overrides these constraints.
public struct DesignBriefRequest: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var id: String
    public var mode: DesignMode
    public var seed: UInt64
    public var allowGrowth: Bool?
    public var lengthRanges: [RequestedLengthRange]
    public var stylingPreferences: StylingPreferences? = nil
    public init(id: String = UUID().uuidString, mode: DesignMode, seed: UInt64,
                allowGrowth: Bool? = nil, lengthRanges: [RequestedLengthRange] = [], stylingPreferences: StylingPreferences? = nil) {
        self.id = id; self.mode = mode; self.seed = seed
        self.allowGrowth = allowGrowth; self.lengthRanges = lengthRanges
        self.stylingPreferences=stylingPreferences
    }
}

public struct BriefRegionDecision: Codable, Sendable {
    public var region: HairRegion
    public var requestedRange: RequestedLengthRange?
    public var appliedLimit: RegionalLengthLimit
    public var availableLengthUsedMeters: Double?
    public var availabilityUncertain: Bool
    public var growthPossibleWithinRange: Bool
}

public struct CompiledDesignBrief: Codable, Sendable {
    public var method: String = "regional_length_brief_v1"
    public var requestSHA256: String
    public var input: HairDesignInput
    public var decisions: [BriefRegionDecision]
    /// Policy defaults, not observed personal preferences or styling requirements.
    public var designDefaults: [String]
    public var unresolved: [String]
    public var personalizedGenerationVerified: Bool = false
}

public enum DesignBriefCompiler {
    public static func compile(scalp: ScalpProfile, profile: HairLengthProfile,
                               request: DesignBriefRequest) throws -> CompiledDesignBrief {
        guard request.schemaVersion == 1, UUID(uuidString: request.id) != nil,
              request.lengthRanges.count <= HairRegion.allCases.count else {
            throw CaptureError.invalid("Invalid brief request identity, version or region count.")
        }
        try request.stylingPreferences?.validate()
        guard request.mode == .guided || (request.lengthRanges.isEmpty && request.allowGrowth == nil && request.stylingPreferences == nil) else {
            throw CaptureError.invalid("Explicit preferences require guided mode.")
        }
        var requested: [HairRegion: RequestedLengthRange] = [:]
        for range in request.lengthRanges {
            guard requested[range.region] == nil, range.minimumMeters.isFinite, range.maximumMeters.isFinite,
                  range.minimumMeters >= 0.001, range.maximumMeters <= 1.5,
                  range.minimumMeters <= range.maximumMeters else {
                throw CaptureError.invalid("Invalid or duplicate requested length range.")
            }
            requested[range.region] = range
        }
        let allowGrowth = request.allowGrowth ?? false
        // Broad representational bounds are not a recommended style or measured length.
        var brief = HairDesignBrief(id: request.id, scalpSHA256: try HairArtifactHash.digest(scalp),
            hairProfileSHA256: try HairArtifactHash.digest(profile), mode: request.mode,
            lengthLimits: HairRegion.allCases.map {
                RegionalLengthLimit(region: $0, minimumMeters: 0.001, maximumMeters: 1.5, origin: .defaultValue)
            }, allowGrowth: allowGrowth, stylingAssumptions: [], seed: request.seed)
        try HaircutValidator.validateInput(HairDesignInput(scalp: scalp, hairProfile: profile, brief: brief))
        let observations = Dictionary(uniqueKeysWithValues: profile.regions.map { ($0.region, $0) })
        var decisions: [BriefRegionDecision] = []
        for region in HairRegion.allCases {
            let preference = requested[region], observation = observations[region]
            let reliable = observation.map {
                [.observed, .userSupplied].contains($0.origin) && [.high, .medium].contains($0.quality)
            } ?? false
            let available = reliable ? observation?.maximumAvailableMeters : nil
            let minimum = preference?.minimumMeters ?? 0.001
            var maximum = preference?.maximumMeters ?? 1.5
            var origin: ObservationOrigin = preference == nil ? .defaultValue : .userSupplied
            if !allowGrowth, let available {
                guard minimum <= available else {
                    throw CaptureError.invalid("Requested minimum in \(region.rawValue) exceeds recorded length. Change the range or explicitly allow growth.")
                }
                if maximum > available {
                    maximum = available
                    if preference == nil { origin = observation!.origin }
                }
            }
            let limit = RegionalLengthLimit(region: region, minimumMeters: minimum,
                                             maximumMeters: maximum, origin: origin)
            decisions.append(BriefRegionDecision(region: region, requestedRange: preference,
                appliedLimit: limit, availableLengthUsedMeters: available, availabilityUncertain: available == nil,
                growthPossibleWithinRange: available.map { maximum > $0 } ?? false))
        }
        brief.lengthLimits = decisions.map(\.appliedLimit)
        brief.stylingPreferences=request.stylingPreferences
        let input = HairDesignInput(scalp: scalp, hairProfile: profile, brief: brief)
        try HaircutValidator.validateInput(input)
        return CompiledDesignBrief(requestSHA256: try HairArtifactHash.digest(request), input: input,
            decisions: decisions, designDefaults: ["preserve_natural_color", "no_assumed_extensions_or_chemical_treatment"]
                + (request.stylingPreferences?.preserveNaturalTexture == nil ? ["preserve_natural_texture"] : [])
                + (request.stylingPreferences?.maximumDailyMinutes == nil ? ["low_to_moderate_daily_styling"] : []),
            unresolved: ["hairline_flow_texture_conditioning", "aesthetic_proposal_generation",
                         "physical_feasibility"] + (decisions.contains { $0.availabilityUncertain } ? ["uncertain_current_lengths"] : [])
                + (request.stylingPreferences == nil ? [] : ["requested_styling_constraints_unverified"]))
    }
}
