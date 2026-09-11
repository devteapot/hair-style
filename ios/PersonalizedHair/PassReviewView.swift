import SwiftUI
import SceneKit
import HairCore

struct PassReviewView: View {
    let pass: SavedPass
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var report: BundleReport?
    @State private var timing: CaptureTimingReport?
    @State private var index: Double = 0
    @State private var imageData: Data?
    @State private var points: [Point3D] = []
    @State private var showCloud = false
    @State private var error: String?
    @State private var loading = true
    @State private var exporting = false
    @State private var share: ShareFile?
    @State private var exportURL: URL?
    @State private var exportTask: Task<Void, Never>?
    @State private var exportTicket = UUID()
    #if targetEnvironment(simulator)
    @State private var exportPublicationHeld = false
    #endif
    @State private var confirmDelete = false
    @State private var landmarks: FaceLandmarkReport?
    @State private var rotation: ImageQuarterTurn = .none
    @State private var detectingFace = false
    @State private var landmarkError: String?
    @State private var landmarkTicket = UUID()

    private var frame: StoredFrame? {
        pass.manifest.frames.indices.contains(Int(index)) ? pass.manifest.frames[Int(index)] : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if pass.manifest.source == .syntheticFixture {
                    Label("Synthetic calibration fixture", systemImage: "cube.transparent")
                        .font(.headline).foregroundStyle(Theme.accent).accessibilityIdentifier("syntheticNotice")
                    Text("An asymmetric plane for checking formats and coordinates. It is not a person or evidence of camera accuracy.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.75))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label(pass.manifest.status == .completed ? "Recording saved" : "Recording incomplete",
                          systemImage: pass.manifest.status == .completed ? "externaldrive" : "exclamationmark.triangle")
                        .font(.headline)
                    Text(pass.manifest.source == .syntheticFixture
                         ? "This fixture checks the app. It cannot verify a person's scan quality."
                         : "Scan quality has not been verified. Check that your head stayed still and the requested areas are visible across the recording.")
                        .font(.subheadline).accessibilityIdentifier("scanQualityStatus")
                    Text("The image and depth views show one recorded frame at a time. A complete 3D head has not been reconstructed.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                Picker("Display", selection: $showCloud) {
                    Text("Image").tag(false)
                    Text("3D depth").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("reviewDisplay")

                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(Theme.ink.opacity(0.06))
                    if loading { ProgressView("Checking evidence…") }
                    else if showCloud {
                        if points.isEmpty { Text("No calibrated depth in this frame.").foregroundStyle(Theme.ink.opacity(0.75)) }
                        else { PointCloudView(points: points).clipShape(RoundedRectangle(cornerRadius: 20)) }
                    } else if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay {
                                if let landmarks { FaceLandmarkOverlay(report: landmarks) }
                            }
                    }
                }.frame(height: 300)
                if pass.manifest.frames.count > 1 {
                    Slider(value: $index, in: 0...Double(pass.manifest.frames.count - 1), step: 1)
                        .accessibilityLabel("Frame").accessibilityValue("\(Int(index) + 1)")
                }
                Text(pass.manifest.frames.isEmpty ? "No frames were saved." : "Frame \(Int(index) + 1) of \(pass.manifest.frames.count)").font(.caption.monospacedDigit())
                if showCloud {
                    Text("Orbit and pinch to inspect one camera-space frame. No head alignment or lens correction has been applied.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.75))
                }
                if !showCloud {
                    Picker("Rotation to upright for analysis", selection: $rotation) {
                        Text("0°").tag(ImageQuarterTurn.none)
                        Text("90° CW").tag(ImageQuarterTurn.clockwise90)
                        Text("180°").tag(ImageQuarterTurn.clockwise180)
                        Text("270° CW").tag(ImageQuarterTurn.clockwise270)
                    }.pickerStyle(.segmented).accessibilityIdentifier("landmarkRotation")
                    Text("Choose the rotation that makes the face upright. Dots stay aligned to the original stored image.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.75))
                    Button(detectingFace ? "Analyzing face…" : "Analyze face landmarks") { Task { await detectLandmarks() } }
                        .disabled(loading || detectingFace || report?.valid != true).accessibilityIdentifier("analyzeLandmarks")
                    if let landmarks {
                        Text(landmarkSummary(landmarks)).font(.footnote).foregroundStyle(Theme.ink.opacity(0.75))
                            .accessibilityIdentifier("landmarkStatus")
                    }
                    if let landmarkError {
                        Text("Face analysis unavailable: \(landmarkError)")
                            .font(.footnote).foregroundStyle(.red).accessibilityIdentifier("landmarkFailure")
                    }
                }
                if let frame {
                    Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 8) {
                        metric("Image", "\(frame.metadata.imageSize.width) × \(frame.metadata.imageSize.height)")
                        if let size = frame.metadata.depthSize { metric("Depth", "\(size.width) × \(size.height) · meters") }
                        if let fraction = frame.metadata.quality.validDepthFraction { metric("Valid depth", "\(Int(fraction * 100))%") }
                        metric("Pose", frame.metadata.poseSource)
                        metric("Mirrored data", frame.metadata.mirrored ? "Yes" : "No")
                    }.font(.caption)
                }
                if let timing {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Saved frame timing").font(.headline)
                        Text("Requested: \(String(format: "%.1f", timing.requestedRateHz)) frames/s")
                        if let rate = timing.observedRateHz {
                            Text("Recorded average: \(String(format: "%.2f", rate)) frames/s")
                        }
                        if let gap = timing.maximumIntervalSeconds {
                            Text("Longest gap: \(String(format: "%.0f", gap * 1000)) ms")
                        }
                        if !timing.nonIncreasingFrameIndices.isEmpty {
                            Text("Some timestamps are repeated or out of order; average rate is unavailable.")
                        }
                        Text("Timing describes saved evidence, not image sharpness or scan coverage.")
                    }.font(.footnote).accessibilityIdentifier("captureTiming")
                }
                if let report {
                    Label(report.valid ? "Saved files are intact" : "Saved files need attention", systemImage: report.valid ? "checkmark.shield" : "exclamationmark.triangle")
                        .font(.headline).foregroundStyle(report.valid ? Theme.accent : .red)
                        .accessibilityIdentifier("integrityStatus")
                    Text("File checks do not confirm complete coverage, sharp images or a motion-free scan.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.75))
                    ForEach(report.errors, id: \.self) { Text($0).foregroundStyle(.red).font(.footnote) }
                    ForEach(report.warnings, id: \.self) { Text($0).foregroundStyle(Theme.ink.opacity(0.75)).font(.footnote) }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Button {
                    exportTask = Task { await export() }
                } label: {
                    Label(exporting ? "Preparing export…" : "Export capture bundle", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).tint(Theme.ink)
                    .disabled(exporting || report?.valid != true).accessibilityIdentifier("exportCapture")
                #if targetEnvironment(simulator)
                if exportPublicationHeld {
                    Text("Synthetic test: export publication held")
                        .accessibilityIdentifier("exportPublicationHeld")
                }
                #endif
                Button("Delete this capture", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity).accessibilityIdentifier("deleteCapture")
            }.padding(24)
        }.background(Theme.paper)
            .navigationTitle("Review capture").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .task {
                do {
                    let url = pass.url
                    let result = try await Task.detached {
                        let integrity = try CaptureBundle.inspect(url)
                        let timing = integrity.valid ? try CaptureTimingReport.analyze(CaptureBundle.load(url)) : nil
                        return (integrity, timing)
                    }.value
                    try Task.checkCancellation()
                    report = result.0; timing = result.1
                } catch { self.error = error.localizedDescription }
            }
            .task(id: Int(index)) { await loadFrame() }
            .onChange(of: rotation) { _, _ in clearLandmarks() }
            .onDisappear { clearLandmarks(); cancelExport() }
            .sheet(item: $share, onDismiss: cleanupExport) { file in ShareSheet(url: file.url) }
            .alert("Delete this capture?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { cancelExport(); if store.delete(pass) { dismiss() } else { error = store.error } }
                Button("Keep", role: .cancel) { }
            } message: { Text("This removes its images and depth evidence from this device.") }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        GridRow { Text(label).foregroundStyle(Theme.ink.opacity(0.75)); Text(value).textSelection(.enabled) }
    }

    private func loadFrame() async {
        clearLandmarks()
        guard let selected = frame else { loading = false; return }
        loading = true
        do {
            let root = pass.url
            let result = try await Task.detached { () throws -> (Data, [Point3D]) in
                let image = try CaptureBundle.payload(selected.image, in: root)
                var points: [Point3D] = []
                if let evidence = selected.depth, let size = selected.metadata.depthSize, let k = selected.metadata.intrinsics {
                    let depth = try DepthGeometry.decode(CaptureBundle.payload(evidence, in: root), size: size)
                    points = try DepthGeometry.pointCloud(values: depth, size: size, intrinsics: k, stride: max(1, size.width / 160))
                }
                return (image, points)
            }.value
            try Task.checkCancellation()
            imageData = result.0; points = result.1; loading = false
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription; loading = false }
    }

    private func clearLandmarks() {
        landmarkTicket = UUID(); landmarks = nil; landmarkError = nil; detectingFace = false
    }
    private func detectLandmarks() async {
        guard let frame else { return }
        let ticket = UUID(); landmarkTicket = ticket; detectingFace = true; landmarkError = nil
        let root = pass.url, id = frame.metadata.id, selectedRotation = rotation
        defer { if landmarkTicket == ticket { detectingFace = false } }
        do {
            let result = try await Task.detached {
                try FaceLandmarkExtractor.extract(bundle: root, frameID: id, rotation: selectedRotation)
            }.value
            guard landmarkTicket == ticket else { return }
            landmarks = result
        } catch {
            guard landmarkTicket == ticket else { return }
            landmarkError = error.localizedDescription
        }
    }
    private func landmarkSummary(_ result: FaceLandmarkReport) -> String {
        switch result.status {
        case .noFace: return "No face detected. Check orientation and visibility."
        case .multipleFaces: return "More than one face detected. Use a frame with only the subject."
        case .lowConfidence: return "Face detection is uncertain. Try another frame."
        case .missingLandmarks: return "A face was detected, but its landmarks are unavailable."
        case .detected:
            let depth = result.points.filter { $0.cameraPoint != nil }.count
            return "\(result.points.count) landmark estimates; \(depth) have usable depth. Green dots have depth; amber dots do not. These estimates still need alignment review."
        }
    }

    private func export() async {
        let ticket = UUID(); exportTicket = ticket
        exporting = true
        defer { if exportTicket == ticket { exporting = false; exportTask = nil } }
        let root = pass.url
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString).zip")
        let worker = Task.detached { try CaptureArchive.export(bundle: root, to: destination) }
        do {
            try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--hold-export-publication-test") {
                exportPublicationHeld = true
                // Simulate a completed worker whose result arrives after view cancellation.
                await Task.detached { try? await Task.sleep(for: .seconds(5)) }.value
                exportPublicationHeld = false
            }
            #endif
            guard !Task.isCancelled, exportTicket == ticket else {
                try? FileManager.default.removeItem(at: destination)
                return
            }
            exportURL = destination; share = ShareFile(url: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            guard !Task.isCancelled, exportTicket == ticket else { return }
            self.error = error.localizedDescription
        }
    }

    private func cancelExport() {
        exportTicket = UUID(); exportTask?.cancel(); exportTask = nil
        exporting = false; share = nil; cleanupExport()
    }

    private func cleanupExport() {
        if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
        exportURL = nil
    }
}

private struct FaceLandmarkOverlay: View {
    let report: FaceLandmarkReport
    var body: some View {
        GeometryReader { geometry in
            let width = Double(report.nativeImageSize.width), height = Double(report.nativeImageSize.height)
            let scale = min(geometry.size.width/width, geometry.size.height/height)
            let left = (geometry.size.width-width*scale)/2, top = (geometry.size.height-height*scale)/2
            ForEach(report.points, id: \.id) { point in
                Circle().fill(point.cameraPoint == nil ? Color.orange : Color.green)
                    .frame(width: 4,height: 4)
                    .position(x: left+point.nativePixel.x*scale,y: top+point.nativePixel.y*scale)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct ShareFile: Identifiable { let id = UUID(); let url: URL }
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.view.accessibilityIdentifier = "captureShareSheet"
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

/// Diagnostic viewer only. The production haircut renderer is a later milestone.
private struct PointCloudView: UIViewRepresentable {
    let points: [Point3D]
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(Theme.paper)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.scene = SCNScene()
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let scene = SCNScene()
        let vertices = points.map { SCNVector3(Float($0.x), Float(-$0.y), Float(-$0.z)) }
        let source = SCNGeometrySource(vertices: vertices)
        let indices = Array(0..<UInt32(vertices.count))
        let data = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(data: data, primitiveType: .point, primitiveCount: vertices.count, bytesPerIndex: 4)
        element.pointSize = 2; element.minimumPointScreenSpaceRadius = 1; element.maximumPointScreenSpaceRadius = 3
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor(Theme.accent)
        geometry.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.zNear = 0.001
        scene.rootNode.addChildNode(camera)
        view.scene = scene; view.pointOfView = camera
        if !vertices.isEmpty {
            let center = vertices.reduce(SCNVector3Zero) { SCNVector3($0.x + $1.x, $0.y + $1.y, $0.z + $1.z) }
            view.defaultCameraController.target = SCNVector3(center.x / Float(vertices.count), center.y / Float(vertices.count), center.z / Float(vertices.count))
        }
    }
}
