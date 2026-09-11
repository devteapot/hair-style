import SwiftUI
import HairCore

/// Compare render derivatives without changing the saved design or its guides.
struct HairRepresentationComparisonView: View {
    let record: StoredHaircut
    let observedFace: CanonicalObservedSurface?
    @State private var meshes: [CompiledHairMesh] = []
    @State private var selection = 0
    @State private var resetCamera = 0
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Same haircut, two renderers").font(.headline)
                Text("Both use the same guide paths and material colors. Width is enlarged eight times for inspection; it does not represent measured hair density.").font(.footnote)
                if meshes.count == 2 {
                    Picker("Renderer",selection:$selection) {
                        Text("Tubes").tag(0)
                        Text("Ribbons").tag(1)
                    }.pickerStyle(.segmented).accessibilityIdentifier("hairRendererPicker")
                    let mesh=meshes[selection]
                    HairGuideScene(record:record,resetCamera:resetCamera,observedFace:observedFace,preparedMesh:mesh)
                        .frame(height:320)
                        .accessibilityLabel("Hair renderer comparison")
                        .accessibilityIdentifier("hairRendererComparisonScene")
                    Button("Reset view") { resetCamera += 1 }
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
}
