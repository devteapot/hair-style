import SwiftUI
import SceneKit
import ARKit
import AVFoundation
import HairCore

/// Deliberate, local alignment for the exact saved model-review revision.
/// Selection is temporary; every camera session still rechecks its live fit.
struct ModelLiveSetupView: View {
    let snapshot: HairLabSnapshot
    @StateObject private var camera = AlignmentReferenceCamera()
    @State private var scanPoints: [Int] = []
    @State private var facePoints: [Int] = []
    @State private var reference: LiveFaceReference?
    @State private var result: LiveReviewAlignmentResult?
    @State private var error: String?
    @State private var busy = false
    @State private var pickingReference = false
    @State private var showLive = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Align your saved haircut").font(.title2)
                Text("Revision \(snapshot.selected.haircut.revision) · \(snapshot.hash.prefix(12))")
                    .font(.caption.monospaced()).accessibilityIdentifier("alignmentRevision")
                Text("This manual research step matches seven points on your recorded face to a neutral face-tracker mesh. It cannot verify identity or repair an incomplete scan. Use the same person, with hair pinned back.")
                    .font(.footnote)
                Text("Point selections are temporary. Leaving alignment setup requires selecting them again.").font(.footnote)
                if let result {
                    Text("Point alignment passed").font(.headline).accessibilityIdentifier("alignmentPassed")
                    Text(String(format: "Three held-out points: median %.1f mm · largest error %.1f mm", result.referenceRegistration.validationMedianMeters * 1000, (result.referenceRegistration.validationResiduals.map(\.meters).max() ?? 0) * 1000))
                        .font(.footnote)
                    Text("These residuals check your selected points, not anatomical accuracy. The live camera checks alignment again before showing hair.").font(.footnote)
                    Button("Open this revision in live preview") { showLive = true }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("openAlignedLivePreview")
                    Button("Select points again") { reset() }
                } else if !pickingReference, let observed = snapshot.observedFace {
                    Text("1. Select points on the recorded face").font(.headline)
                    pointPrompt(count: scanPoints.count)
                    MeshPointPicker(vertices: observed.vertices.map(\.position), triangles: observed.triangles,
                                    selected: scanPoints) { select($0, reference: false) }
                        .frame(height: 390).clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("recordedFacePointPicker")
                    pickerHelp
                    Text("If a named feature is missing or unclear, return to the scan review. Do not select the scalp or guess where a feature should be.").font(.footnote)
                } else if let reference {
                    Text("3. Select the same points on the neutral tracker face").font(.headline)
                    pointPrompt(count: facePoints.count)
                    MeshPointPicker(vertices: reference.vertices, triangles: reference.triangles,
                                    selected: facePoints) { select($0, reference: true) }
                        .frame(height: 390).clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("trackerFacePointPicker")
                    pickerHelp
                    Button("Retake neutral reference") { self.reference = nil; facePoints = []; error = nil }
                        .disabled(busy)
                    Button("Correct recorded-face points") { pickingReference = false; self.reference = nil; facePoints = []; error = nil }
                        .disabled(busy)
                } else {
                    Text("2. Make a neutral face reference").font(.headline)
                    Text("Keep your eyes open, mouth relaxed and face centered. Start the camera, then choose Use neutral face. Only a temporary 3D mesh is kept in memory; no photo or video is saved.").font(.footnote)
                    if ARFaceTrackingConfiguration.isSupported {
                        AlignmentCameraSurface(model: camera).frame(height: 370)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        Button(camera.running ? "Stop alignment camera" : "Start alignment camera") {
                            if camera.running { camera.stop() } else { Task { await camera.start() } }
                        }.disabled(camera.starting).accessibilityIdentifier("startAlignmentCamera")
                        Button("Use neutral face") {
                            do { reference = try camera.freeze(); error = nil }
                            catch { self.error = error.localizedDescription }
                        }.disabled(!camera.running).accessibilityIdentifier("freezeAlignmentFace")
                    } else {
                        Text("Neutral face capture needs an iPhone with AR face tracking. No camera is opened in the simulator.")
                            .accessibilityIdentifier("alignmentCameraUnsupported")
                    }
                    if let cameraError = camera.error { Text(cameraError).foregroundStyle(errorColor).font(.footnote) }
                    Button("Back to recorded-face points") { camera.stop(); pickingReference = false }
                }
                if busy { ProgressView("Checking alignment and the selected revision…") }
                if let error { Text(error).foregroundStyle(errorColor).font(.footnote).accessibilityIdentifier("modelAlignmentError") }
            }.padding(24)
        }.background(Theme.paper).foregroundStyle(Theme.ink).navigationTitle("Live alignment")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if result == nil, !pickingReference || reference != nil {
                    VStack(spacing: 8) {
                        Divider()
                        HStack {
                            Button("Undo last point") {
                                if pickingReference { if !facePoints.isEmpty { facePoints.removeLast() } }
                                else if !scanPoints.isEmpty { scanPoints.removeLast() }
                                error = nil
                            }.disabled(busy || (pickingReference ? facePoints.isEmpty : scanPoints.isEmpty))
                            Spacer()
                            if let reference, pickingReference {
                                Button("Check alignment") { Task { await prepare(reference) } }
                                    .buttonStyle(.borderedProminent).disabled(facePoints.count != 7 || busy)
                                    .accessibilityIdentifier("checkModelLiveAlignment")
                            } else {
                                Button("Continue") { pickingReference = true }
                                    .buttonStyle(.borderedProminent).disabled(scanPoints.count != 7)
                                    .accessibilityIdentifier("continueAlignmentReference")
                            }
                        }.padding(.horizontal, 24).padding(.bottom, 8)
                    }.background(Theme.paper).foregroundStyle(Theme.ink)
                }
            }
            .navigationDestination(isPresented: $showLive) {
                if let result { LivePreviewView(initialPackage: result.package, observedFace: snapshot.observedFace) }
            }
            .onDisappear { camera.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { camera.stop() } }
    }

    private var errorColor: Color { Color(red: 0.68, green: 0.12, blue: 0.09) }
    private var pickerHelp: some View {
        Text("Tap to mark a feature; drag to rotate and pinch to zoom. This 3D view is not mirrored. Left and right mean the person's own sides. Markers follow the order above.")
            .font(.footnote)
    }
    private func pointPrompt(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(count < 7 ? "Point \(count + 1) of 7: \(LiveReviewCorrespondences.labels[count])" : "All seven points selected")
                .font(.headline).accessibilityIdentifier("alignmentPointPrompt")
            ForEach(0..<count, id: \.self) { index in
                Text("\(index + 1). \(LiveReviewCorrespondences.labels[index]) ✓").font(.caption)
            }
        }
    }
    private func select(_ index: Int, reference: Bool) {
        guard !busy else { return }
        if reference {
            guard facePoints.count < 7, !facePoints.contains(index) else { return }
            facePoints.append(index)
        } else {
            guard scanPoints.count < 7, !scanPoints.contains(index) else { return }
            scanPoints.append(index)
        }
        error = nil
    }
    private func reset() {
        camera.stop(); scanPoints = []; facePoints = []; reference = nil; result = nil; error = nil; pickingReference = false
    }
    private func prepare(_ reference: LiveFaceReference) async {
        guard !busy, let observed = snapshot.observedFace, scanPoints.count == 7, facePoints.count == 7 else { return }
        busy = true; error = nil; defer { busy = false }
        let pairs = zip(scanPoints, facePoints).map { LiveReviewPointPair(observedVertex: $0.0, faceVertex: $0.1) }
        let input = snapshot.selected.input, haircut = snapshot.selected.haircut
        do {
            result = try await Task.detached {
                try LiveReviewCorrespondences.prepare(input: input, haircut: haircut, observed: observed, reference: reference, pairs: pairs)
            }.value
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor
private final class AlignmentReferenceCamera: NSObject, ObservableObject, ARSessionDelegate {
    let view = ARSCNView(frame: .zero)
    @Published var running = false
    @Published var starting = false
    @Published var error: String?
    private var request = UUID()
    override init() {
        super.init()
        view.scene = SCNScene()
        view.session.delegate = self; view.session.delegateQueue = .main
    }
    func start() async {
        guard !running, !starting, ARFaceTrackingConfiguration.isSupported else { return }
        starting = true; error = nil
        let ticket = UUID(); request = ticket
        let permitted = await AVCaptureDevice.requestAccess(for: .video)
        guard request == ticket else { return }
        starting = false
        guard permitted else { error = "Enable camera access in Settings to create an alignment reference."; return }
        let configuration = ARFaceTrackingConfiguration(); configuration.maximumNumberOfTrackedFaces = 1
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        running = true
    }
    func freeze() throws -> LiveFaceReference {
        guard running, let frame = view.session.currentFrame, case .normal = frame.camera.trackingState,
              CACurrentMediaTime() - frame.timestamp < 0.2,
              let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else {
            throw CaptureError.invalid("A stable, visible face is needed. Look at the camera and try again.")
        }
        let vertices = face.geometry.vertices.map { Point3D(x: Double($0.x), y: Double($0.y), z: Double($0.z)) }
        let indices = face.geometry.triangleIndices.map(Int.init)
        let triangles = stride(from: 0, to: indices.count, by: 3).map { Array(indices[$0..<$0+3]) }
        let reference = LiveFaceReference(vertices: vertices, triangles: triangles)
        try reference.validate()
        stop()
        return reference
    }
    func stop() { request = UUID(); starting = false; running = false; view.session.pause() }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in self?.stop(); self?.error = "Camera interrupted. Start it again when ready." }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.stop(); self?.error = message }
    }
}

private struct AlignmentCameraSurface: UIViewRepresentable {
    let model: AlignmentReferenceCamera
    func makeUIView(context: Context) -> ARSCNView { model.view }
    func updateUIView(_ view: ARSCNView, context: Context) { }
}

/// Hit-testing only the visible observed mesh prevents picking an inferred
/// scalp point. Snap to a vertex of the hit triangle to retain exact evidence.
private struct MeshPointPicker: UIViewRepresentable {
    let vertices: [Point3D]
    let triangles: [[Int]]
    let selected: [Int]
    let onPick: (Int) -> Void
    final class Coordinator: NSObject {
        var parent: MeshPointPicker
        weak var view: SCNView?
        let markers = SCNNode()
        var selected: [Int] = []
        init(_ parent: MeshPointPicker) { self.parent = parent }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view, gesture.state == .ended else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            guard let hit = hits.first(where: { $0.node.name == "observed-selection-surface" }),
                  parent.triangles.indices.contains(hit.faceIndex) else { return }
            let p = Point3D(x: Double(hit.localCoordinates.x), y: Double(hit.localCoordinates.y), z: Double(hit.localCoordinates.z))
            func squaredDistance(_ index: Int) -> Double {
                let v = parent.vertices[index]
                return (v.x-p.x)*(v.x-p.x) + (v.y-p.y)*(v.y-p.y) + (v.z-p.z)*(v.z-p.z)
            }
            let index = parent.triangles[hit.faceIndex].min { squaredDistance($0) < squaredDistance($1) }!
            parent.onPick(index)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(); view.scene = SCNScene(); view.backgroundColor = UIColor(Theme.paper)
        view.allowsCameraControl = true; view.autoenablesDefaultLighting = true; view.antialiasingMode = .multisampling4X
        let positions = SCNGeometrySource(vertices: vertices.map { SCNVector3(Float($0.x), Float($0.y), Float($0.z)) })
        let indices = triangles.flatMap { $0 }.map(UInt32.init)
        let element = SCNGeometryElement(data: indices.withUnsafeBytes { Data($0) }, primitiveType: .triangles, primitiveCount: indices.count/3, bytesPerIndex: 4)
        let geometry = SCNGeometry(sources: [positions], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor(white: 0.65, alpha: 1)
        geometry.firstMaterial?.isDoubleSided = true
        let node = SCNNode(geometry: geometry); node.name = "observed-selection-surface"
        view.scene!.rootNode.addChildNode(node)
        view.scene!.rootNode.addChildNode(context.coordinator.markers)
        let xs = vertices.map(\.x), ys = vertices.map(\.y), zs = vertices.map(\.z)
        let center = SCNVector3(Float((xs.min()! + xs.max()!)/2), Float((ys.min()! + ys.max()!)/2), Float((zs.min()! + zs.max()!)/2))
        let extent = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.zNear = 0.001; camera.camera?.zFar = 5
        camera.camera?.fieldOfView = 40
        camera.position = SCNVector3(center.x, center.y, center.z + Float(max(0.2, extent * 1.8)))
        camera.look(at: center, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        view.scene!.rootNode.addChildNode(camera); view.pointOfView = camera
        view.defaultCameraController.target = center
        context.coordinator.view = view
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.selected != selected else { return }
        context.coordinator.selected = selected
        context.coordinator.markers.childNodes.forEach { $0.removeFromParentNode() }
        for (number, index) in selected.enumerated() {
            let sphere = SCNSphere(radius: 0.0015)
            sphere.firstMaterial?.diffuse.contents = number < 4 ? UIColor(Theme.accent) : UIColor(red: 0.7, green: 0.3, blue: 0.07, alpha: 1)
            let node = SCNNode(geometry: sphere), p = vertices[index]
            node.position = SCNVector3(Float(p.x), Float(p.y), Float(p.z))
            context.coordinator.markers.addChildNode(node)
        }
    }
}
