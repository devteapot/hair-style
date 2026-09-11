import XCTest
@testable import HairCore

final class LivePackageTests: XCTestCase {
    func testRecordedColorRevisionSurvivesLiveHandoffExactly() throws {
        var value = try package()
        let baseHash = try HairArtifactHash.digest(value.haircut)
        let color = RecordedHairColor(subjectSessionID: value.input.scalp.subjectSessionID,
            captureID: UUID().uuidString, frameID: UUID().uuidString,
            reportSHA256: String(repeating: "a", count: 64), imageSHA256: String(repeating: "b", count: 64), rgb: [20, 30, 40])
        value.haircut = try HaircutEditor.apply(HairEdit(baseSHA256: baseHash, operation: .matchRecordedColor,
            region: .fringe, value: 0, recordedColor: color), to: value.haircut, input: value.input).haircut
        value.meshSettings = .modelReview
        let decoded = try ManifestCoding.decoder().decode(LivePreviewPackage.self, from: ManifestCoding.encoder().encode(value))
        let live = try decoded.prepareMesh()
        let studio = try HairMeshCompiler.compile(input: value.input, haircut: value.haircut, radialSides: 3, radiusScale: 8)
        XCTAssertNotEqual(live.haircutSHA256, baseHash)
        XCTAssertEqual(try HairArtifactHash.digest(live), try HairArtifactHash.digest(studio))
        XCTAssertEqual(decoded.haircut.edit?.recordedColor?.reportSHA256, color.reportSHA256)
        XCTAssertEqual(decoded.haircut.edit?.recordedColor?.rgb, color.rgb)
    }

    func testRibbonPackageRoundTripMatchesInteractiveCompiler() throws {
        var value=try package();value.meshSettings = .init(radialSides:3,radiusScale:8,representation:.ribbon)
        let restored=try ManifestCoding.decoder().decode(LivePreviewPackage.self,from:ManifestCoding.encoder().encode(value))
        let live=try restored.prepareMesh()
        let interactive=try HairRibbonCompiler.compile(input:value.input,haircut:value.haircut,radiusScale:8)
        XCTAssertEqual(try HairArtifactHash.digest(live),try HairArtifactHash.digest(interactive))
        XCTAssertEqual(live.haircutSHA256,try HairArtifactHash.digest(value.haircut))
        let legacy=try ManifestCoding.decoder().decode(LiveMeshSettings.self,from:Data("{\"radialSides\":3,\"radiusScale\":8}".utf8))
        XCTAssertNil(legacy.representation)
    }
    private func package() throws -> LivePreviewPackage {
        let (input, haircut) = try SyntheticHaircut.create()
        let positions = [(-0.08,-0.08),(0.08,-0.08),(-0.08,0.08),(0.08,0.08),(-0.03,-0.02),(0.04,-0.01),(0.0,0.05)]
        let landmarks = positions.enumerated().map {
            LiveLandmarkSelection(id: "p\($0.offset)", canonicalPoint: Point3D(x: $0.element.0,y: 0.1,z: $0.element.1), faceVertexIndex: $0.offset)
        }
        return LivePreviewPackage(input: input, haircut: haircut, fitLandmarks: Array(landmarks.prefix(4)), validationLandmarks: Array(landmarks.suffix(3)))
    }
    func testPackageRoundTripRetainsExactRenderedRevision() throws {
        let package = try package()
        let decoded = try ManifestCoding.decoder().decode(LivePreviewPackage.self, from: ManifestCoding.encoder().encode(package))
        let mesh = try decoded.prepareMesh()
        XCTAssertEqual(mesh.haircutSHA256, try HairArtifactHash.digest(package.haircut))
        XCTAssertEqual(mesh.radiusScale, 1)
    }
    func testDirectionRevisionCompilesIdenticallyForLiveAndInteractivePreview() throws {
        var value=try package()
        value.meshSettings = .modelReview
        let original=try HairArtifactHash.digest(value.haircut)
        let edit=HairEdit(baseSHA256:original,operation:.rotateAroundRootNormal,region:.fringe,value:30)
        value.haircut=try HaircutEditor.apply(edit,to:value.haircut,input:value.input).haircut
        let decoded=try ManifestCoding.decoder().decode(LivePreviewPackage.self,from:ManifestCoding.encoder().encode(value))
        let live=try decoded.prepareMesh()
        let interactive=try HairMeshCompiler.compile(input:value.input,haircut:value.haircut,radialSides:3,radiusScale:8)
        XCTAssertNotEqual(live.haircutSHA256,original)
        XCTAssertEqual(live.haircutSHA256,interactive.haircutSHA256)
        XCTAssertEqual(try HairArtifactHash.digest(live),try HairArtifactHash.digest(interactive))
        XCTAssertEqual(decoded.haircut.edit?.operation,.rotateAroundRootNormal)
        XCTAssertEqual(decoded.haircut.edit?.value,30)
    }

    func testRejectsDuplicateDegenerateAndNonfiniteSelectionsAndStaleHaircut() throws {
        var value = try package()
        value.validationLandmarks[0].faceVertexIndex = value.fitLandmarks[0].faceVertexIndex
        XCTAssertThrowsError(try value.prepareMesh())
        value = try package(); value.fitLandmarks[0].canonicalPoint.x = .nan
        XCTAssertThrowsError(try value.prepareMesh())
        value = try package(); value.validationLandmarks[0].canonicalPoint = value.fitLandmarks[0].canonicalPoint
        XCTAssertThrowsError(try value.prepareMesh())
        value = try package(); value.haircut.scalpSHA256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try value.prepareMesh())
    }
}
