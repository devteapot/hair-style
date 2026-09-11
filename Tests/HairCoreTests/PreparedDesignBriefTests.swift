import XCTest
@testable import HairCore

final class PreparedDesignBriefTests:XCTestCase {
    func testReplayBindsSourcePreferencesAndRejectsAlteredOutput() throws {
        let (source,_)=try SyntheticHaircut.create()
        let request=DesignBriefRequest(mode:.guided,seed:9,lengthRanges:[.init(region:.fringe,minimumMeters:0.011,maximumMeters:0.05)],
            stylingPreferences:StylingPreferences(allowsHeatTools:false))
        var prepared=try PreparedDesignBrief.prepare(source:source,request:request)
        let input=try prepared.validatedInput(source:source)
        XCTAssertEqual(input.brief.stylingPreferences?.allowsHeatTools,false)
        XCTAssertEqual(input.brief.lengthLimits.first(where:{$0.region == .fringe})?.minimumMeters,0.011)
        var changed=source;changed.brief.seed += 1
        XCTAssertThrowsError(try prepared.validatedInput(source:changed))
        prepared.compiled.input.brief.lengthLimits[0].maximumMeters=1
        XCTAssertThrowsError(try prepared.validatedInput(source:source))
    }
    func testLegacyNativeDocumentStillRequiresReplay() throws {
        let (source,_)=try SyntheticHaircut.create()
        let value=try PreparedDesignBrief.prepare(source:source,request:DesignBriefRequest(mode:.autonomous,seed:1))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:ManifestCoding.encoder().encode(value)) as? [String:Any])
        json.removeValue(forKey:"schemaVersion")
        let legacy=try ManifestCoding.decoder().decode(PreparedDesignBrief.self,from:JSONSerialization.data(withJSONObject:json))
        _=try legacy.validatedInput(source:source)
        json["schemaVersion"]=2
        let unsupported=try ManifestCoding.decoder().decode(PreparedDesignBrief.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertThrowsError(try unsupported.validatedInput(source:source))
    }
}
