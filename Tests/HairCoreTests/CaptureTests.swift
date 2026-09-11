import XCTest
@testable import HairCore

final class CaptureTests: XCTestCase {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testFloatEncodingPreservesInvalidSamplesAndLittleEndian() throws {
        let data = DepthGeometry.encode([1, .nan, .infinity, -1])
        XCTAssertEqual(Array(data.prefix(4)), [0, 0, 128, 63])
        let values = try DepthGeometry.decode(data, size: PixelSize(2, 2))
        XCTAssertEqual(values[0], 1)
        XCTAssertTrue(values[1].isNaN)
        XCTAssertTrue(values[2].isInfinite)
        XCTAssertEqual(DepthGeometry.quality(values).fraction, 0.25)
        XCTAssertThrowsError(try DepthGeometry.decode(data, size: PixelSize(3, 2)))
    }

    func testProjectionScalingAndCameraTransformAreNotMirrored() throws {
        let k = Intrinsics(fx: 4, fy: 4, cx: 2, cy: 2, referenceSize: PixelSize(4, 4))
        let transform = RigidTransform(rowMajor: [1,0,0,2, 0,-1,0,3, 0,0,-1,4, 0,0,0,1])
        XCTAssertTrue(transform.isValid)
        let points = try DepthGeometry.pointCloud(values: [1,1,1,1], size: PixelSize(2,2), intrinsics: k, worldFromCamera: transform)
        XCTAssertEqual(points[0], Point3D(x: 1.5, y: 3.5, z: 3))
        XCTAssertEqual(points[3], Point3D(x: 2, y: 3, z: 3))
        let reflection = RigidTransform(rowMajor: [-1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1])
        XCTAssertFalse(reflection.isValid)
        XCTAssertThrowsError(try DepthGeometry.pointCloud(values: [1], size: PixelSize(1,1), intrinsics: k, worldFromCamera: reflection))
    }

    func testFixtureRoundTripAndTamperingIsRejected() throws {
        let root = try temporaryDirectory()
        let bundle = try SyntheticCapture.create(in: root)
        let report = try CaptureBundle.inspect(bundle)
        XCTAssertTrue(report.valid)
        XCTAssertEqual(report.frameCount, 3)
        XCTAssertEqual(report.depthFrameCount, 3)
        XCTAssertEqual(report.source, .syntheticFixture)
        let manifest = try CaptureBundle.load(bundle)
        let evidence = try XCTUnwrap(manifest.frames[0].depth)
        var payload = try CaptureBundle.payload(evidence, in: bundle)
        payload[0] ^= 0xff
        try payload.write(to: bundle.appendingPathComponent(evidence.path))
        XCTAssertFalse(try CaptureBundle.inspect(bundle).valid)
    }

    func testPathTraversalAndSymlinkEscapeAreRejected() throws {
        let root = try temporaryDirectory()
        let evidence = FileEvidence(path: "../../private", byteCount: 1, sha256: "")
        XCTAssertThrowsError(try CaptureBundle.payload(evidence, in: root))
        let bundle = try SyntheticCapture.create(in: root)
        let image = try CaptureBundle.load(bundle).frames[0].image
        let original = bundle.appendingPathComponent(image.path)
        let external = root.appendingPathComponent("external.jpg")
        try FileManager.default.moveItem(at: original, to: external)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: external)
        XCTAssertThrowsError(try CaptureBundle.payload(image, in: bundle))
    }

    func testInterruptedAndEmptyCaptureCannotPass() throws {
        let root = try temporaryDirectory()
        let report = DeviceReport(model: "test", osVersion: "test", build: "test", hasTrueDepth: false,
            hasRearSceneDepth: false, hasFaceTracking: false, isSimulator: true)
        let writer = try CaptureBundleWriter(root: root, subjectSessionID: "test", kind: .frontFace,
            source: .syntheticFixture, device: report, consentVersion: "test")
        try writer.finish()
        XCTAssertEqual(writer.manifest.status, .interrupted)
        XCTAssertFalse(try CaptureBundle.inspect(writer.url).valid)
        XCTAssertThrowsError(try writer.append(metadata: FrameMetadata(imageTimestamp: 1, imageSize: PixelSize(1,1)), imageJPEG: Data([0])))
    }

    func testUnknownHeadPoseIsNotMisrepresented() throws {
        var m = FrameMetadata(imageTimestamp: 1, imageSize: PixelSize(1,1))
        XCTAssertNil(m.worldFromOpticalCamera)
        XCTAssertFalse(m.quality.headPoseAvailable)
        m.quality.headPoseAvailable = true
        XCTAssertThrowsError(try CaptureBundle.validate(m))
    }

    func testUnsupportedSchemaAndInvalidDepthCalibrationFail() throws {
        let root = try temporaryDirectory()
        let bundle = try SyntheticCapture.create(in: root)
        var manifest = try CaptureBundle.load(bundle)
        manifest.schemaVersion = 999
        try ManifestCoding.encoder().encode(manifest).write(to: bundle.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try CaptureBundle.load(bundle))
        let m = FrameMetadata(imageTimestamp: 1, depthTimestamp: 1, imageSize: PixelSize(1,1), depthSize: PixelSize(1,1))
        XCTAssertThrowsError(try CaptureBundle.validate(m))
    }

    func testCancelledExportDoesNotLeaveAnArchive() async throws {
        let root = try temporaryDirectory()
        let bundle = try SyntheticCapture.create(in: root)
        let archive = root.appendingPathComponent("cancelled.zip")
        let job = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            try CaptureArchive.export(bundle: bundle, to: archive)
        }
        do { try await job.value; XCTFail("Cancelled export must fail") }
        catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertTrue(try CaptureBundle.inspect(bundle).valid)
    }

    #if os(macOS)
    func testArchiveCanBeUnzippedAndIndependentlyValidated() throws {
        let root = try temporaryDirectory()
        let bundle = try SyntheticCapture.create(in: root)
        let archive = root.appendingPathComponent("capture.zip")
        try CaptureArchive.export(bundle: bundle, to: archive)
        XCTAssertThrowsError(try CaptureArchive.export(bundle: bundle, to: archive))
        let extracted = root.appendingPathComponent("extracted")
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", archive.path, "-d", extracted.path]
        try unzip.run(); unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0)
        let report = try CaptureBundle.inspect(extracted)
        XCTAssertTrue(report.valid)
        XCTAssertEqual(report.frameCount, 3)
    }
    #endif
}
