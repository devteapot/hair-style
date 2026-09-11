import Foundation
import HairCore

struct HairLabSnapshot: Sendable {
    let selected: StoredHaircut
    let original: StoredHaircut
    let hash: String
    let canUndo: Bool
    let canRedo: Bool
    var observedFace: CanonicalObservedSurface? = nil
    var selectedMesh: CompiledHairMesh? = nil
    var originalMesh: CompiledHairMesh? = nil
    var researchMethod: String? = nil
    var scalpReview: ScalpReviewDocument? = nil
}

/// Serializes selection changes and commits the selection only after its
/// immutable artifact exists. The library repository remains selection-free.
actor HairLabWorker {
    private struct Selection: Codable {
        var id: String
        var original: String
        var selected: String
        var undo: [String]
        var redo: [String]
    }
    private let root: URL
    private let repository: HaircutRepository
    private let modelReview: Bool
    private let expectedOriginal: String?
    private var preparedModel: PreparedModelReview?
    private var packageURL: URL { root.appendingPathComponent("model-review.json") }
    private var pointer: URL { root.appendingPathComponent("selection.json") }
    init(root: URL, modelReview: Bool = false, expectedOriginal: String? = nil) {
        self.root = root
        self.expectedOriginal = expectedOriginal
        self.modelReview = modelReview
        repository = HaircutRepository(root: root.appendingPathComponent("revisions"))
    }
    func restore() throws -> HairLabSnapshot? {
        guard FileManager.default.fileExists(atPath: pointer.path) else { return nil }
        return try snapshot(read())
    }
    func create() throws -> HairLabSnapshot {
        guard !modelReview else { throw CaptureError.invalid("Import a model review package for this studio.") }
        guard !FileManager.default.fileExists(atPath: pointer.path) else { throw CaptureError.invalid("A saved fixture already exists. Reopen it first.") }
        let (input, haircut) = try SyntheticHaircut.create()
        let hash = try repository.save(input: input, haircut: haircut)
        let selection = Selection(id: haircut.id, original: hash, selected: hash, undo: [], redo: [])
        let result = try snapshot(selection)
        try write(selection)
        return result
    }
    func importModel(_ data:Data) throws -> HairLabSnapshot {
        guard modelReview,!FileManager.default.fileExists(atPath:pointer.path),data.count<=100_000_000 else {
            throw CaptureError.invalid("A saved model review already exists, or the package exceeds 100 MB.")
        }
        let package=try ManifestCoding.decoder().decode(ModelReviewPackage.self,from:data)
        let prepared=try package.prepare()
        guard expectedOriginal == nil || expectedOriginal == prepared.mesh.haircutSHA256 else {
            throw CaptureError.invalid("Candidate studio identity differs from this package.")
        }
        try protectRoot()
        try data.write(to:packageURL,options:[.atomic,.completeFileProtection])
        preparedModel=prepared
        let hash=try repository.save(input:prepared.input,haircut:prepared.haircut)
        let selection=Selection(id:prepared.haircut.id,original:hash,selected:hash,undo:[],redo:[])
        let result=try snapshot(selection)
        try write(selection)
        return result
    }
    private func model() throws -> PreparedModelReview {
        if let preparedModel { return preparedModel }
        guard (try packageURL.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<=100_000_000 else {
            throw CaptureError.invalid("Saved model package exceeds 100 MB.")
        }
        let prepared=try ManifestCoding.decoder().decode(ModelReviewPackage.self,from:Data(contentsOf:packageURL)).prepare()
        preparedModel=prepared
        return prepared
    }
    func commit(_ result: HairEditResult, expectedBase: String) throws -> HairLabSnapshot {
        var selection = try read()
        guard selection.selected == expectedBase, result.haircut.parentSHA256 == expectedBase else {
            throw CaptureError.invalid("The selected revision changed. Preview the edit again.")
        }
        let base = try repository.load(id: selection.id, sha256: selection.selected)
        let hash = try repository.save(input: base.input, haircut: result.haircut)
        selection.undo.append(selection.selected); selection.selected = hash; selection.redo = []
        let next = try snapshot(selection)
        try write(selection)
        return next
    }
    func move(undo: Bool, expectedBase: String) throws -> HairLabSnapshot {
        var selection = try read()
        guard selection.selected == expectedBase else { throw CaptureError.invalid("The selected revision changed.") }
        if undo {
            guard let previous = selection.undo.popLast() else { throw CaptureError.invalid("No earlier selection.") }
            selection.redo.append(selection.selected); selection.selected = previous
        } else {
            guard let next = selection.redo.popLast() else { throw CaptureError.invalid("No redo selection.") }
            selection.undo.append(selection.selected); selection.selected = next
        }
        let result = try snapshot(selection)
        try write(selection)
        return result
    }
    func delete() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        preparedModel=nil
    }
    func preparationInputs(preferencesDirectory: URL) throws -> PersonalPreparationInputs {
        guard modelReview else { throw CaptureError.invalid("Personal preparation requires a model review.") }
        let current = try snapshot(read())
        let prepared = try model()
        let source = current.selected.input
        let sourceHash = try HairArtifactHash.digest(source)
        let briefURL = preferencesDirectory.appendingPathComponent(sourceHash+".json")
        let brief: PreparedDesignBrief
        if FileManager.default.fileExists(atPath: briefURL.path) {
            guard (try briefURL.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 25_000_000 else {
                throw CaptureError.invalid("Saved brief exceeds its size limit.")
            }
            brief = try ManifestCoding.decoder().decode(PreparedDesignBrief.self,from:Data(contentsOf:briefURL))
            _ = try brief.validatedInput(source:source)
        } else {
            brief = try PreparedDesignBrief.prepare(source:source,request:DesignBriefRequest(id:source.brief.id,mode:.autonomous,seed:source.brief.seed))
        }
        guard current.selected.haircut.materials.allSatisfy({ $0.radiusMeters <= 0.00005 }) else {
            throw CaptureError.invalid("These guides exceed the preparation stage's material radius.")
        }
        var mapping = prepared.imported.request
        let package = try ManifestCoding.decoder().decode(ModelReviewPackage.self,from:Data(contentsOf:packageURL))
        mapping.sourceArtifactSHA256 = try package.regenerationSampleSHA256()
        mapping.id = current.selected.haircut.id
        guard mapping.mappings.count == current.selected.haircut.guides.count else { throw CaptureError.invalid("Guide correspondence changed.") }
        for index in mapping.mappings.indices {
            let guide = current.selected.haircut.guides[index]
            guard mapping.mappings[index].guideID == guide.id, mapping.mappings[index].region == guide.region else {
                throw CaptureError.invalid("Guide correspondence changed.")
            }
            mapping.mappings[index].binding = guide.root
        }
        mapping.method = "Selected research revision attachment snapshot: \(current.hash). Regeneration uses the original model sample; correspondence still requires replay."
        let face = prepared.observedFace
        let anatomy = GuideClearanceInput(scalpSHA256:current.selected.haircut.scalpSHA256,clearanceMeters:0.001,
            surfaces:[ClearanceSurface(region:.face,origin:.observed,sourceSHA256:try HairArtifactHash.digest(face),
                vertices:face.vertices.map(\.position),triangles:face.triangles)])
        let encoder=ManifestCoding.encoder()
        let inputs = PersonalPreparationInputs(input:try encoder.encode(source),preparedBrief:try encoder.encode(brief),
            mapping:try encoder.encode(mapping),anatomy:try encoder.encode(anatomy))
        _ = try inputs.request()
        return inputs
    }
    private func read() throws -> Selection {
        let data = try Data(contentsOf: pointer)
        guard data.count <= 100_000 else { throw CaptureError.invalid("Saved selection exceeds its size limit.") }
        let selection = try ManifestCoding.decoder().decode(Selection.self, from: data)
        guard selection.undo.count <= 128, selection.redo.count <= 128 else { throw CaptureError.invalid("Saved history is too long.") }
        return selection
    }
    private func snapshot(_ selection: Selection) throws -> HairLabSnapshot {
        let selected = try repository.load(id: selection.id, sha256: selection.selected)
        let original = try repository.load(id: selection.id, sha256: selection.original)
        guard expectedOriginal == nil || selection.original == expectedOriginal else { throw CaptureError.invalid("Candidate studio contains another original revision.") }
        guard original.haircut.revision == 1 else { throw CaptureError.invalid("Saved original is not the initial revision.") }
        var snapshot=HairLabSnapshot(selected:selected,original:original,hash:selection.selected,
            canUndo:!selection.undo.isEmpty,canRedo:!selection.redo.isEmpty)
        if modelReview {
            let prepared=try model()
            guard selection.original==prepared.mesh.haircutSHA256,
                  try HairArtifactHash.digest(selected.input)==HairArtifactHash.digest(prepared.input) else {
                throw CaptureError.invalid("Saved model history no longer matches its source package.")
            }
            snapshot.observedFace=prepared.observedFace
            snapshot.scalpReview=prepared.scalpReview
            snapshot.researchMethod=prepared.researchMethod
            snapshot.originalMesh=prepared.mesh
            snapshot.selectedMesh=selection.selected==selection.original ? prepared.mesh :
                try HairMeshCompiler.compile(input:selected.input,haircut:selected.haircut,radialSides:3,radiusScale:8)
        }
        return snapshot
    }
    private func protectRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        var directory = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
    private func write(_ selection: Selection) throws {
        try protectRoot()
        try ManifestCoding.encoder().encode(selection).write(to: pointer, options: [.atomic, .completeFileProtection])
    }
}

@MainActor
final class HairLabStore: ObservableObject {
    @Published var snapshot: HairLabSnapshot?
    @Published var preview: HairEditResult?
    @Published var previewMesh: CompiledHairMesh?
    @Published var busy = false
    @Published var error: String?
    @Published var preparationInputs: PersonalPreparationInputs?
    private var ticket = 0
    private let worker: HairLabWorker
    private let modelReview: Bool
    init(modelReview: Bool = false, candidate: CandidateStudioID? = nil) {
        self.modelReview=modelReview
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var directory = modelReview ? "ModelHairLab" : "HairLab"
        #if targetEnvironment(simulator)
        if modelReview && ProcessInfo.processInfo.arguments.contains("--conditioned-model-review-test") { directory = "ConditionedModelReviewTest" }
        if modelReview && ProcessInfo.processInfo.arguments.contains("--refined-model-review-test") { directory = "RefinedModelReviewTest" }
        if modelReview && ProcessInfo.processInfo.arguments.contains("--prepared-pipeline-model-review-test") { directory = "PreparedPipelineModelReviewTest" }
        if modelReview && ProcessInfo.processInfo.arguments.contains("--fresh-short-review-test") { directory = "FreshShortModelReviewTest" }
        #endif
        let root=candidate?.directory ?? support.appendingPathComponent(directory)
        worker = HairLabWorker(root:root,modelReview:modelReview,expectedOriginal:candidate?.hash)
        preferencesDirectory=root.appendingPathComponent("preferences")
    }
    let preferencesDirectory: URL
    func prepareGenerationInputs() async {
        guard !busy else { return }
        busy=true;preparationInputs=nil;defer { busy=false }
        do { preparationInputs=try await worker.preparationInputs(preferencesDirectory:preferencesDirectory);error=nil }
        catch { self.error=error.localizedDescription }
    }
    func restore() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { snapshot = try await worker.restore(); preview = nil;previewMesh=nil; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func create() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { snapshot = try await worker.create(); preview = nil; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func importModel(url:URL,consumePrepared:Bool=false) async {
        guard !busy else { return };busy=true;defer {busy=false}
        let access=url.startAccessingSecurityScopedResource()
        defer { if access {url.stopAccessingSecurityScopedResource()} }
        do {
            let data=try await Task.detached {
                guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<=100_000_000 else { throw CaptureError.invalid("Use a model review package smaller than 100 MB.") }
                return try Data(contentsOf:url)
            }.value
            snapshot=try await worker.importModel(data);preview=nil;previewMesh=nil;error=nil
            if consumePrepared { try FileManager.default.removeItem(at:url) }
        } catch { self.error=error.localizedDescription }
    }
    func preview(operation: HairEditOperation, region: HairRegion, value: Double) async {
        guard !busy, let base = snapshot else { return }
        busy=true;defer {busy=false}
        ticket += 1; let request = ticket
        preview = nil; previewMesh=nil; error = nil
        let edit = HairEdit(baseSHA256: base.hash, operation: operation, region: region, value: value)
        do {
            let usesModel=modelReview
            let (result,mesh) = try await Task.detached {
                let anatomy = try base.observedFace.map { face in
                    GuideClearanceInput(scalpSHA256: base.selected.haircut.scalpSHA256, clearanceMeters: 0.001,
                        surfaces: [ClearanceSurface(region: .face, origin: .observed,
                            sourceSHA256: try HairArtifactHash.digest(face), vertices: face.vertices.map(\.position), triangles: face.triangles)])
                }
                let result=try HaircutEditor.apply(edit,to:base.selected.haircut,input:base.selected.input,anatomy:anatomy)
                let mesh=usesModel ? try HairMeshCompiler.compile(input:base.selected.input,haircut:result.haircut,radialSides:3,radiusScale:8) : nil
                return (result,mesh)
            }.value
            guard ticket == request, snapshot?.hash == base.hash else { return }
            preview = result;previewMesh=mesh
        } catch {
            guard ticket == request else { return }
            self.error = error.localizedDescription
        }
    }
    func discard() { ticket += 1; preview = nil;previewMesh=nil; error = nil }
    func save() async {
        guard !busy, let preview, let base = snapshot else { return }
        ticket += 1; busy = true; defer { busy = false }
        do { snapshot = try await worker.commit(preview, expectedBase: base.hash); self.preview = nil;previewMesh=nil; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func move(undo: Bool) async {
        guard !busy, let base = snapshot else { return }
        ticket += 1; busy = true; defer { busy = false }
        do { snapshot = try await worker.move(undo: undo, expectedBase: base.hash); preview = nil;previewMesh=nil; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func delete() async {
        guard !busy else { return }; ticket += 1; busy = true; defer { busy = false }
        do { try await worker.delete(); snapshot = nil; preview = nil;previewMesh=nil; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

/// Only canonical SHA-256 identifiers can address a candidate studio.
struct CandidateStudioID: Identifiable, Hashable, Sendable {
    let hash: String
    var id: String { hash }
    init(_ hash: String) throws {
        guard hash.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw CaptureError.invalid("Invalid candidate studio identity.") }
        self.hash=hash
    }
    static var library: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("CandidateStudios")
    }
    var directory: URL { Self.library.appendingPathComponent(hash) }
    static func save(_ package: ModelReviewPackage) async throws -> Self {
        let prepared=try await Task.detached { try package.prepare() }.value
        let identity=try Self(prepared.mesh.haircutSHA256)
        let worker=HairLabWorker(root:identity.directory,modelReview:true,expectedOriginal:identity.hash)
        if try await worker.restore() == nil {
            let data=try await Task.detached { try ManifestCoding.encoder().encode(package) }.value
            _=try await worker.importModel(data)
        }
        return identity
    }
}
