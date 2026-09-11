import XCTest
@testable import HairCore

final class HairImageAnalysisTests: XCTestCase {
    func testSavedReviewRoundTripAndMismatchRejection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try SyntheticCapture.create(in: root)
        let manifest = try CaptureBundle.load(bundle)
        let frame = manifest.frames[0]
        let value = HairImageAnalysis(schemaVersion: 1, method: "local_segformer_hair_image_v1",
            captureID: manifest.id, frameID: frame.metadata.id,
            sourceManifestSHA256: EvidenceHash.sha256(try Data(contentsOf: bundle.appendingPathComponent("manifest.json"))),
            imageSHA256: frame.image.sha256, imageSize: frame.metadata.imageSize,
            captureCondition: .unknown, captureConditionSource: "unknown",
            observation: .init(hairPixels: 500, interiorPixels: 200,
                recordedColor: .init(space: "recorded_rgb_uint8", sampleCount: 200, median: [20, 30, 40], intrinsicColorCalibrated: false),
                semanticAccuracyValidated: false),
            textureOrientation: .init(supportedPixels: 80, directed: false, rootToTipMeasured: false, accuracyValidated: false),
            acceptedForNaturalHairBaseline: false, registeredToHead: false)
        let data = try JSONEncoder().encode(value)
        _ = try HairImageAnalysis.save(data, bundle: bundle, frameID: frame.metadata.id)
        let loaded = try XCTUnwrap(HairImageAnalysis.load(bundle: bundle, frameID: frame.metadata.id))
        XCTAssertEqual(loaded.observation.recordedColor?.median, [20, 30, 40])
        XCTAssertTrue(try CaptureBundle.inspect(bundle).valid)
        XCTAssertThrowsError(try HairImageAnalysis.validated(data, bundle: bundle, frameID: manifest.frames[1].metadata.id))
        var invalid = value
        invalid.observation.recordedColor?.median = [300, 0, 0]
        XCTAssertThrowsError(try HairImageAnalysis.validated(JSONEncoder().encode(invalid), bundle: bundle, frameID: frame.metadata.id))
        invalid = value; invalid.textureOrientation?.rootToTipMeasured = true
        XCTAssertThrowsError(try HairImageAnalysis.validated(JSONEncoder().encode(invalid), bundle: bundle, frameID: frame.metadata.id))
        invalid = value; invalid.captureConditionSource = "participant_declaration"; invalid.captureCondition = .untied
        XCTAssertThrowsError(try HairImageAnalysis.validated(JSONEncoder().encode(invalid), bundle: bundle, frameID: frame.metadata.id))
        var changed = manifest; changed.notes.append("Capture revised")
        try ManifestCoding.encoder().encode(changed).write(to: bundle.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try HairImageAnalysis.load(bundle: bundle, frameID: frame.metadata.id))
    }
}
