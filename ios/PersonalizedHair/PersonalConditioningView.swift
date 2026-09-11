import SwiftUI
import HairCore

@MainActor
private final class PersonalConditioningModel: ObservableObject {
    struct Saved: Codable {
        var sourceHash: String
        var preparationJob: String
        var requestKey: String
        var inputs: PersonalConditioningInputs?
        var session: String?
        var job: String?
        var jobState: String?
        var status = "Ready to create a research candidate"
        var cancellationPending = false
        var outputSHA256: String?
    }
    @Published var saved: Saved?
    @Published var result: ProcessingConditioningResult?
    @Published var busy = false
    @Published var error: String?
    let source: StoredHaircut
    let inputs: PersonalPreparationInputs
    let endpoint: URL
    let preparationJob: String
    private var directory: URL {
        let key=EvidenceHash.sha256(Data((endpoint.absoluteString+"/"+preparationJob).utf8))
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("PersonalConditioning/"+key)
    }
    init(source:StoredHaircut,inputs:PersonalPreparationInputs,endpoint:URL,preparationJob:String) {
        self.source=source;self.inputs=inputs;self.endpoint=endpoint;self.preparationJob=preparationJob
    }
    private func persist(_ value:Saved) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
            attributes:[.protectionKey:FileProtectionType.complete])
        var url=directory;var values=URLResourceValues();values.isExcludedFromBackup=true;try url.setResourceValues(values)
        let data=try ManifestCoding.encoder().encode(value)
        guard data.count<=100_000_000 else { throw CaptureError.invalid("Candidate state exceeds its storage limit.") }
        try data.write(to:directory.appendingPathComponent("state.json"),options:[.atomic,.completeFileProtection])
        saved=value
    }
    func restore() async {
        guard !busy,FileManager.default.fileExists(atPath:directory.appendingPathComponent("state.json").path) else { return }
        busy=true;defer { busy=false }
        do {
            let directory=directory,inputs=inputs,source=source,preparationJob=preparationJob
            let restored=try await Task.detached { () throws -> (Saved,ProcessingConditioningResult?,String?) in
                let stateFile=directory.appendingPathComponent("state.json")
                guard (try stateFile.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<=100_000_000 else { throw CaptureError.invalid("Saved candidate state is too large.") }
                let value=try ManifestCoding.decoder().decode(Saved.self,from:Data(contentsOf:stateFile))
                guard value.preparationJob==preparationJob, value.sourceHash == (try HairArtifactHash.digest(source.haircut)) else {
                    throw CaptureError.invalid("Saved candidate belongs to another preparation or source revision.")
                }
                if let context=value.inputs {
                    guard try context.preparationInputs.request()==inputs.request() else { throw CaptureError.invalid("Saved candidate inputs changed.") }
                    _=try context.request()
                }
                var result:ProcessingConditioningResult?
                var cacheError:String?
                if let hash=value.outputSHA256 {
                    guard let context=value.inputs else { throw CaptureError.invalid("Saved candidate inputs are missing.") }
                    do {
                        let file=directory.appendingPathComponent("result.json")
                        guard (try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<=100_000_000 else { throw CaptureError.invalid("Saved candidate is too large.") }
                        result=try ProcessingConditioningResult.verify(data:Data(contentsOf:file),outputSHA256:hash,inputs:context)
                    } catch { cacheError="Saved candidate could not be verified. Refresh to retrieve it again, or delete it. "+error.localizedDescription }
                }
                return (value,result,cacheError)
            }.value
            saved=restored.0;result=restored.1;error=restored.2
        } catch { self.error=error.localizedDescription }
    }
    private func connection() throws -> ProcessingClient {
        guard let credential=try ProcessingCredentialStore().load(endpoint:endpoint) else {
            throw CaptureError.invalid("The preparation service credential is unavailable.")
        }
        return try ProcessingClient(baseURL:endpoint,credential:credential)
    }
    func advance(allowStart:Bool=false) async {
        if saved?.cancellationPending == true { await cancel();return }
        guard !busy, saved != nil || allowStart else { return }
        busy=true;defer { busy=false }
        var client:ProcessingClient?
        do {
            var value:Saved
            if let saved { value=saved }
            else {
                guard !FileManager.default.fileExists(atPath:directory.appendingPathComponent("state.json").path) else {
                    throw CaptureError.invalid("Existing candidate state could not be restored; it has not been overwritten.")
                }
                value=Saved(sourceHash:try HairArtifactHash.digest(source.haircut),preparationJob:preparationJob,requestKey:UUID().uuidString)
                try persist(value)
            }
            let api=try connection();client=api
            if value.inputs == nil {
                let mapping=try ManifestCoding.decoder().decode(ModelGuideImportRequest.self,from:inputs.mapping)
                value.inputs=try await api.personalConditioningInputs(preparationJobID:preparationJob,inputs:inputs,
                    modelSampleSHA256:mapping.sourceArtifactSHA256)
                try persist(value)
            }
            guard let context=value.inputs else { throw CaptureError.invalid("Verified conditioning inputs are unavailable.") }
            if value.session == nil { value.session=try await api.createSession(requestKey:value.requestKey);try persist(value) }
            if value.job == nil {
                value.status="Sending candidate inputs";try persist(value)
                for data in [inputs.input,inputs.preparedBrief,inputs.mapping,inputs.anatomy,context.preparationData] {
                    _=try await api.upload(data,sessionID:value.session!)
                }
                let request=try await Task.detached { try context.request() }.value
                value.job=try await api.submitPersonalConditioning(sessionID:value.session!,conditioning:request,requestKey:value.requestKey)
                try persist(value)
            }
            let status=try await api.job(value.job!)
            value.jobState=status.state;value.status="\(status.state) · \(status.stage)";try persist(value)
            if status.state=="succeeded",value.outputSHA256 == nil || result == nil {
                let artifact=try await api.personalConditioningArtifact(jobID:value.job!,inputs:context)
                let file=directory.appendingPathComponent("result.json")
                try await Task.detached { try artifact.data.write(to:file,options:[.atomic,.completeFileProtection]) }.value
                value.outputSHA256=artifact.outputSHA256;value.status="Candidate saved for review";try persist(value)
                result=artifact.result
            }
            error=nil
        } catch { if !Task.isCancelled { self.error=error.localizedDescription } }
        await client?.close()
    }
    func cancel() async {
        guard !busy,var value=saved,let job=value.job else { return }
        busy=true;defer { busy=false };var client:ProcessingClient?
        do {
            value.cancellationPending=true;value.status="Cancellation pending";try persist(value)
            let api=try connection();client=api;try await api.cancelJob(job)
            let status=try await api.job(job);value.jobState=status.state
            value.cancellationPending = !["cancelled","failed","succeeded"].contains(status.state)
            value.status=status.state=="succeeded" ? "Completed before cancellation; refresh to retrieve" : status.state
            try persist(value);error=nil
        } catch { self.error=error.localizedDescription }
        await client?.close()
    }
    func delete() async {
        guard !busy,let saved else { return };busy=true;defer { busy=false };var client:ProcessingClient?
        do {
            if let session=saved.session { let api=try connection();client=api;try await api.deleteSession(session) }
            try FileManager.default.removeItem(at:directory);self.saved=nil;result=nil;error=nil
        } catch { self.error=error.localizedDescription }
        await client?.close()
    }
}

struct PersonalConditioningView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model:PersonalConditioningModel
    @State private var consent=false
    @State private var confirmDelete=false
    @State private var studio: CandidateStudioID?
    @State private var savingStudio=false
    @State private var studioError: String?
    private let scalpReview: ScalpReviewDocument?
    private let observedFace:CanonicalObservedSurface?
    init(source:StoredHaircut,inputs:PersonalPreparationInputs,endpoint:URL,preparationJob:String,observedFace:CanonicalObservedSurface?,scalpReview:ScalpReviewDocument?) {
        _model=StateObject(wrappedValue:PersonalConditioningModel(source:source,inputs:inputs,endpoint:endpoint,preparationJob:preparationJob))
        self.observedFace=observedFace
        self.scalpReview=scalpReview
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Create a research candidate").font(.headline)
                Text("Uses the available model sample and your prepared geometry to create editable guides. This preview does not yet choose a complete hairstyle from your preferences.").font(.footnote)
                if model.saved == nil {
                    Toggle("Run the model with my prepared face, scalp and design inputs on this service",isOn:$consent)
                        .accessibilityIdentifier("conditioningConsent")
                }
                if let saved=model.saved { Text(saved.status).accessibilityIdentifier("conditioningStatus") }
                if let result=model.result {
                    HairGuideScene(record:StoredHaircut(input:result.input,haircut:result.haircut),resetCamera:0,
                        observedFace:observedFace,preparedMesh:result.mesh).frame(height:300)
                        .accessibilityIdentifier("conditioningResultScene")
                    Text("Research revision \(result.validation.haircutSHA256.prefix(10))").font(.caption.monospaced())
                        .accessibilityIdentifier("conditioningRevision")
                    Text("\(Set(result.clearance.violations.map(\.guideID)).count) guide curves need clearance review. \(result.clearance.missingRegions.count) anatomy regions are unavailable.")
                        .accessibilityIdentifier("conditioningReview")
                    if let scalpReview {
                        Button("Save and open separate studio") {
                            Task {
                                savingStudio=true;defer { savingStudio=false }
                                do {
                                    let package=try await Task.detached { try result.modelReviewPackage(scalpReview:scalpReview) }.value
                                    studio=try await CandidateStudioID.save(package);studioError=nil
                                } catch { studioError=error.localizedDescription }
                            }
                        }.disabled(savingStudio || model.busy).accessibilityIdentifier("saveCandidateStudio")
                        Text("Keeps a separate copy in Saved candidates. Edits must pass geometry checks before they can be saved.").font(.footnote)
                    }
                    if savingStudio { ProgressView("Saving candidate studio…") }
                    if let studioError { Text(studioError).foregroundStyle(.red) }
                    Text("Sparse guides at their actual radius. Physical fit, complete hair density and style suitability remain unverified. Your selected haircut has not changed.").font(.footnote)
                }
                Button(model.saved == nil ? "Create candidate" : "Continue / refresh candidate") {
                    Task { await model.advance(allowStart:consent) }
                }.disabled(model.busy || (model.saved == nil && !consent)).accessibilityIdentifier("advanceConditioning")
                if let saved=model.saved {
                    if saved.job != nil,!(["cancelled","failed","succeeded"].contains(saved.jobState ?? "")) {
                        Button(saved.cancellationPending ? "Retry cancellation" : "Cancel candidate job") { Task { await model.cancel() } }
                            .disabled(model.busy).accessibilityIdentifier("cancelConditioning")
                    }
                    Button("Delete candidate and its processing data",role:.destructive) { confirmDelete=true }
                        .disabled(model.busy).accessibilityIdentifier("deleteConditioning")
                }
                if model.busy { ProgressView("Processing candidate…") }
                if let error=model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("conditioningError") }
            }.padding(24)
        }.background(Theme.paper).foregroundStyle(Theme.ink).navigationTitle("Research candidate")
            .navigationDestination(item:$studio) { HairLabView(modelReview:true,candidate:$0) }
            .task { await model.restore() }
            .task(id:model.saved?.job) {
                guard let job=model.saved?.job else { return }
                while !Task.isCancelled {
                    guard let value=model.saved,value.job==job,value.outputSHA256==nil,
                          !["cancelled","failed"].contains(value.jobState ?? "") else { return }
                    do { try await Task.sleep(nanoseconds:2_000_000_000) } catch { return }
                    guard !Task.isCancelled,let value=model.saved,value.job==job,value.outputSHA256==nil,
                          !["cancelled","failed"].contains(value.jobState ?? "") else { return }
                    if scenePhase == .active,!model.busy,model.error==nil { await model.advance() }
                }
            }
            .alert("Delete this candidate?",isPresented:$confirmDelete) {
                Button("Delete",role:.destructive) { Task { await model.delete() } }
                Button("Keep",role:.cancel) { }
            } message: { Text("Removes this candidate's service session and processing files. Studios saved in Saved candidates, your selected haircut and the separate preparation result are kept.") }
    }
}
