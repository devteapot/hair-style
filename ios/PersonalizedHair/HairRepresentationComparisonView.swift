import SwiftUI
import HairCore
import Darwin

/// Compare render derivatives without changing the saved design or its guides.
struct HairRepresentationComparisonView: View {
    @Environment(\.scenePhase) private var scenePhase
    let record: StoredHaircut
    let observedFace: CanonicalObservedSurface?
    @State private var meshes: [CompiledHairMesh] = []
    @State private var selection = 0
    @State private var resetCamera = 0
    @State private var error: String?
    @State private var timing: LiveRenderTimingDelegate?
    @State private var timer: Task<Void,Never>?
    @State private var duration = 10
    @State private var reports: [Int:ComparisonTimingRun] = [:]
    @State private var exportURL: URL?
    @State private var viewport = CGSize.zero

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Same haircut, two renderers").font(.headline)
                Text("Both use the same guide paths and material colors. Width is enlarged eight times for inspection; it does not represent measured hair density.").font(.footnote)
                if meshes.count == 2 {
                    Picker("Renderer",selection:$selection) {
                        Text("Tubes").tag(0)
                        Text("Ribbons").tag(1)
                    }.pickerStyle(.segmented).disabled(timing != nil).accessibilityIdentifier("hairRendererPicker")
                    let mesh=meshes[selection]
                    HairGuideScene(record:record,resetCamera:resetCamera,observedFace:observedFace,preparedMesh:mesh,timingDelegate:timing)
                        .frame(height:320)
                        .onGeometryChange(for:CGSize.self) { $0.size } action: { size in
                            if viewport != .zero,viewport != size { stopTiming(reason:"viewport_changed") }
                            viewport=size
                        }
                        .accessibilityLabel("Hair renderer comparison")
                        .accessibilityIdentifier("hairRendererComparisonScene")
                    Button("Reset view") { resetCamera += 1 }
                        .disabled(timing != nil)
                    HStack {
                        Button(timing == nil ? "Record \(duration) seconds" : "Stop recording") {
                            if timing == nil { startTiming() } else { stopTiming(reason:"user_stopped") }
                        }.accessibilityIdentifier("recordRendererTiming")
                        if timing != nil { Text("Recording…").font(.caption) }
                    }
                    Picker("Recording duration",selection:$duration) {
                        Text("10 sec").tag(10);Text("1 min").tag(60);Text("5 min").tag(300)
                    }.pickerStyle(.segmented).disabled(timing != nil)
                    if let report=reports[selection] {
                        Text("\(report.callbacks.observedCallbackCount) callbacks · p95 \(report.callbacks.retainedP95IntervalSeconds.map { String(format:"%.1f ms",$0*1000) } ?? "unavailable")")
                            .font(.caption.monospacedDigit()).accessibilityIdentifier("rendererTimingSummary")
                        Button("Prepare comparison timing export") { prepareExport() }
                            .disabled(timing != nil).accessibilityIdentifier("exportRendererTiming")
                    }
                    if let exportURL { ShareLink("Share timing report",item:exportURL).accessibilityIdentifier("shareRendererTiming") }
                    Text("Keep the preview visible while recording. These are SceneKit callback intervals, not GPU completion times or displayed FPS. Export includes renderer, device environment and thermal state; no images or face coordinates.").font(.footnote)
                    if Self.simulator { Text("Simulator timing cannot establish phone performance.").font(.footnote) }
                    if let error { Text(error).foregroundStyle(Theme.ink) }
                    Text("\(mesh.vertices.count) vertices · \(mesh.batches.reduce(0) { $0+$1.indices.count/3 }) triangles")
                        .font(.caption.monospacedDigit()).accessibilityIdentifier("hairRendererGeometryCount")
                    Text("Revision \(mesh.haircutRevision) · \(mesh.haircutSHA256.prefix(12))")
                        .font(.caption.monospaced()).accessibilityIdentifier("hairRendererRevision")
                    Text("Ribbons are flat, double-sided strips and can disappear edge-on. Tubes have a round cross-section. Fewer vertices alone do not prove faster rendering; phone frame rate and thermal behavior still need measurement.").font(.footnote)
                    Text("This comparison does not change your saved haircut or the live preview renderer.").font(.footnote)
                } else if let error {
                    Text(error).foregroundStyle(Theme.ink).accessibilityIdentifier("hairRendererComparisonError")
                } else {
                    ProgressView("Preparing both renderers…")
                }
            }.padding(24)
        }.background(Theme.paper).foregroundStyle(Theme.ink).navigationTitle("Preview comparison")
        .onChange(of:scenePhase) { _,phase in if phase != .active { stopTiming(reason:"app_inactive") } }
        .onDisappear { stopTiming(reason:"view_closed");clearExport() }
        .task {
            guard meshes.isEmpty else { return }
            let record=record
            let worker=Task.detached(priority:.userInitiated) {
                let tube=try HairMeshCompiler.compile(input:record.input,haircut:record.haircut,radialSides:3,radiusScale:8)
                try Task.checkCancellation()
                let ribbon=try HairRibbonCompiler.compile(input:record.input,haircut:record.haircut,radiusScale:8)
                return [tube,ribbon]
            }
            do {
                let prepared=try await withTaskCancellationHandler(operation:{ try await worker.value },onCancel:{ worker.cancel() })
                try Task.checkCancellation()
                meshes=prepared
            } catch {
                if !Task.isCancelled { self.error=error.localizedDescription }
            }
        }
    }

    private func startTiming() {
        guard meshes.count == 2,timing == nil else { return }
        do {
            error=nil
            clearExport();reports[selection]=nil
            timing=try LiveRenderTimingDelegate(haircutSHA256:meshes[selection].haircutSHA256,context:.rendererComparison)
            let seconds=duration
            timer=Task {
                do { try await Task.sleep(for:.seconds(seconds)) } catch { return }
                guard !Task.isCancelled else { return }
                stopTiming(reason:"duration_elapsed")
            }
        } catch { self.error=error.localizedDescription }
    }
    private func stopTiming(reason:String) {
        timer?.cancel();timer=nil
        guard let timing,let callbacks=timing.stop(),meshes.indices.contains(selection) else { self.timing=nil;return }
        self.timing=nil
        let mesh=meshes[selection]
        reports[selection]=ComparisonTimingRun(meshMethod:mesh.method,vertexCount:mesh.vertices.count,
            triangleCount:mesh.batches.reduce(0) { $0+$1.indices.count/3 },radiusScale:mesh.radiusScale,
            requestedSeconds:duration,stopReason:reason,viewportWidthPoints:viewport.width,viewportHeightPoints:viewport.height,
            simulator:Self.simulator,deviceDescription:UIDevice.current.model,osVersion:UIDevice.current.systemVersion,
            deviceModelIdentifier:Self.deviceModelIdentifier,
            appBuild:Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown",
            observedFaceTriangleCount:observedFace?.triangles.count ?? 0,scalpTriangleCount:record.input.scalp.triangles.count,
            syntheticHaircut:record.haircut.generation.origin == .syntheticFixture,callbacks:callbacks)
    }
    private func prepareExport() {
        do {
            let report=ComparisonTimingExport(runs:reports.keys.sorted().compactMap { reports[$0] })
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("renderer-comparison-"+UUID().uuidString+".json")
            try ManifestCoding.encoder().encode(report).write(to:url,options:[.atomic,.completeFileProtection])
            clearExport();exportURL=url
            error=nil
        } catch { self.error=error.localizedDescription }
    }
    private func clearExport() {
        if let exportURL { try? FileManager.default.removeItem(at:exportURL) };exportURL=nil
    }
    private static var simulator:Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    private static var deviceModelIdentifier:String {
        #if targetEnvironment(simulator)
        if let model=ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return String(model.prefix(64)) }
        #endif
        var info=utsname()
        guard uname(&info)==0 else { return "unknown" }
        let capacity=MemoryLayout.size(ofValue:info.machine)
        return withUnsafePointer(to:&info.machine) { pointer in
            pointer.withMemoryRebound(to:CChar.self,capacity:capacity) { String(cString:$0) }
        }
    }
}

private struct ComparisonTimingRun: Encodable {
    var meshMethod:String
    var vertexCount:Int
    var triangleCount:Int
    var radiusScale:Double
    var requestedSeconds:Int
    var stopReason:String
    var viewportWidthPoints:Double
    var viewportHeightPoints:Double
    var simulator:Bool
    var deviceDescription:String
    var osVersion:String
    var deviceModelIdentifier:String
    var appBuild:String
    var observedFaceTriangleCount:Int
    var scalpTriangleCount:Int
    var syntheticHaircut:Bool
    var callbacks:RenderTimingReport
}
private struct ComparisonTimingExport: Encodable {
    var method="interactive_renderer_comparison_callbacks_v1"
    var requestedCallbackRateHz=60
    var multisampleCount=4
    var standardizedCameraPath=false
    var sustainedPerformanceVerified=false
    var runs:[ComparisonTimingRun]
}
