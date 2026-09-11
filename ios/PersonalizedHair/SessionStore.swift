import Foundation
import HairCore

struct SavedPass: Identifiable {
    let url: URL
    let manifest: CaptureManifest
    var id: String { manifest.id }
}

@MainActor
final class SessionStore: ObservableObject {
    let root: URL
    @Published var passes: [SavedPass] = []
    @Published var error: String?
    let subjectSessionID: String

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Captures", isDirectory: true)
        let key = "subjectSessionID"
        subjectSessionID = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
        UserDefaults.standard.set(subjectSessionID, forKey: key)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try TemporaryExportCleanup.removeAbandonedExports(in: FileManager.default.temporaryDirectory)
        }
        catch { self.error = error.localizedDescription }
        reload()
    }

    func reload() {
        do {
            passes = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.first != "." }
                .compactMap { url in
                    do { return SavedPass(url: url, manifest: try CaptureBundle.load(url)) }
                    catch { self.error = "Some capture folders could not be read. They remain in Files for recovery."; return nil }
                }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func delete(_ pass: SavedPass) -> Bool {
        do { try FileManager.default.removeItem(at: pass.url); reload(); return true }
        catch { self.error = error.localizedDescription; return false }
    }

    func addFixture() async {
        do {
            let captureRoot = root
            let fixtureURL = try await Task.detached { try SyntheticCapture.create(in: captureRoot) }.value
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--hair-analysis-review-test") {
                let manifestData = try Data(contentsOf: fixtureURL.appendingPathComponent("manifest.json"))
                let manifest = try CaptureBundle.load(fixtureURL)
                let frame = manifest.frames[0]
                let report: [String: Any] = [
                    "schemaVersion": 1, "method": "local_segformer_hair_image_v1",
                    "captureID": manifest.id, "frameID": frame.metadata.id,
                    "sourceManifestSHA256": EvidenceHash.sha256(manifestData), "imageSHA256": frame.image.sha256,
                    "imageSize": ["width": frame.metadata.imageSize.width, "height": frame.metadata.imageSize.height],
                    "captureCondition": "unknown", "captureConditionSource": "unknown",
                    "observation": ["hairPixels": 500, "interiorPixels": 200, "semanticAccuracyValidated": false,
                        "recordedColor": ["space": "recorded_rgb_uint8", "sampleCount": 200,
                            "median": [20, 30, 40], "intrinsicColorCalibrated": false]],
                    "acceptedForNaturalHairBaseline": false, "registeredToHead": false]
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try JSONSerialization.data(withJSONObject: report).write(to: documents.appendingPathComponent("Hair analysis fixture.json"), options: .atomic)
            }
            #endif
            reload()
        } catch { self.error = error.localizedDescription }
    }
}

extension CaptureKind {
    var title: String {
        switch self {
        case .frontFace: return "Face details"
        case .rearHead: return "Around your head"
        case .naturalHair: return "Your natural hair"
        case .detail: return "A closer look"
        }
    }
    var symbol: String {
        switch self {
        case .frontFace: return "faceid"
        case .rearHead: return "view.3d"
        case .naturalHair: return "person.crop.square"
        case .detail: return "viewfinder"
        }
    }
    var guidance: String {
        switch self {
        case .frontFace: return "Pin your hair back with your forehead and ears visible. Hold the phone at face height. Slowly look left, right, up and down, keeping a relaxed expression."
        case .rearHead: return "Stay seated with your hair pinned back. Ask someone to move slowly around you, including both ears, the crown and the back of your head. Keep your head still."
        case .naturalHair: return "Release your hair and let it settle into its usual dry shape. Ask someone to capture the front, sides, back and crown."
        case .detail: return "Capture a clear view of your hairline, temples or crown. Use soft light and avoid pulling your hair tightly."
        }
    }
}
