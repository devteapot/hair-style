import SwiftUI
import SceneKit
import simd
import HairCore
import UniformTypeIdentifiers

struct HairLabView: View {
    @StateObject private var store: HairLabStore
    private let modelReview: Bool
    private let candidate: CandidateStudioID?
    @State private var importing=false
    @State private var showPreparation=false
    init(modelReview:Bool=false, candidate:CandidateStudioID?=nil) {
        self.modelReview=modelReview
        self.candidate=candidate
        _store=StateObject(wrappedValue:HairLabStore(modelReview:modelReview,candidate:candidate))
    }
    private var preparedURL:URL {
        var name = "model-review.json"
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--conditioned-model-review-test") { name = "conditioned-model-review-test.json" }
        if ProcessInfo.processInfo.arguments.contains("--refined-model-review-test") { name = "refined-model-review-test.json" }
        if ProcessInfo.processInfo.arguments.contains("--prepared-pipeline-model-review-test") { name = "prepared-pipeline-model-review-test.json" }
        if ProcessInfo.processInfo.arguments.contains("--fresh-short-review-test") { name = "fresh-short-review-test.json" }
        #endif
        return FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent(name)
    }
    private var shownMesh:CompiledHairMesh? {
        guard let snapshot=store.snapshot else { return nil }
        return compare ? snapshot.originalMesh : (store.preview == nil ? snapshot.selectedMesh : store.previewMesh)
    }
    @State private var compare = false
    @State private var resetCamera = 0
    @State private var fringeMM = 70.0
    @State private var fringeDirectionDegrees = 0.0
    @State private var confirmDelete = false
    @State private var displayedClearance: GuideClearanceReport?
    private var conflictingRoots: Set<String> {
        guard let report = displayedClearance, report.haircutSHA256 == shownMesh?.haircutSHA256 else { return [] }
        return Set((report.rootViolations ?? []).map(\.guideID))
    }
    private var conflictingSegments: [GuideConflictSegment] {
        guard let report=displayedClearance,let shown,report.haircutSHA256==shownMesh?.haircutSHA256 else { return [] }
        return (try? GuideConflictOverlay.segments(haircut:shown.haircut,report:report)) ?? []
    }
    private var shown: StoredHaircut? {
        guard let snapshot = store.snapshot else { return nil }
        if compare { return snapshot.original }
        var selected = snapshot.selected
        if let preview = store.preview { selected.haircut = preview.haircut }
        return selected
    }
    private var maximumFringe: Double {
        guard let cut = store.snapshot?.selected.haircut else { return 100 }
        let lengths = cut.guides.filter { $0.region == .fringe }.compactMap { try? HaircutValidator.arcLength($0.points) }
        return max(5, floor((lengths.min() ?? 0.1) * 1000 + 1e-5))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(modelReview ? "Generated hair review" : "Synthetic guide lab", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline).foregroundStyle(Theme.accent).accessibilityIdentifier("hairLabNotice")
                Text(modelReview ? "Model-generated guides fitted to your estimated scalp. The recorded face stays fixed. Scalp shape, hairline and style suitability still need review." : "Inspect and edit two test curves on a flat scalp fixture. These are not a generated haircut or a scanned person.")
                    .font(.footnote).foregroundStyle(Theme.ink.opacity(0.8))
                if let record = shown, let snapshot = store.snapshot {
                    if let method = snapshot.researchMethod {
                        Text("Research fitting applied: \(method). Source linkage and geometry are checked; this does not verify the fitting method or physical suitability.")
                            .font(.footnote).foregroundStyle(Theme.ink).accessibilityIdentifier("researchRevisionNotice")
                    }
                    if modelReview || record.haircut.guides.reduce(0, { $0 + $1.points.count - 1 }) <= 2_000 {
                        HairGuideScene(record:record,resetCamera:resetCamera,observedFace:snapshot.observedFace,preparedMesh:shownMesh,
                            conflictingRootIDs: conflictingRoots,conflictingSegments:conflictingSegments)
                            .frame(height: 285).clipShape(RoundedRectangle(cornerRadius: 20))
                            .accessibilityLabel(modelReview ? "Interactive recorded face, inferred scalp and generated guides" : "Interactive synthetic scalp and guide curves")
                            .accessibilityIdentifier("hairGuideScene")
                    } else {
                        Text("This asset exceeds the guide viewer's 2,000-segment limit.")
                            .frame(height: 285).foregroundStyle(Theme.ink.opacity(0.8))
                    }
                    HStack {
                        Text(compare ? "Original · revision 1" : store.preview == nil ? "Saved · revision \(snapshot.selected.haircut.revision)" : "Unsaved preview")
                            .font(.headline).accessibilityIdentifier("hairRevisionStatus")
                        Spacer()
                        Button("Reset view") { resetCamera += 1 }.font(.caption)
                            .accessibilityIdentifier("resetHairCamera")
                    }
                    Text("\(record.haircut.guides.count) guide curves · enlarged for inspection")
                        .font(.caption).foregroundStyle(Theme.ink.opacity(0.8))
                    if !conflictingRoots.isEmpty {
                        Text("Red markers show \(conflictingRoots.count) attachments that need review. Markers are enlarged and visible through the surface to help locate them.")
                            .font(.footnote).foregroundStyle(Theme.ink).accessibilityIdentifier("conflictingRootLegend")
                    }
                    if !conflictingSegments.isEmpty {
                        Text("Purple highlights show \(min(conflictingSegments.count,4096)) of \(conflictingSegments.count) conflicting curve segments. They are enlarged and visible through the surface for inspection.")
                            .font(.footnote).foregroundStyle(Theme.ink).accessibilityIdentifier("conflictingSegmentLegend")
                    }
                    Text(modelReview ? "Fringe \(range(record.haircut,region:.fringe)) mm · crown \(range(record.haircut,region:.crown)) mm" : "Fringe \(fringeLength(record.haircut)) mm · crown \(crownLength(record.haircut)) mm")
                        .font(.caption.monospacedDigit()).accessibilityIdentifier("hairLengths")
                    Toggle("Compare with original", isOn: $compare).accessibilityIdentifier("compareHairOriginal")
                    Text(modelReview ? "Orbit with one finger; pinch to zoom. Gray is the recorded face, amber the inferred scalp, and green the fringe. Guides are enlarged for inspection." : "Orbit with one finger; pinch to zoom. Green is the fringe, amber is the crown. Root dots remain attached to the fixture.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.8))
                    HaircutExplanationView(record: record)
                    NavigationLink("Preferences for a new design") {
                        DesignPreferencesView(source: snapshot.selected.input, directory:store.preferencesDirectory)
                    }.accessibilityIdentifier("openDesignPreferences")
                    if let face = snapshot.observedFace, let identity = shownMesh?.haircutSHA256 {
                        HairClearanceReviewView(record: record, face: face, identity: identity) { displayedClearance = $0 }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fringe length · \(Int(fringeMM)) mm").font(.subheadline.weight(.medium))
                        if maximumFringe > 5 {
                            Slider(value: $fringeMM, in: 5...maximumFringe, step: 1)
                                .accessibilityLabel("Fringe length in millimeters").accessibilityIdentifier("fringeLengthSlider")
                                .onChange(of: fringeMM) { _, _ in store.discard() }
                        }
                        Button("Preview shorter fringe") {
                            compare = false
                            Task { await store.preview(operation: .shortenToLength, region: .fringe, value: fringeMM/1000) }
                        }.disabled(fringeMM >= maximumFringe).accessibilityIdentifier("previewFringe")
                        Text("Fringe direction adjustment · \(Int(fringeDirectionDegrees))°").font(.subheadline.weight(.medium))
                        Slider(value:$fringeDirectionDegrees,in:-45...45,step:1)
                            .accessibilityLabel("Fringe direction adjustment in degrees").accessibilityIdentifier("fringeDirectionSlider")
                            .onChange(of:fringeDirectionDegrees) { _, _ in store.discard() }
                        Text("Relative to the saved revision. Turns each fringe guide around its scalp attachment without changing its length. Growth direction and styling feasibility remain unverified.").font(.footnote)
                        Button("Preview fringe direction") {
                            compare=false
                            Task { await store.preview(operation:.rotateAroundRootNormal,region:.fringe,value:fringeDirectionDegrees) }
                        }.disabled(fringeDirectionDegrees == 0).accessibilityIdentifier("previewFringeDirection")
                        Button("Preview 20% less crown volume") {
                            compare = false
                            Task { await store.preview(operation: .scaleLateralVolume, region: .crown, value: 0.8) }
                        }.accessibilityIdentifier("previewCrown")
                        if modelReview {
                            Button("Preview 20% more crown volume") {
                                compare=false
                                Task { await store.preview(operation:.scaleLateralVolume,region:.crown,value:1.2) }
                            }.accessibilityIdentifier("previewMoreCrown")
                        }
                    }.disabled(store.busy)
                    if store.preview != nil {
                        HStack {
                            Button("Save revision") { Task { await store.save() } }
                                .buttonStyle(.borderedProminent).accessibilityIdentifier("saveHairRevision")
                            Button("Discard") { store.discard() }.accessibilityIdentifier("discardHairPreview")
                        }.disabled(store.busy)
                    }
                    HStack {
                        Button("Undo") { compare = false; Task { await store.move(undo: true) } }
                            .disabled(!snapshot.canUndo || store.busy).accessibilityIdentifier("undoHairRevision")
                        Button("Redo") { compare = false; Task { await store.move(undo: false) } }
                            .disabled(!snapshot.canRedo || store.busy).accessibilityIdentifier("redoHairRevision")
                        Spacer()
                        Text(String(snapshot.hash.prefix(10))).font(.caption.monospaced()).foregroundStyle(Theme.ink.opacity(0.8))
                            .accessibilityIdentifier("selectedHairHash")
                    }
                    Label("Physical feasibility is unverified", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.8))
                    if modelReview, snapshot.observedFace != nil {
                        Button {
                            Task {
                                await store.prepareGenerationInputs()
                                showPreparation = store.preparationInputs != nil
                            }
                        } label: {
                            Text("Check inputs for a new design")
                                .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
                        }.disabled(store.busy || store.preview != nil || compare)
                            .accessibilityIdentifier("preparePersonalGeneration")
                        NavigationLink {
                            ModelLiveSetupView(snapshot: snapshot)
                        } label: {
                            Label("Align saved revision for live preview", systemImage: "person.crop.rectangle")
                        }.disabled(store.busy || store.preview != nil || compare)
                            .accessibilityIdentifier("alignModelLivePreview")
                        Text("Save or discard any preview and leave original comparison before opening live alignment.")
                            .font(.footnote).foregroundStyle(Theme.ink.opacity(0.8))
                    }
                    if !modelReview, store.preview == nil, !compare {
                        NavigationLink("Test durable processing") { ProcessingLabView(source: snapshot.selected) }
                            .accessibilityIdentifier("openProcessingLab")
                    }
                    Button(modelReview ? "Delete model review" : "Delete guide fixture", role: .destructive) { confirmDelete = true }
                        .disabled(store.busy).accessibilityIdentifier("deleteHairFixture")
                } else {
                    ContentUnavailableView(modelReview ? "No model review" : "No guide fixture", systemImage: "point.3.filled.connected.trianglepath.dotted",
                        description: Text(modelReview ? "Import the local package containing generated guides and their captured-face evidence." : "Create a synthetic fixture to inspect the editing pipeline."))
                    if modelReview && candidate == nil {
                        if FileManager.default.fileExists(atPath:preparedURL.path) {
                            Button("Load prepared model review") { Task { await store.importModel(url:preparedURL,consumePrepared:true) } }
                                .buttonStyle(.borderedProminent).disabled(store.busy).accessibilityIdentifier("loadPreparedModelReview")
                        }
                        Button("Import model review") { importing=true }.disabled(store.busy).accessibilityIdentifier("importModelReview")
                    } else if !modelReview {
                        Button("Create synthetic guides") { Task { await store.create() } }
                            .buttonStyle(.borderedProminent).disabled(store.busy).accessibilityIdentifier("createHairFixture")
                    }
                }
                if store.busy { ProgressView("Checking saved geometry…") }
                if let error = store.error {
                    Text(error).font(.footnote).foregroundStyle(Color(red:0.68,green:0.12,blue:0.09)).accessibilityIdentifier("hairLabError")
                    if store.snapshot == nil {
                        Button("Remove unreadable lab data", role: .destructive) { confirmDelete = true }.disabled(store.busy)
                    }
                }
            }.padding(24)
        }.background(Theme.paper).foregroundStyle(Theme.ink).navigationTitle(modelReview ? "Model review" : "Guide studio").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .task { await store.restore() }
            .onChange(of: store.snapshot?.hash) { _, _ in fringeMM = min(fringeMM,maximumFringe) }
            .navigationDestination(isPresented:$showPreparation) {
                if let inputs=store.preparationInputs, let source=store.snapshot?.selected {
                    ProcessingLabView(source:source,preparationInputs:inputs,observedFace:store.snapshot?.observedFace,scalpReview:store.snapshot?.scalpReview)
                }
            }
            .onDisappear { store.discard() }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
                switch result {
                case .success(let url):Task { await store.importModel(url:url) }
                case .failure(let error):store.error=error.localizedDescription
                }
            }
            .alert(modelReview ? "Delete the model review?" : "Delete the guide fixture?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { Task { await store.delete() } }
                Button("Keep", role: .cancel) { }
            } message: { Text(modelReview ? "This removes the imported review and all its saved edits. Original camera captures and the separate scalp review are kept." : "This removes this fixture and all its saved revisions from the device.") }
    }
    private func range(_ cut:HaircutRevision,region:HairRegion)->String {
        let values=cut.guides.filter{$0.region==region}.compactMap{try? HaircutValidator.arcLength($0.points)}
        guard let low=values.min(),let high=values.max() else {return "—"}
        return "\(Int((low*1000).rounded()))–\(Int((high*1000).rounded()))"
    }
    private func fringeLength(_ cut: HaircutRevision) -> Int { length(cut, region: .fringe) }
    private func crownLength(_ cut: HaircutRevision) -> Int { length(cut, region: .crown) }
    private func length(_ cut: HaircutRevision, region: HairRegion) -> Int {
        Int(((cut.guides.first { $0.region == region }.flatMap { try? HaircutValidator.arcLength($0.points) }) ?? 0) * 1000 + 0.5)
    }
}

/// Enlarged tubes for inspection of the small lab fixture. No density
/// interpolation, physical material or hair simulation claim.
struct HairGuideScene: UIViewRepresentable {
    let record: StoredHaircut
    let resetCamera: Int
    var observedFace: CanonicalObservedSurface? = nil
    var preparedMesh: CompiledHairMesh? = nil
    var conflictingRootIDs: Set<String> = []
    var conflictingSegments: [GuideConflictSegment] = []
    final class Coordinator {
        var signature = ""
        var reset = -1
        let content = SCNNode()
        let errorLabel = UILabel()
        let rootMarkers = SCNNode()
        var markerSignature = ""
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene(); view.backgroundColor = UIColor(Theme.paper)
        view.allowsCameraControl = true; view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.scene!.rootNode.addChildNode(context.coordinator.content)
        view.scene!.rootNode.addChildNode(context.coordinator.rootMarkers)
        let errorLabel = context.coordinator.errorLabel
        errorLabel.numberOfLines = 0; errorLabel.textAlignment = .center
        errorLabel.accessibilityIdentifier = "hairMeshError"
        errorLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        errorLabel.frame = view.bounds; view.addSubview(errorLabel)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.zNear = 0.001; camera.camera?.zFar = 10
        camera.camera?.fieldOfView = 42
        view.scene!.rootNode.addChildNode(camera); view.pointOfView = camera
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let isModel=record.haircut.generation.origin == .model
        let signature = preparedMesh?.haircutSHA256 ?? (try? HairArtifactHash.digest(record.haircut)) ?? "invalid"
        let segmentSignature=conflictingSegments.prefix(4096).map { "\($0.guideID):\($0.segmentIndex)" }.joined(separator:",")
        let markerSignature = signature + ":" + conflictingRootIDs.sorted().joined(separator: ",") + ":" + segmentSignature
        if context.coordinator.markerSignature != markerSignature {
            context.coordinator.markerSignature = markerSignature
            context.coordinator.rootMarkers.childNodes.forEach { $0.removeFromParentNode() }
            for guide in record.haircut.guides where conflictingRootIDs.contains(guide.id) {
                guard let root = guide.points.first else { continue }
                let geometry = SCNSphere(radius: 0.002)
                geometry.segmentCount = 12
                geometry.firstMaterial?.diffuse.contents = UIColor.systemRed
                geometry.firstMaterial?.lightingModel = .constant
                geometry.firstMaterial?.readsFromDepthBuffer = false
                geometry.firstMaterial?.writesToDepthBuffer = false
                let node = SCNNode(geometry: geometry); node.position = vector(root); node.renderingOrder = 100
                context.coordinator.rootMarkers.addChildNode(node)
            }
        }
        if context.coordinator.rootMarkers.childNode(withName:"curve-conflicts",recursively:false) == nil, !conflictingSegments.isEmpty {
            var positions:[SCNVector3]=[];var triangles:[UInt32]=[]
            for segment in conflictingSegments.prefix(4096) {
                let a=SIMD3<Float>(Float(segment.start.x),Float(segment.start.y),Float(segment.start.z))
                let b=SIMD3<Float>(Float(segment.end.x),Float(segment.end.y),Float(segment.end.z))
                guard simd_length(b-a)>1e-9 else { continue }
                let direction=simd_normalize(b-a)
                let reference=abs(direction.y)<0.9 ? SIMD3<Float>(0,1,0) : SIMD3<Float>(1,0,0)
                let u=simd_normalize(simd_cross(direction,reference))*0.0008
                let v=simd_cross(direction,u);let offset=UInt32(positions.count)
                for point in [a,b] { for radial in [u,v,-u,-v] { positions.append(SCNVector3(point+radial)) } }
                for side in 0..<4 {
                    let i=offset+UInt32(side),j=offset+UInt32((side+1)%4)
                    triangles += [i,j,i+4,j,j+4,i+4]
                }
            }
            let element=SCNGeometryElement(data:triangles.withUnsafeBytes { Data($0) },primitiveType:.triangles,primitiveCount:triangles.count/3,bytesPerIndex:4)
            let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:positions)],elements:[element])
            let material=SCNMaterial();material.diffuse.contents=UIColor(red:0.55,green:0.05,blue:0.7,alpha:1)
            material.lightingModel = .constant;material.isDoubleSided=true
            material.readsFromDepthBuffer=false;material.writesToDepthBuffer=false;geometry.materials=[material]
            let node=SCNNode(geometry:geometry);node.name="curve-conflicts";node.renderingOrder=101
            context.coordinator.rootMarkers.addChildNode(node)
        }
        if signature != context.coordinator.signature {
            context.coordinator.signature = signature
            let content = context.coordinator.content
            content.childNodes.forEach { $0.removeFromParentNode() }
            let source = SCNGeometrySource(vertices: record.input.scalp.vertices.map(vector))
            let indices = record.input.scalp.triangles.flatMap { $0 }.map { UInt32($0) }
            let element = SCNGeometryElement(data: indices.withUnsafeBytes { Data($0) }, primitiveType: .triangles,
                primitiveCount: indices.count/3, bytesPerIndex: 4)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            geometry.firstMaterial?.diffuse.contents = isModel ? UIColor(red:0.86,green:0.64,blue:0.30,alpha:1) : UIColor(red: 0.72,green: 0.77,blue: 0.73,alpha: 1)
            geometry.firstMaterial?.isDoubleSided = true
            content.addChildNode(SCNNode(geometry: geometry))
            if let face=observedFace {
                let positions=SCNGeometrySource(vertices:face.vertices.map { vector($0.position) })
                let normals=SCNGeometrySource(normals:face.vertices.map { vector($0.normal) })
                let indices=face.triangles.flatMap{$0}.map(UInt32.init)
                let element=SCNGeometryElement(data:indices.withUnsafeBytes{Data($0)},primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4)
                let mesh=SCNGeometry(sources:[positions,normals],elements:[element])
                mesh.firstMaterial?.diffuse.contents=UIColor(white:0.75,alpha:1);mesh.firstMaterial?.isDoubleSided=true
                content.addChildNode(SCNNode(geometry:mesh))
            }
            let mesh: CompiledHairMesh
            do {
                if let preparedMesh { mesh=preparedMesh }
                else if isModel { throw CaptureError.invalid("The model mesh has not finished preparing.") }
                else { mesh = try HairMeshCompiler.compile(input: record.input, haircut: record.haircut, radiusScale: 30) }
                context.coordinator.errorLabel.text = nil
            } catch {
                context.coordinator.errorLabel.text = "Unable to display guides: \(error.localizedDescription)"
                return
            }
            let positions = SCNGeometrySource(vertices: mesh.vertices.map(vector))
            let normals = SCNGeometrySource(normals: mesh.normals.map(vector))
            for batch in mesh.batches {
                let element = SCNGeometryElement(data: batch.indices.withUnsafeBytes { Data($0) },
                    primitiveType: .triangles, primitiveCount: batch.indices.count/3, bytesPerIndex: 4)
                let geometry = SCNGeometry(sources: [positions, normals], elements: [element])
                geometry.firstMaterial?.diffuse.contents = batch.region == .fringe ? UIColor(Theme.accent) : (isModel ? UIColor(red:0.18,green:0.11,blue:0.075,alpha:1) : UIColor(red: 0.74,green: 0.39,blue: 0.13,alpha: 1))
                content.addChildNode(SCNNode(geometry: geometry))
            }
            for guide in record.haircut.guides where !isModel {
                let color = guide.region == .fringe ? UIColor(Theme.accent) : UIColor(red: 0.74,green: 0.39,blue: 0.13,alpha: 1)
                if let root = guide.points.first {
                    let dot = SCNSphere(radius: 0.003); dot.firstMaterial?.diffuse.contents = color
                    let node = SCNNode(geometry: dot); node.position = vector(root); content.addChildNode(node)
                }
            }
        }
        if context.coordinator.reset != resetCamera {
            context.coordinator.reset = resetCamera
            var target=SCNVector3(0,0.13,0.015)
            if isModel {
                let points=record.input.scalp.vertices+record.haircut.guides.flatMap(\.points)
                target=vector(Point3D(x:(points.map(\.x).min()!+points.map(\.x).max()!)/2,
                    y:(points.map(\.y).min()!+points.map(\.y).max()!)/2,z:(points.map(\.z).min()!+points.map(\.z).max()!)/2))
            }
            view.defaultCameraController.stopInertia()
            view.defaultCameraController.worldUp = SCNVector3(0,1,0)
            view.pointOfView?.position = isModel ? SCNVector3(target.x+0.16,target.y+0.06,target.z+0.48) : SCNVector3(0.24,0.29,0.34)
            view.pointOfView?.look(at: target, up: SCNVector3(0,1,0), localFront: SCNVector3(0,0,-1))
            view.defaultCameraController.target = target
        }
    }
    private func vector(_ p: Point3D) -> SCNVector3 { SCNVector3(Float(p.x),Float(p.y),Float(p.z)) }
}

private struct DesignPreferencesView: View {
    let source: HairDesignInput
    let directory: URL
    @State private var guided=false
    @State private var limitTime=false
    @State private var minutes=10
    @State private var heat=0
    @State private var products=0
    @State private var texture=0
    @State private var growth=0
    @State private var lengthRanges:[HairRegion:RequestedLengthRange]=[:]
    @State private var busy=false
    @State private var initiallyLoaded=false
    @State private var status:String?
    @State private var failure:String?
    @State private var savedBriefURL:URL?
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                preferenceCard {
                    Toggle("Choose preferences",isOn:$guided).accessibilityIdentifier("guidedPreferences")
                    Text(guided ? "Every answer is optional." : "Automatic mode uses declared defaults and available evidence. No style answers are required.")
                }
                if guided {
                    Text("Length").font(.headline)
                    preferenceCard {
                        NavigationLink {
                            RegionalLengthPreferencesView(profile:source.hairProfile,ranges:Binding(get:{lengthRanges},set:{lengthRanges=$0;status=nil}))
                        } label: {
                            HStack {
                                VStack(alignment:.leading,spacing:4) {
                                    Text("Regional length ranges")
                                    Text(lengthRangeSummary).font(.callout.weight(.medium)).foregroundStyle(.black)
                                }.fixedSize(horizontal:false,vertical:true)
                                Spacer()
                                Image(systemName:"chevron.right").accessibilityHidden(true)
                            }.frame(minHeight:44).contentShape(Rectangle())
                        }.accessibilityLabel("Regional length ranges")
                            .accessibilityValue(lengthRangeSummary)
                            .accessibilityIdentifier("openLengthPreferences")
                    }
                    Text("Styling").font(.headline)
                    preferenceCard {
                        Toggle("Set a daily time limit",isOn:$limitTime).accessibilityIdentifier("limitStylingTime")
                        if limitTime { Stepper("At most \(minutes) minutes",value:$minutes,in:0...180).accessibilityIdentifier("stylingMinutes") }
                        choice("Heat tools",selection:$heat,id:"heatPreference")
                        choice("Styling products",selection:$products,id:"productPreference")
                        choice("Natural texture",selection:$texture,id:"texturePreference",
                            options:["Unspecified","Preserve it","Changes may be considered"])
                        choice("Allow growing hair out",selection:$growth,id:"growthPreference")
                    }
                }
                preferenceCard {
                    Button("Save design brief") { save() }.buttonStyle(.borderedProminent).tint(Theme.ink).foregroundStyle(.white).accessibilityIdentifier("saveDesignPreferences")
                    if let savedBriefURL { ShareLink("Export saved brief",item:savedBriefURL).accessibilityIdentifier("exportDesignBrief") }
                    Text("This prepares a new brief. It does not regenerate or change the displayed haircut. Styling suitability still needs verification.")
                    if let status { Text(status).accessibilityIdentifier("designPreferencesStatus") }
                    if let failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("designPreferencesError") }
                }
            }.padding(20)
        }.background(Theme.paper).foregroundStyle(Theme.ink)
            .navigationTitle("Design preferences").disabled(busy).task {
                guard !initiallyLoaded else { return }
                initiallyLoaded=true
                await load()
            }
            .onChange(of:guided) { status=nil }.onChange(of:limitTime) { status=nil }
            .onChange(of:minutes) { status=nil }.onChange(of:heat) { status=nil }
            .onChange(of:products) { status=nil }.onChange(of:texture) { status=nil }.onChange(of:growth) { status=nil }
    }
    private var lengthRangeSummary: String {
        lengthRanges.isEmpty ? "No preferred ranges set" : "\(lengthRanges.count) regional range\(lengthRanges.count == 1 ? "" : "s") set"
    }
    private func preferenceCard<Content:View>(@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:20,content:content)
            .frame(maxWidth:.infinity,alignment:.leading).padding(20)
            .background(.white,in:RoundedRectangle(cornerRadius:20))
    }
    private func choice(_ title:String,selection:Binding<Int>,id:String,options:[String]=["Unspecified","Yes","No"])->some View {
        NavigationLink {
            PreferenceChoiceView(title:title,selection:selection,options:options)
        } label: {
            HStack {
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.body).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier(id+"Title")
                Text(options[selection.wrappedValue]).font(.callout).foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
            Image(systemName:"chevron.right").accessibilityHidden(true)
            }.frame(minHeight:44).contentShape(Rectangle()).multilineTextAlignment(.leading)
        }.accessibilityLabel(title)
            .accessibilityValue(options[selection.wrappedValue]).accessibilityIdentifier(id)
    }
    private func answer(_ value:Int)->Bool? { value==0 ? nil : value==1 }
    private func file(_ hash:String)->URL { directory.appendingPathComponent(hash+".json") }
    private func save() {
        let preferences=StylingPreferences(maximumDailyMinutes:limitTime ? minutes:nil,allowsHeatTools:answer(heat),
            allowsStylingProducts:answer(products),preserveNaturalTexture:answer(texture))
        let hasStyling=limitTime || heat != 0 || products != 0 || texture != 0
        let request=DesignBriefRequest(mode:guided ? .guided:.autonomous,seed:source.brief.seed,
            allowGrowth:guided ? answer(growth):nil,
            lengthRanges:guided ? HairRegion.allCases.compactMap { lengthRanges[$0] } : [],
            stylingPreferences:guided && hasStyling ? preferences:nil)
        busy=true;failure=nil;status=nil
        Task {
            defer { busy=false }
            do {
                let source=source
                let value=try await Task.detached(priority:.userInitiated) {
                    try PreparedDesignBrief.prepare(source:source,request:request)
                }.value
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                let url=file(value.sourceSHA256)
                try ManifestCoding.encoder().encode(value).write(to:url,options:[.atomic,.completeFileProtection])
                var target=url;var resource=URLResourceValues();resource.isExcludedFromBackup=true;try target.setResourceValues(resource)
                savedBriefURL=url
                status="Saved \(request.mode == .guided ? "guided" : "automatic") brief. Generation is pending."
            } catch { failure=error.localizedDescription }
        }
    }
    private func load() async {
        busy=true;defer { busy=false }
        do {
            let source=source,directory=directory
            let saved=try await Task.detached(priority:.userInitiated) { () throws -> PreparedDesignBrief? in
                let hash=try HairArtifactHash.digest(source),url=directory.appendingPathComponent(hash+".json")
                guard FileManager.default.fileExists(atPath:url.path) else { return nil }
                guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<25_000_000 else { throw CaptureError.invalid("Saved brief is too large.") }
                let value=try ManifestCoding.decoder().decode(PreparedDesignBrief.self,from:Data(contentsOf:url))
                _=try value.validatedInput(source:source)
                return value
            }.value
            if let saved {
                savedBriefURL=file(saved.sourceSHA256)
                guided=saved.request.mode == .guided;let p=saved.request.stylingPreferences
                limitTime=p?.maximumDailyMinutes != nil;minutes=p?.maximumDailyMinutes ?? 10
                heat=p?.allowsHeatTools.map { $0 ? 1:2 } ?? 0;products=p?.allowsStylingProducts.map { $0 ? 1:2 } ?? 0
                texture=p?.preserveNaturalTexture.map { $0 ? 1:2 } ?? 0;growth=saved.request.allowGrowth.map { $0 ? 1:2 } ?? 0
                lengthRanges=Dictionary(uniqueKeysWithValues:saved.request.lengthRanges.map { ($0.region,$0) })
            }
        } catch { failure=error.localizedDescription }
    }
}

private struct RegionalLengthPreferencesView:View {
    let profile:HairLengthProfile
    @Binding var ranges:[HairRegion:RequestedLengthRange]
    private func name(_ region:HairRegion)->String {
        switch region {
        case .fringe:return "Fringe"
        case .top:return "Top"
        case .crown:return "Crown"
        case .anatomicalLeft:return "Your left side"
        case .anatomicalRight:return "Your right side"
        case .nape:return "Nape"
        }
    }
    var body:some View {
        Form {
            Section {
                Text("Set only the regions you care about. Values are preferred cut lengths in millimeters, not measurements or recommendations.")
                Text("A range beyond reliable current-length evidence requires allowing growth in the main preferences screen.")
            }
            ForEach(HairRegion.allCases,id:\.self) { region in
                Section(name(region)) {
                    Toggle("Set a preferred range",isOn:Binding(get:{ranges[region] != nil},set:{ enabled in
                        ranges[region]=enabled ? RequestedLengthRange(region:region,minimumMeters:0.01,maximumMeters:0.1):nil
                    })).accessibilityIdentifier("lengthEnabled_"+region.rawValue)
                    if let observation=profile.regions.first(where:{$0.region==region}),
                       [.observed,.userSupplied].contains(observation.origin),[.high,.medium].contains(observation.quality),
                       let available=observation.maximumAvailableMeters {
                        Text("Recorded available length: \(available*1000,format:.number.precision(.fractionLength(0))) mm")
                    } else { Text("Current length is uncertain.") }
                    if let range=ranges[region] {
                        lengthControl("Minimum",region:region,minimum:true)
                        lengthControl("Maximum",region:region,minimum:false)
                        if range.minimumMeters>range.maximumMeters { Text("Minimum must not exceed maximum.").foregroundStyle(.red) }
                    }
                }
            }
        }.scrollContentBackground(.hidden).background(Theme.paper).foregroundStyle(Theme.ink).navigationTitle("Preferred lengths")
    }
    private func lengthControl(_ title:String,region:HairRegion,minimum:Bool)->some View {
        let binding=Binding<Double>(get:{
            guard let value=ranges[region] else { return 1 }
            return (minimum ? value.minimumMeters:value.maximumMeters)*1000
        },set:{ mm in
            guard var value=ranges[region] else { return }
            if minimum { value.minimumMeters=mm/1000 } else { value.maximumMeters=mm/1000 }
            ranges[region]=value
        })
        return Stepper(value:binding,in:1...1500,step:1) {
            Text("\(title): \(binding.wrappedValue,format:.number.precision(.fractionLength(0))) mm")
        }.accessibilityIdentifier("length"+(minimum ? "Min_":"Max_")+region.rawValue)
    }
}

private struct PreferenceChoiceView:View {
    let title:String
    @Binding var selection:Int
    let options:[String]
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        List {
            ForEach(options.indices,id:\.self) { index in
                Button { selection=index;dismiss() } label: {
                    HStack {
                        Text(options[index]).font(.body).fixedSize(horizontal:false,vertical:true)
                        Spacer()
                        if selection==index { Image(systemName:"checkmark").accessibilityHidden(true) }
                    }.frame(minHeight:44)
                }.accessibilityAddTraits(selection==index ? [.isSelected] : [])
            }
        }.scrollContentBackground(.hidden).background(Theme.paper).foregroundStyle(Theme.ink).navigationTitle(title)
    }
}

private struct HaircutExplanationView: View {
    let record: StoredHaircut
    @State private var report: HaircutExplanation?
    @State private var failure: String?
    private var identity: String { (try? HairArtifactHash.digest(record.haircut)) ?? "invalid" }
    var body: some View {
        DisclosureGroup("Design details") {
            VStack(alignment: .leading, spacing: 12) {
                if let report, report.haircutSHA256 == identity {
                    Text("Revision \(report.revision) · \(report.mode == .guided ? "Guided constraints" : "Automatic defaults")")
                        .font(.subheadline.weight(.semibold))
                    if report.generationOrigin == .syntheticFixture {
                        Text("Engineering fixture: these values do not describe a person.")
                    }
                    if let preferences=report.stylingPreferences {
                        Text("Your styling preferences").fontWeight(.semibold)
                        if let minutes=preferences.maximumDailyMinutes { Text("Daily styling: at most \(minutes) minutes") }
                        if let allowed=preferences.allowsHeatTools { Text(allowed ? "Heat tools: allowed" : "Heat tools: avoid") }
                        if let allowed=preferences.allowsStylingProducts { Text(allowed ? "Styling products: allowed" : "Styling products: avoid") }
                        if let preserve=preferences.preserveNaturalTexture { Text(preserve ? "Preserve natural texture" : "Texture changes may be considered") }
                        Text("These are requested constraints. This candidate has not been verified to satisfy them.")
                    }
                    ForEach(report.regions, id: \.region) { region in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name(region.region)).fontWeight(.semibold)
                            Text("Guide lengths: \(mm(region.minimumLengthMeters))–\(mm(region.maximumLengthMeters)) mm")
                            Text("Allowed range: \(mm(region.limit.minimumMeters))–\(mm(region.limit.maximumMeters)) mm (\(origin(region.limit.origin)))")
                            if let length = region.availableLengthMeters {
                                Text("Recorded available length: \(mm(length)) mm (\(origin(region.availableLengthOrigin)))")
                            } else {
                                Text("Current length is uncertain; this range does not establish that your hair can achieve it.")
                            }
                            if region.requiresGrowth { Text("This region requires growth beyond its recorded length.").fontWeight(.semibold) }
                        }
                    }
                    if let edit = report.lastEdit {
                        switch edit.operation {
                        case .shortenToLength:
                            Text("Last edit: shorten \(name(edit.region).lowercased()) to at most \(mm(edit.value)) mm.")
                        case .scaleLateralVolume:
                            Text("Last edit: scale \(name(edit.region).lowercased()) lateral volume by \(String(format: "%.2f", edit.value)).")
                        case .rotateAroundRootNormal:
                            Text("Last edit: rotate \(name(edit.region).lowercased()) direction by \(String(format: "%+.1f", edit.value))° around each scalp attachment. Roots and lengths are preserved.")
                        }
                    }
                    Text("These details explain the saved parameters. Suitability, styling effort and physical feasibility remain unverified.")
                } else if let failure {
                    Text("Design details could not be verified: \(failure)")
                } else { ProgressView("Checking design details…") }
            }.font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }.accessibilityIdentifier("hairDesignDetails")
        .task(id: identity) {
            report = nil; failure = nil
            let input = record.input, haircut = record.haircut
            do {
                let result = try await Task.detached { try HaircutExplanation.build(input: input, haircut: haircut) }.value
                guard !Task.isCancelled else { return }
                report = result
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
        }
    }
    private func mm(_ meters: Double) -> String { String(format: "%.1f", meters * 1000) }
    private func name(_ region: HairRegion) -> String {
        switch region {
        case .anatomicalLeft: "Your left side"
        case .anatomicalRight: "Your right side"
        default: region.rawValue.capitalized
        }
    }
    private func origin(_ value: ObservationOrigin) -> String {
        switch value {
        case .observed: "observed"
        case .userSupplied: "user supplied"
        case .inferred: "estimated"
        case .defaultValue: "default"
        case .unknown: "unknown"
        }
    }
}

private struct HairClearanceReviewView: View {
    let record: StoredHaircut
    let face: CanonicalObservedSurface
    let identity: String
    var onReport: (GuideClearanceReport) -> Void = { _ in }
    @State private var report: GuideClearanceReport?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Face clearance").font(.subheadline.weight(.semibold))
            if let report, report.haircutSHA256 == identity {
                let roots = Set((report.rootViolations ?? []).map(\.guideID)).count
                let curves = Set(report.violations.map(\.guideID)).count
                Text(roots > 0 ? "Review scalp attachments" : curves > 0 ? "Hair curves need revision" : "No conflicts with the supplied face surface")
                    .fontWeight(.semibold).accessibilityIdentifier("faceClearanceStatus")
                if roots > 0 {
                    Text("\(roots) attachments are too close to the supplied face surface. Review the estimated scalp, hairline and attachment mapping before regenerating hair; changing curves alone cannot resolve fixed-root conflicts.")
                } else if curves > 0 {
                    Text("\(curves) guide curves conflict with the supplied face surface. Revise the curves and check again before treating this as a valid design.")
                }
                Text("The face scan is incomplete and may be noisy. Ear surfaces are unavailable. This check does not establish physical fit or style suitability.")
                Text("Checked revision \(String(report.haircutSHA256.prefix(10)))")
                    .font(.caption.monospaced()).accessibilityIdentifier("faceClearanceRevision")
            } else if let error {
                Text("Clearance could not be checked: \(error)").accessibilityIdentifier("faceClearanceError")
            } else {
                ProgressView("Checking this revision against the recorded face…")
            }
        }.font(.footnote).foregroundStyle(Theme.ink)
            .task(id: identity) {
                report = nil; error = nil
                let worker = Task.detached(priority: .utility) {
                    try Task.checkCancellation()
                    let anatomy = GuideClearanceInput(scalpSHA256: record.haircut.scalpSHA256, clearanceMeters: 0.001,
                        surfaces: [ClearanceSurface(region: .face, origin: .observed,
                            sourceSHA256: try HairArtifactHash.digest(face), vertices: face.vertices.map(\.position), triangles: face.triangles)])
                    return try GuideClearance.check(input: record.input, haircut: record.haircut, anatomy: anatomy)
                }
                do {
                    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                    guard !Task.isCancelled, result.haircutSHA256 == identity else { return }
                    report = result; onReport(result)
                } catch is CancellationError { }
                catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
    }
}

@MainActor
private final class ProcessingLabModel: ObservableObject {
    struct Saved: Codable {
        var endpoint: URL
        var source: StoredHaircut
        var requestKey: String
        var sessionID: String?
        var jobID: String?
        var status: String
        var mesh: CompiledHairMesh?
        var jobState: String?
        var cancellationPending: Bool?
        var preparationInputs: PersonalPreparationInputs?
        var preparationResult: ProcessingPreparationResult?
    }
    @Published var saved: Saved?
    @Published var busy = false
    @Published var error: String?
    let source: StoredHaircut
    let preparationInputs: PersonalPreparationInputs?
    private var file: URL {
        let name: String
        if let inputs=preparationInputs, let request=try? inputs.request(), let hash=try? HairArtifactHash.digest(request) {
            name="PersonalPreparation/\(hash).json"
        } else { name="ProcessingLab/state.json" }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    }
    init(source: StoredHaircut, preparationInputs: PersonalPreparationInputs? = nil) {
        self.source = source; self.preparationInputs=preparationInputs
    }
    private func persist(_ value: Saved) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var url = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        let data = try ManifestCoding.encoder().encode(value)
        guard data.count <= 100_000_000 else { throw CaptureError.invalid("Processing state exceeds its local storage limit.") }
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        saved = value
    }
    func restore() async {
        guard !busy, FileManager.default.fileExists(atPath: file.path) else { return }
        busy = true; defer { busy = false }
        do {
            let url = file
            let expectedInputs=preparationInputs
            let expectedSource=source
            let value = try await Task.detached {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 100_000_000 else { throw CaptureError.invalid("Saved processing test exceeds its size limit.") }
                let value = try ManifestCoding.decoder().decode(Saved.self, from: Data(contentsOf: url))
                if let inputs=value.preparationInputs {
                    guard try inputs.request() == expectedInputs?.request(), value.mesh == nil else { throw CaptureError.invalid("Saved preparation belongs to different inputs.") }
                    guard try HairArtifactHash.digest(value.source.haircut) == HairArtifactHash.digest(expectedSource.haircut) else { throw CaptureError.invalid("Saved preparation belongs to a different haircut revision.") }
                    let input=try ManifestCoding.decoder().decode(HairDesignInput.self,from:inputs.input)
                    guard try HairArtifactHash.digest(input) == HairArtifactHash.digest(value.source.input) else { throw CaptureError.invalid("Saved preparation source changed.") }
                    if let result=value.preparationResult {
                        let data=try ManifestCoding.encoder().encode(result)
                        _=try ProcessingPreparationResult.verify(data:data,outputSHA256:EvidenceHash.sha256(data),inputs:inputs)
                    }
                } else {
                    guard expectedInputs == nil, value.source.haircut.generation.origin == .syntheticFixture else { throw CaptureError.invalid("This lab only accepts synthetic fixtures.") }
                }
                _ = try HaircutValidator.validate(input: value.source.input, haircut: value.source.haircut)
                if let mesh = value.mesh {
                    let replay = try HairMeshCompiler.compile(input: value.source.input, haircut: value.source.haircut, radialSides: 3, radiusScale: 1)
                    guard try HairArtifactHash.digest(mesh) == HairArtifactHash.digest(replay) else { throw CaptureError.invalid("Saved processing mesh differs from its source.") }
                }
                return value
            }.value
            saved = value; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func client(_ endpoint: URL, createIfMissing: Bool = false) async throws -> ProcessingClient {
        let vault = ProcessingCredentialStore()
        let credential = try vault.load(endpoint: endpoint)
        guard credential != nil || createIfMissing else { throw CaptureError.invalid("This job's guest credential is unavailable. Restore it before contacting its session.") }
        let client = try ProcessingClient(baseURL: endpoint, credential: credential)
        if credential == nil {
            do { try vault.save(await client.createGuest(), endpoint: endpoint) }
            catch { await client.close(); throw error }
        }
        return client
    }
    func advance(endpoint: String) async {
        if saved?.cancellationPending == true { await cancel(); return }
        guard !busy else { return }; busy = true; defer { busy = false }
        var connection: ProcessingClient?
        do {
            var value: Saved
            if let saved { value = saved }
            else {
                guard preparationInputs != nil || source.haircut.generation.origin == .syntheticFixture,
                      let url = URL(string: endpoint) else { throw CaptureError.invalid("Use valid processing inputs and a service origin.") }
                value = Saved(endpoint: try ProcessingEndpoint.origin(url), source: source,
                    requestKey: UUID().uuidString, status: preparationInputs == nil ? "Ready to upload synthetic fixture" : "Ready to send preparation inputs",
                    preparationInputs:preparationInputs)
                try persist(value)
            }
            let client = try await client(value.endpoint, createIfMissing: value.sessionID == nil); connection = client
            if value.sessionID == nil { value.sessionID = try await client.createSession(requestKey: value.requestKey); try persist(value) }
            let input = try ManifestCoding.encoder().encode(value.source.input)
            let haircut = try ManifestCoding.encoder().encode(value.source.haircut)
            if value.jobID == nil {
                if let inputs=value.preparationInputs {
                    value.status="Sending preparation inputs";try persist(value)
                    for data in [inputs.input,inputs.preparedBrief,inputs.mapping,inputs.anatomy] {
                        _=try await client.upload(data,sessionID:value.sessionID!)
                    }
                    value.status="Submitting preparation";try persist(value)
                    value.jobID=try await client.submitPersonalPreparation(sessionID:value.sessionID!,preparation:inputs.request(),requestKey:value.requestKey)
                    try persist(value)
                } else {
                value.status = "Uploading synthetic fixture"; try persist(value)
                let inputHash = try await client.upload(input, sessionID: value.sessionID!)
                let haircutHash = try await client.upload(haircut, sessionID: value.sessionID!)
                value.status = "Submitting compilation"; try persist(value)
                value.jobID = try await client.submitCompilation(sessionID: value.sessionID!, inputHash: inputHash,
                    haircutHash: haircutHash, requestKey: value.requestKey)
                try persist(value)
                }
            }
            let status = try await client.job(value.jobID!)
            value.jobState = status.state
            value.status = "\(status.state) · \(status.stage)"; try persist(value)
            if status.state == "succeeded", let inputs=value.preparationInputs, value.preparationResult == nil {
                value.preparationResult=try await client.personalPreparationResult(jobID:value.jobID!,inputs:inputs)
                value.status=value.preparationResult!.attachmentsReady ? "Supplied attachment checks passed" : "Review scalp attachments before generation"
                try persist(value)
            } else if status.state == "succeeded", value.preparationInputs == nil, value.mesh == nil {
                let result = try await client.compiledResult(jobID: value.jobID!, inputData: input, haircutData: haircut)
                value.mesh = result.mesh; value.status = "Verified result saved for offline viewing"; try persist(value)
            }
            error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        await connection?.close()
    }
    func cancel() async {
        guard !busy, var value = saved, let job = value.jobID else { return }
        busy = true; defer { busy = false }
        var connection: ProcessingClient?
        do {
            // Persist intent first so a lost response or relaunch retries cancellation, not submission.
            value.cancellationPending = true
            value.status = "Cancellation pending — contact the service to confirm"
            try persist(value)
            let client = try await client(value.endpoint); connection = client
            try await client.cancelJob(job)
            let status = try await client.job(job)
            value.jobState = status.state
            value.cancellationPending = !["cancelled", "succeeded", "failed"].contains(status.state)
            switch status.state {
            case "cancelled": value.status = "Cancelled"
            case "cancel_requested": value.status = "Cancellation requested — waiting for worker acknowledgement"
            case "succeeded": value.status = "Completed before cancellation — refresh to retrieve the result"
            default: value.status = "\(status.state) · \(status.stage)"
            }
            try persist(value); error = nil
        } catch { self.error = error.localizedDescription }
        await connection?.close()
    }
    func delete() async {
        guard !busy, let saved else { return }; busy = true; defer { busy = false }
        var connection: ProcessingClient?
        do {
            if let session = saved.sessionID {
                let client = try await client(saved.endpoint); connection = client
                try await client.deleteSession(session)
            }
            try FileManager.default.removeItem(at: file)
            self.saved = nil; error = nil
        } catch { self.error = error.localizedDescription }
        await connection?.close()
    }
}

private struct ProcessingLabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: ProcessingLabModel
    @State private var endpoint = "http://127.0.0.1:8765"
    @State private var confirmDelete = false
    @State private var consent = false
    private let personal: Bool
    private let observedFace: CanonicalObservedSurface?
    private let scalpReview: ScalpReviewDocument?
    init(source: StoredHaircut, preparationInputs: PersonalPreparationInputs? = nil, observedFace: CanonicalObservedSurface? = nil, scalpReview: ScalpReviewDocument? = nil) {
        personal=preparationInputs != nil
        self.observedFace=observedFace
        self.scalpReview=scalpReview
        _model = StateObject(wrappedValue: ProcessingLabModel(source: source,preparationInputs:preparationInputs))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(personal ? "Check your design inputs" : "Synthetic processing test").font(.headline)
                Text(personal ? "Checks your saved brief and scalp attachments against the supplied face scan. This step does not generate a haircut." : "Uploads only this engineering fixture. It tests durable compilation and recovery; it does not generate a personal haircut.").font(.footnote)
                TextField("Service origin", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(model.saved != nil || model.busy).accessibilityIdentifier("processingEndpoint")
                if personal, model.saved == nil {
                    Toggle("Send my face and scalp geometry, attachments and design brief to this service",isOn:$consent)
                        .accessibilityIdentifier("personalPreparationConsent")
                }
                if let saved = model.saved {
                    Text(saved.status).accessibilityIdentifier("processingStatus")
                    Text("Saved source revision \(saved.source.haircut.revision)").font(.caption)
                    if let result=saved.preparationResult {
                        Text(result.attachmentsReady ? "No supplied-surface attachment conflicts" : "\(result.rootPreflight.violations.count) attachment conflicts need review")
                            .accessibilityIdentifier("personalPreparationResult")
                        Text("\(result.rootPreflight.missingRegions.count) anatomy regions remain unavailable. Hair curves, physical fit and style suitability are not verified. No model was run.")
                            .font(.footnote).accessibilityIdentifier("personalPreparationLimitations")
                        if result.attachmentsReady, let inputs=saved.preparationInputs, let job=saved.jobID {
                            NavigationLink("Create a research candidate") {
                                PersonalConditioningView(source:saved.source,inputs:inputs,endpoint:saved.endpoint,
                                    preparationJob:job,observedFace:observedFace,scalpReview:scalpReview)
                            }.accessibilityIdentifier("openPersonalConditioning")
                        }
                    }
                    if let mesh = saved.mesh {
                        HairGuideScene(record: saved.source, resetCamera: 0, preparedMesh: mesh).frame(height: 280)
                            .accessibilityIdentifier("processingResultScene")
                        Text("Verified compiled geometry · actual material radius").font(.footnote)
                    }
                }
                Button(model.saved == nil ? (personal ? "Check design inputs" : "Upload synthetic fixture") : "Continue / refresh job") {
                    Task { await model.advance(endpoint: endpoint) }
                }.disabled(model.busy || (personal && model.saved == nil && !consent)).accessibilityIdentifier("advanceProcessingJob")
                if model.saved != nil {
                    if let saved = model.saved, saved.jobID != nil, saved.mesh == nil,
                       !["cancelled", "succeeded", "failed"].contains(saved.jobState ?? "") {
                        Button(saved.cancellationPending == true ? "Retry cancellation" : "Cancel job") {
                            Task { await model.cancel() }
                        }.disabled(model.busy).accessibilityIdentifier("cancelProcessingJob")
                    }
                    Button("Delete processing test", role: .destructive) { confirmDelete = true }
                        .disabled(model.busy).accessibilityIdentifier("deleteProcessingJob")
                }
                if model.busy { ProgressView("Processing request…") }
                if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("processingError") }
            }.padding(24)
        }.background(Theme.paper).foregroundStyle(Theme.ink).navigationTitle(personal ? "Design preparation" : "Processing lab")
            .task { await model.restore(); if let saved = model.saved { endpoint = saved.endpoint.absoluteString } }
            .task(id:model.saved?.jobID) {
                guard personal, let job=model.saved?.jobID else { return }
                while !Task.isCancelled {
                    guard let saved=model.saved, saved.jobID == job,
                          saved.preparationResult == nil,
                          !["cancelled","failed"].contains(saved.jobState ?? "") else { return }
                    do { try await Task.sleep(nanoseconds:2_000_000_000) }
                    catch { return }
                    guard !Task.isCancelled, let current=model.saved, current.jobID == job,
                          current.preparationResult == nil,
                          !["cancelled","failed"].contains(current.jobState ?? "") else { return }
                    if scenePhase == .active, !model.busy, model.error == nil {
                        await model.advance(endpoint:current.endpoint.absoluteString)
                    }
                }
            }
            .alert("Delete this processing test?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { Task { await model.delete() } }
                Button("Keep", role: .cancel) { }
            } message: { Text(personal ? "Revokes this backend session and removes its local cached result. Your saved haircut and design brief are kept." : "Revokes this backend session and removes its local cached result. The original synthetic guide fixture is kept.") }
    }
}

struct CandidateStudioLibraryView: View {
    @State private var candidates: [CandidateStudioID] = []
    @State private var error: String?
    var body: some View {
        List {
            Text("Each candidate keeps its own edits. Deleting a processing result does not delete these saved studios.").font(.footnote)
            ForEach(candidates) { candidate in
                NavigationLink("Candidate \(candidate.hash.prefix(10))") {
                    HairLabView(modelReview:true,candidate:candidate)
                }.accessibilityIdentifier("candidateStudio-"+candidate.hash)
            }
            if candidates.isEmpty { Text("No saved candidate studios") }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Saved candidates").foregroundStyle(Theme.ink)
            .task {
                do {
                    let root=CandidateStudioID.library
                    candidates = try await Task.detached {
                        guard FileManager.default.fileExists(atPath:root.path) else { return [CandidateStudioID]() }
                        return try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
                            .compactMap { try? CandidateStudioID($0.lastPathComponent) }.sorted { $0.hash < $1.hash }
                    }.value
                    error=nil
                } catch { self.error=error.localizedDescription }
            }
    }
}
