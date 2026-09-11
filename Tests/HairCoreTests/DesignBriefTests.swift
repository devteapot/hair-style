import XCTest
@testable import HairCore

final class DesignBriefTests: XCTestCase {
    func testStylingPreferencesRemainExplicitUnverifiedAndHashBound() throws {
        let (input,_) = try SyntheticHaircut.create()
        var request=DesignBriefRequest(mode:.guided,seed:7,stylingPreferences:StylingPreferences(
            maximumDailyMinutes:0,allowsHeatTools:false,allowsStylingProducts:false))
        let result=try DesignBriefCompiler.compile(scalp:input.scalp,profile:input.hairProfile,request:request)
        XCTAssertEqual(result.input.brief.stylingPreferences,request.stylingPreferences)
        XCTAssertNil(result.input.brief.stylingPreferences?.preserveNaturalTexture)
        XCTAssertTrue(result.unresolved.contains("requested_styling_constraints_unverified"))
        XCTAssertFalse(result.designDefaults.contains("low_to_moderate_daily_styling"))
        XCTAssertTrue(result.designDefaults.contains("preserve_natural_texture"))
        var changed=result.input;changed.brief.stylingPreferences?.allowsHeatTools=true
        XCTAssertNotEqual(try HairArtifactHash.digest(result.input.brief),try HairArtifactHash.digest(changed.brief))
        let data=try ManifestCoding.encoder().encode(result.input)
        XCTAssertEqual(try ManifestCoding.decoder().decode(HairDesignInput.self,from:data).brief.stylingPreferences,request.stylingPreferences)
        request.mode = .autonomous
        XCTAssertThrowsError(try DesignBriefCompiler.compile(scalp:input.scalp,profile:input.hairProfile,request:request))
        XCTAssertThrowsError(try StylingPreferences().validate())
        XCTAssertThrowsError(try StylingPreferences(maximumDailyMinutes:-1).validate())
    }

    func testAutonomousUsesEvidenceWithoutInventingMissingLengths() throws {
        let (input, _) = try SyntheticHaircut.create()
        let request = DesignBriefRequest(mode: .autonomous, seed: 7)
        let result = try DesignBriefCompiler.compile(scalp: input.scalp, profile: input.hairProfile, request: request)
        XCTAssertEqual(result.decisions.count, 6)
        let crown = try XCTUnwrap(result.decisions.first { $0.region == .crown })
        XCTAssertEqual(crown.appliedLimit.maximumMeters, 0.2)
        XCTAssertFalse(crown.availabilityUncertain)
        let fringe = try XCTUnwrap(result.decisions.first { $0.region == .fringe })
        XCTAssertTrue(fringe.availabilityUncertain)
        XCTAssertNil(fringe.availableLengthUsedMeters)
        XCTAssertEqual(fringe.appliedLimit.origin, .defaultValue)
        XCTAssertTrue(result.input.brief.stylingAssumptions.isEmpty)
        XCTAssertFalse(result.personalizedGenerationVerified)
        let repeated = try DesignBriefCompiler.compile(scalp: input.scalp, profile: input.hairProfile, request: request)
        XCTAssertEqual(try HairArtifactHash.digest(result), try HairArtifactHash.digest(repeated))
    }

    func testGuidedIntersectionGrowthConflictAndEvidenceQuality() throws {
        var (input, _) = try SyntheticHaircut.create()
        var request = DesignBriefRequest(mode: .guided, seed: 9,
            lengthRanges: [.init(region: .crown, minimumMeters: 0.1, maximumMeters: 0.3)])
        var result = try DesignBriefCompiler.compile(scalp: input.scalp, profile: input.hairProfile, request: request)
        XCTAssertEqual(result.decisions.first { $0.region == .crown }?.appliedLimit.maximumMeters, 0.2)
        request.lengthRanges[0].minimumMeters = 0.25
        XCTAssertThrowsError(try DesignBriefCompiler.compile(scalp: input.scalp, profile: input.hairProfile, request: request))
        request.allowGrowth = true
        result = try DesignBriefCompiler.compile(scalp: input.scalp, profile: input.hairProfile, request: request)
        XCTAssertEqual(result.decisions.first { $0.region == .crown }?.growthPossibleWithinRange, true)
        input.hairProfile.regions[1].quality = .low
        request.allowGrowth = false
        result = try DesignBriefCompiler.compile(scalp: input.scalp, profile: input.hairProfile, request: request)
        XCTAssertEqual(result.decisions.first { $0.region == .crown }?.availabilityUncertain, true)
        XCTAssertEqual(result.decisions.first { $0.region == .crown }?.appliedLimit.maximumMeters, 0.3)
    }

    func testRejectsDuplicatePreferencesForeignProfileAndAutonomousOverrides() throws {
        var (input, _) = try SyntheticHaircut.create()
        let range = RequestedLengthRange(region: .fringe, minimumMeters: 0.01, maximumMeters: 0.1)
        var request = DesignBriefRequest(mode: .guided, seed: 1, lengthRanges: [range, range])
        XCTAssertThrowsError(try DesignBriefCompiler.compile(scalp: input.scalp, profile: input.hairProfile, request: request))
        request.lengthRanges = [range]; request.mode = .autonomous
        XCTAssertThrowsError(try DesignBriefCompiler.compile(scalp: input.scalp, profile: input.hairProfile, request: request))
        request.lengthRanges = []; input.hairProfile.subjectSessionID = "another-person"
        XCTAssertThrowsError(try DesignBriefCompiler.compile(scalp: input.scalp, profile: input.hairProfile, request: request))
    }
}
