import SwiftUI
import ARKit
import AVFoundation
import UniformTypeIdentifiers
import HairCore

@MainActor
final class LivePreviewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var status = "Import a haircut and calibration landmarks to begin."
    @Published var ready = false
    @Published var running = false
    @Published var preparing = false
    @Published var error: String?
    let view = ARSCNView(frame: .zero)
    let inspectionView = SCNView(frame: .zero)
    @Published var assetIdentity = ""
    private let hairRoot = SCNNode()
    private let faceOccluder = SCNNode()
    private var faceOcclusionGeometry: ARSCNFaceGeometry?
    private var lastFaceAnchorID: String?
    private var package: LivePreviewPackage?
    private var tracker: LiveHairTracker?
    private var displayLink: CADisplayLink?
    private var sessionID = UUID().uuidString
    private var requestID = UUID()
    private var lastFrameTimestamp: Double?
    private var timingRecorder: LiveTimingRecorder?
    private var timingReport: LiveTimingReport?
    private var renderTimingDelegate: LiveRenderTimingDelegate?
    @Published var renderingSummary = ""
    #if targetEnvironment(simulator)
    private var simulatorRenderSettings: (Bool, Bool)?
    #endif
    @Published var hasTimingReport = false
    @Published var timingExportURL: URL?
    @Published var exportingTiming = false


    override init() {
        super.init()
        view.scene = SCNScene(); view.scene.rootNode.addChildNode(hairRoot)
        if let device = view.device ?? MTLCreateSystemDefaultDevice() {
            faceOcclusionGeometry = ARSCNFaceGeometry(device: device, fillMesh: true)
            let material = SCNMaterial()
            material.colorBufferWriteMask = []
            material.writesToDepthBuffer = true; material.readsFromDepthBuffer = true
            material.isDoubleSided = true
            faceOcclusionGeometry?.materials = [material]
            faceOccluder.geometry = faceOcclusionGeometry
            faceOccluder.renderingOrder = -10
            faceOccluder.isHidden = true
            view.scene.rootNode.addChildNode(faceOccluder)
        }
        view.session.delegate = self; view.session.delegateQueue = .main
        view.automaticallyUpdatesLighting = true; view.autoenablesDefaultLighting = true
        hairRoot.isHidden = true
        inspectionView.backgroundColor = UIColor(Theme.paper)
        inspectionView.allowsCameraControl = true; inspectionView.autoenablesDefaultLighting = true
        inspectionView.antialiasingMode = .multisampling4X
    }

    func load(_ url: URL) async {
        stop(); ready = false; package = nil; preparing = true; error = nil
        assetIdentity = ""; inspectionView.scene = nil
        let ticket = UUID(); requestID = ticket
        do {
            let prepared = try await Task.detached { () -> (LivePreviewPackage, CompiledHairMesh) in
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 100_000_000 else { throw CaptureError.invalid("Live package exceeds 100 MB.") }
                let package = try ManifestCoding.decoder().decode(LivePreviewPackage.self, from: Data(contentsOf: url))
                return (package, try package.prepareMesh())
            }.value
            guard requestID == ticket else { return }
            apply(prepared)
        } catch {
            guard requestID == ticket else { return }
            preparing = false; self.error = error.localizedDescription
        }
    }


    func load(package: LivePreviewPackage, observedFace: CanonicalObservedSurface?) async {
        stop(); ready = false; self.package = nil; preparing = true; error = nil
        assetIdentity = ""; inspectionView.scene = nil
        let ticket = UUID(); requestID = ticket
        do {
            let mesh = try await Task.detached { try package.prepareMesh() }.value
            guard requestID == ticket else { return }
            apply((package, mesh), observedFace: observedFace)
        } catch {
            guard requestID == ticket else { return }
            preparing = false; self.error = error.localizedDescription
        }
    }

    private func apply(_ prepared: (LivePreviewPackage, CompiledHairMesh), observedFace: CanonicalObservedSurface? = nil) {
            hairRoot.childNodes.forEach { $0.removeFromParentNode() }
            hairRoot.simdTransform = matrix_identity_float4x4
            let mesh = prepared.1
            let positions = SCNGeometrySource(vertices: mesh.vertices.map { SCNVector3(Float($0.x),Float($0.y),Float($0.z)) })
            let normals = SCNGeometrySource(normals: mesh.normals.map { SCNVector3(Float($0.x),Float($0.y),Float($0.z)) })
            for batch in mesh.batches {
                let element = SCNGeometryElement(data: batch.indices.withUnsafeBytes { Data($0) }, primitiveType: .triangles,
                    primitiveCount: batch.indices.count/3, bytesPerIndex: 4)
                let geometry = SCNGeometry(sources: [positions,normals], elements: [element])
                if let material = mesh.materials.first(where: { $0.id == batch.materialID }) {
                    geometry.firstMaterial = HairSceneMaterials.make(material)
                }
                geometry.firstMaterial?.isDoubleSided = mesh.method == "guide_ribbon_mesh_v1"
                hairRoot.addChildNode(SCNNode(geometry: geometry))
            }
            let scene = SCNScene()
            let inspectionHair = hairRoot.clone(); inspectionHair.isHidden = false
            scene.rootNode.addChildNode(inspectionHair)
            let scalp = prepared.0.input.scalp
            let scalpSource = SCNGeometrySource(vertices: scalp.vertices.map { SCNVector3(Float($0.x),Float($0.y),Float($0.z)) })
            let scalpIndices = scalp.triangles.flatMap { $0 }.map(UInt32.init)
            let scalpElement = SCNGeometryElement(data: scalpIndices.withUnsafeBytes { Data($0) }, primitiveType: .triangles,
                primitiveCount: scalpIndices.count/3, bytesPerIndex: 4)
            let scalpGeometry = SCNGeometry(sources: [scalpSource], elements: [scalpElement])
            scalpGeometry.firstMaterial?.diffuse.contents = UIColor(red: 0.72,green: 0.77,blue: 0.73,alpha: 1)
            scalpGeometry.firstMaterial?.isDoubleSided = true
            if observedFace != nil { scalpGeometry.firstMaterial?.diffuse.contents = UIColor(red: 0.86, green: 0.64, blue: 0.30, alpha: 1) }
            scene.rootNode.addChildNode(SCNNode(geometry: scalpGeometry))
            if let observedFace {
                let positions = SCNGeometrySource(vertices: observedFace.vertices.map { SCNVector3(Float($0.position.x), Float($0.position.y), Float($0.position.z)) })
                let normals = SCNGeometrySource(normals: observedFace.vertices.map { SCNVector3(Float($0.normal.x), Float($0.normal.y), Float($0.normal.z)) })
                let indices = observedFace.triangles.flatMap { $0 }.map(UInt32.init)
                let element = SCNGeometryElement(data: indices.withUnsafeBytes { Data($0) }, primitiveType: .triangles, primitiveCount: indices.count/3, bytesPerIndex: 4)
                let geometry = SCNGeometry(sources: [positions, normals], elements: [element])
                geometry.firstMaterial?.diffuse.contents = UIColor(white: 0.75, alpha: 1)
                geometry.firstMaterial?.isDoubleSided = true
                scene.rootNode.addChildNode(SCNNode(geometry: geometry))
            }
            let all = scalp.vertices + mesh.vertices
            let xs = all.map(\.x), ys = all.map(\.y), zs = all.map(\.z)
            let center = SCNVector3(Float((xs.min()!+xs.max()!)/2),Float((ys.min()!+ys.max()!)/2),Float((zs.min()!+zs.max()!)/2))
            let extent = max(xs.max()!-xs.min()!, max(ys.max()!-ys.min()!, zs.max()!-zs.min()!))
            let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.zNear = 0.001; camera.camera?.zFar = 20
            camera.position = SCNVector3(center.x + Float(extent*1.2),center.y + Float(extent*0.8),center.z + Float(max(0.2,extent*2)))
            camera.look(at: center, up: SCNVector3(0,1,0), localFront: SCNVector3(0,0,-1))
            scene.rootNode.addChildNode(camera); inspectionView.scene = scene; inspectionView.pointOfView = camera
            inspectionView.defaultCameraController.target = center
            let source = prepared.0.input.scalp.triangleOrigins.contains(.synthetic) ? "Synthetic test asset" : "Imported asset"
            assetIdentity = "\(source) · Revision \(mesh.haircutRevision) · \(mesh.haircutSHA256)"
            package = prepared.0; ready = true; preparing = false
            status = "Loaded revision \(mesh.haircutRevision). Pin existing hair back, then start the camera."
    }

    func start() async {
        guard ready, !running, !preparing, ARFaceTrackingConfiguration.isSupported else { return }
        guard faceOcclusionGeometry != nil else { error = "Unable to prepare the face-depth renderer."; return }
        preparing = true; error = nil
        let ticket = UUID(); requestID = ticket
        let permitted = await AVCaptureDevice.requestAccess(for: .video)
        guard requestID == ticket else { return }
        preparing = false
        guard permitted else { error = "Camera access is off. Enable it in Settings to try the live preview."; return }
        sessionID = UUID().uuidString; tracker = nil; lastFrameTimestamp = nil; lastFaceAnchorID = nil
        let configuration = ARFaceTrackingConfiguration(); configuration.maximumNumberOfTrackedFaces = ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces
        if let package {
            let identity = try? HairArtifactHash.digest(package.haircut)
            if let identity {
                timingRecorder = try? LiveTimingRecorder(haircutSHA256: identity)
                renderTimingDelegate = try? LiveRenderTimingDelegate(haircutSHA256: identity)
                view.delegate = renderTimingDelegate
            }
        }
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        timingReport = nil; hasTimingReport = false
        if let timingExportURL { try? FileManager.default.removeItem(at: timingExportURL) }
        timingExportURL = nil
        running = true; status = "Keep a neutral expression and tap Calibrate alignment."
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    #if targetEnvironment(simulator)
    func recordSimulatorRenderTiming() async {
        guard ready, !running, let package else { return }
        do {
            let identity = try HairArtifactHash.digest(package.haircut)
            timingRecorder = try LiveTimingRecorder(haircutSHA256: identity)
            renderTimingDelegate = try LiveRenderTimingDelegate(haircutSHA256: identity, context: .syntheticInspection)
            simulatorRenderSettings = (inspectionView.isPlaying, inspectionView.rendersContinuously)
            inspectionView.delegate = renderTimingDelegate
            inspectionView.isPlaying = true; inspectionView.rendersContinuously = true
            timingReport = nil; hasTimingReport = false; renderingSummary = ""
            running = true; let ticket = requestID
            try await Task.sleep(nanoseconds: 3_000_000_000)
            guard ticket == requestID else { return }
            stop()
        } catch { stop(); self.error = error.localizedDescription }
    }

    func loadSimulatorFixture() async {
        do {
            let (input, original) = try SyntheticHaircut.create()
            var haircut = original; haircut.materials[0].radiusMeters = 0.0015
            let positions = [(-0.08,-0.08),(0.08,-0.08),(-0.08,0.08),(0.08,0.08),(-0.03,-0.02),(0.04,-0.01),(0.0,0.05)]
            let landmarks = positions.enumerated().map {
                LiveLandmarkSelection(id: "fixture_\($0.offset)", canonicalPoint: Point3D(x: $0.element.0,y: 0.1,z: $0.element.1), faceVertexIndex: $0.offset)
            }
            let fixture = LivePreviewPackage(input: input, haircut: haircut,
                fitLandmarks: Array(landmarks.prefix(4)), validationLandmarks: Array(landmarks.suffix(3)))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
            try ManifestCoding.encoder().encode(fixture).write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }
            await load(url)
        } catch { self.error = error.localizedDescription }
    }
    #endif

    func calibrate() {
        guard running, let package, let frame = view.session.currentFrame,
              case .normal = frame.camera.trackingState,
              frame.anchors.compactMap({ $0 as? ARFaceAnchor }).count == 1,
              let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else {
            error = "Exactly one tracked face is needed. Stay alone in frame with a neutral expression."; return
        }
        do {
            let vertices = face.geometry.vertices
            let indices = face.geometry.triangleIndices.map(Int.init)
            let triangles = stride(from: 0, to: indices.count, by: 3).map { Array(indices[$0..<$0+3]) }
            try package.validateTrackerTopology(vertexCount: vertices.count, triangles: triangles)
            func pairs(_ selected: [LiveLandmarkSelection]) throws -> [LandmarkPair] {
                try selected.map { point in
                    guard vertices.indices.contains(point.faceVertexIndex) else { throw CaptureError.invalid("A selected face vertex is unavailable on this device.") }
                    let v = vertices[point.faceVertexIndex]
                    return LandmarkPair(id: point.id, source: point.canonicalPoint,
                                        target: Point3D(x: Double(v.x),y: Double(v.y),z: Double(v.z)))
                }
            }
            let registration = RegistrationInput(sourceFrameID: "personal_canonical", targetFrameID: "ar_face_local",
                evidenceSource: package.input.scalp.triangleOrigins.contains(.synthetic) ? .syntheticFixture : .sensor,
                fitPairs: try pairs(package.fitLandmarks), validationPairs: try pairs(package.validationLandmarks))
            let request = LiveCalibrationRequest(scalpSHA256: package.haircut.scalpSHA256, trackingSessionID: sessionID,
                anchorID: face.identifier.uuidString, landmarkEvidenceSHA256: try HairArtifactHash.digest(registration), registration: registration)
            let calibration = try LiveHairAlignment.calibrate(request, scalp: package.input.scalp)
            tracker = try LiveHairTracker(calibration: calibration, scalp: package.input.scalp)
            error = nil; status = "Alignment accepted. Acquiring stable tracking…"
        } catch { tracker = nil; hairRoot.isHidden = true; faceOccluder.isHidden = true; self.error = error.localizedDescription }
    }

    @objc private func tick() {
        guard running else { return }
        let now = CACurrentMediaTime()
        var newCameraFrame = false
        var overlayState: LiveOverlayState?
        defer {
            let thermal: String
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: thermal = "nominal"
            case .fair: thermal = "fair"
            case .serious: thermal = "serious"
            case .critical: thermal = "critical"
            @unknown default: thermal = "unknown"
            }
            timingRecorder?.append(timestamp: now, newCameraFrame: newCameraFrame,
                overlayState: overlayState, thermalState: thermal)
        }
        if let frame = view.session.currentFrame, frame.timestamp != lastFrameTimestamp {
            newCameraFrame = true
            lastFrameTimestamp = frame.timestamp
            let faces = frame.anchors.compactMap { $0 as? ARFaceAnchor }
            if let face = faces.first {
                lastFaceAnchorID = face.identifier.uuidString
                faceOcclusionGeometry?.update(from: face.geometry)
                faceOccluder.simdTransform = face.transform
                let m = face.transform
                let matrix = RigidTransform(rowMajor: (0..<4).flatMap { r in (0..<4).map { c in Double(m[c][r]) } })
                let normal: Bool
                if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
                try? tracker?.update(LiveFaceSample(trackingSessionID: sessionID, anchorID: face.identifier.uuidString,
                    timestamp: now, tracked: face.isTracked && normal, worldFromFace: matrix, faceCount: faces.count))
            } else if let lastFaceAnchorID {
                try? tracker?.update(LiveFaceSample(trackingSessionID: sessionID, anchorID: lastFaceAnchorID,
                    timestamp: now, tracked: false, worldFromFace: .identity, faceCount: 0))
            }
        }
        guard let presentation = tracker?.presentation(now: now) else { hairRoot.isHidden = true; faceOccluder.isHidden = true; return }
        overlayState = presentation.state
        if let transform = presentation.worldFromCanonical {
            let m = transform.rowMajor
            hairRoot.simdTransform = simd_float4x4(columns: (
                SIMD4(Float(m[0]),Float(m[4]),Float(m[8]),Float(m[12])),
                SIMD4(Float(m[1]),Float(m[5]),Float(m[9]),Float(m[13])),
                SIMD4(Float(m[2]),Float(m[6]),Float(m[10]),Float(m[14])),
                SIMD4(Float(m[3]),Float(m[7]),Float(m[11]),Float(m[15]))))
            hairRoot.isHidden = false; faceOccluder.isHidden = false
        } else { hairRoot.isHidden = true; faceOccluder.isHidden = true }
        let message: String
        switch presentation.state {
        case .visible: message = "Live alignment active · experimental preview"
        case .acquiring: message = "Acquiring stable tracking…"
        case .trackingLost: message = "Tracking lost. Face the camera to reacquire."
        case .recalibrationRequired: message = "Alignment changed or multiple faces were detected. Stay alone in frame and calibrate again."
        }
        if status != message { status = message }
    }

    func exportTiming() async {
        guard !running, !exportingTiming, let report = timingReport else { return }
        exportingTiming = true; defer { exportingTiming = false }
        do {
            let url = try await Task.detached {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-timing-" + UUID().uuidString + ".json")
                try ManifestCoding.encoder().encode(report).write(to: url, options: [.atomic, .completeFileProtection])
                return url
            }.value
            if let timingExportURL { try? FileManager.default.removeItem(at: timingExportURL) }
            timingExportURL = url
        } catch { self.error = error.localizedDescription }
    }

    func stop() {
        let renderReport = renderTimingDelegate?.stop()
        view.delegate = nil; renderTimingDelegate = nil
        #if targetEnvironment(simulator)
        if let settings = simulatorRenderSettings {
            inspectionView.delegate = nil
            inspectionView.isPlaying = settings.0; inspectionView.rendersContinuously = settings.1
            simulatorRenderSettings = nil
        }
        #endif
        if let timingRecorder {
            var report = timingRecorder.report(); report.rendererCallbacks = renderReport
            timingReport = report
            hasTimingReport = !report.samples.isEmpty || (renderReport?.observedCallbackCount ?? 0) > 0
            if let renderReport {
                let prefix = renderReport.context == .syntheticInspection ? "Synthetic renderer callbacks" : "Renderer callbacks"
                renderingSummary = "\(prefix): \(renderReport.observedCallbackCount)"
            }
            self.timingRecorder = nil
        }
        requestID = UUID(); preparing = false; running = false
        displayLink?.invalidate(); displayLink = nil
        view.session.pause(); tracker?.interrupt(); tracker = nil; hairRoot.isHidden = true; faceOccluder.isHidden = true
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.stop(); self?.status = "Camera interrupted. Start again and recalibrate."
        }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.stop(); self?.error = "AR tracking failed: " + message
        }
    }
}

private struct HairInspectionSurface: UIViewRepresentable {
    let model: LivePreviewModel
    func makeUIView(context: Context) -> SCNView { model.inspectionView }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

private struct LiveCameraSurface: UIViewRepresentable {
    let model: LivePreviewModel
    func makeUIView(context: Context) -> ARSCNView { model.view }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct LivePreviewView: View {
    @StateObject private var model = LivePreviewModel()
    @State private var importing = false
    var initialPackage: LivePreviewPackage? = nil
    var observedFace: CanonicalObservedSurface? = nil
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Experimental live preview").font(.title2)
                Text("Uses an imported haircut and explicit calibration landmarks. Pin existing hair back. Stay alone in frame. Multiple reported faces pause alignment until you calibrate again. Face-depth occlusion is experimental; ears, hands and existing hair are not masked.").font(.footnote)
                if initialPackage == nil {
                    Button("Import live package") { importing = true }.disabled(model.preparing)
                } else {
                    Text("Uses your selected saved revision. Guides retain the same enlarged inspection thickness as the model review; this is not final hair density.").font(.footnote)
                }
                #if targetEnvironment(simulator)
                Button("Load synthetic preview test") { Task { await model.loadSimulatorFixture() } }
                    .disabled(model.preparing).accessibilityIdentifier("loadPreviewFixture")
                if model.ready && ProcessInfo.processInfo.arguments.contains("--render-timing-test") {
                    Button("Record synthetic rendering timing") { Task { await model.recordSimulatorRenderTiming() } }
                        .disabled(model.running).accessibilityIdentifier("recordSyntheticRenderTiming")
                }
                #endif
                if model.ready {
                    HairInspectionSurface(model: model).frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityIdentifier("importedHairScene")
                    Text(model.assetIdentity).font(.caption.monospaced()).textSelection(.enabled)
                        .accessibilityIdentifier("importedHairIdentity")
                    Text("Orbit and pinch to inspect. This is the same hair mesh used by live preview. Scalp completion and inferred regions need separate review.").font(.footnote)
                }
                if ARFaceTrackingConfiguration.isSupported {
                    LiveCameraSurface(model: model).frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 20))
                    Button(model.running ? "Stop camera" : "Start camera") {
                        if model.running { model.stop() } else { Task { await model.start() } }
                    }.disabled(!model.ready || model.preparing || model.exportingTiming)
                    Button("Calibrate alignment") { model.calibrate() }.disabled(!model.running)
                    Text(model.status).font(.callout)
                } else {
                    Text("Live preview needs an iPhone with AR face tracking. It cannot run in the simulator.")
                        .accessibilityIdentifier("liveUnsupported")
                }
                if model.hasTimingReport && !model.running {
                    Text(model.renderingSummary).accessibilityIdentifier("renderTimingSummary")
                    Text("Timing records display intervals, SceneKit render callbacks, camera-frame arrivals, tracking and thermal state. It contains no images or face coordinates. These callbacks do not measure GPU completion or displayed-frame timing.")
                        .font(.footnote)
                    Button("Prepare timing export") { Task { await model.exportTiming() } }
                        .disabled(model.exportingTiming)
                    if let url = model.timingExportURL { ShareLink("Share timing report", item: url) }
                }
                if let error = model.error { Text(error).foregroundStyle(Color(red: 0.68, green: 0.12, blue: 0.09)).font(.footnote) }
            }.padding(24)
        }.background(Theme.paper).foregroundStyle(Theme.ink).navigationTitle("Live preview")
            .task { if let initialPackage { await model.load(package: initialPackage, observedFace: observedFace) } }
            .onDisappear { model.stop() }
            .onChange(of: phase) { _, value in if value != .active { model.stop() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): Task { await model.load(url) }
                case .failure(let error): model.error = error.localizedDescription
                }
            }
    }
}
