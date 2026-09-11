import SwiftUI
import AVFoundation
import HairCore

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var recording = false
    @Published var preparing = false
    @Published var lastUpdate: CaptureUpdate?
    @Published var error: String?
    private let engine = CaptureEngine()
    private var startRequest = UUID()
    var onFinish: (() -> Void)?

    init() {
        engine.onUpdate = { [weak self] update in self?.lastUpdate = update }
        engine.onStarted = { [weak self] _ in self?.recording = true; self?.preparing = false }
        engine.onStopped = { [weak self] _ in
            self?.recording = false; self?.preparing = false; self?.onFinish?()
        }
        engine.onError = { [weak self] message in self?.error = message }
    }

    func start(kind: CaptureKind, store: SessionStore, denseFrontSampling: Bool = false, trackedFrontCapture: Bool = false, hairCondition: HairCaptureCondition = .unknown) async {
        guard !recording && !preparing else { return }
        preparing = true; error = nil; lastUpdate = nil
        let request = UUID()
        startRequest = request
        let permitted = await AVCaptureDevice.requestAccess(for: .video)
        // Permission can resolve after the view disappears or the app backgrounds.
        guard startRequest == request else { return }
        guard permitted else { preparing = false; error = "Camera access is off. Enable it in Settings to capture your head."; return }
        engine.start(kind: kind, root: store.root, subjectSessionID: store.subjectSessionID, device: DeviceCapabilities.report(), denseFrontSampling: denseFrontSampling, trackedFrontCapture: trackedFrontCapture, hairCondition: hairCondition)
    }

    func stop(interrupted: Bool = false) {
        startRequest = UUID()
        preparing = false
        engine.stop(interrupted: interrupted, note: interrupted ? "Capture paused when the app left the foreground." : nil)
    }
}

struct CaptureView: View {
    let kind: CaptureKind
    @EnvironmentObject var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = CaptureViewModel()
    @State private var consent = false
    @State private var denseFrontSampling = false
    @State private var trackedFrontCapture = false
    @State private var hairCondition: HairCaptureCondition = .unknown

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(kind.guidance).font(.title3).foregroundStyle(.secondary)
                ZStack {
                    RoundedRectangle(cornerRadius: 28).fill(Color.black.opacity(0.94))
                    if let update = model.lastUpdate, let image = UIImage(data: update.jpeg), let cgImage = image.cgImage {
                        Image(uiImage: UIImage(cgImage: cgImage, scale: 1, orientation: kind == .frontFace ? .leftMirrored : .right))
                            .resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 28))
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: kind.symbol).font(.system(size: 64, weight: .ultraLight))
                            Text(model.preparing ? "Preparing camera…" : "Your camera opens when you start.")
                                .font(.callout).multilineTextAlignment(.center)
                        }.foregroundStyle(.white.opacity(0.8)).padding()
                    }
                }.frame(height: 340).accessibilityLabel("Capture camera preview")

                if let update = model.lastUpdate {
                    HStack {
                        Label("\(update.frameCount) frames saved", systemImage: "checkmark.circle")
                        Spacer()
                        if let fraction = update.metadata.quality.validDepthFraction {
                            Text("\(Int(fraction * 100))% depth valid").monospacedDigit()
                        }
                    }.font(.caption)
                    Text("Frames are saved locally. Depth validity is a sensor check, not a complete scan-quality score.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("captureError") }

                Picker("Hair in this recording", selection: $hairCondition) {
                    Text("Not specified").tag(HairCaptureCondition.unknown)
                    Text("Tied or pinned back").tag(HairCaptureCondition.tied)
                    Text("Loose").tag(HairCaptureCondition.untied)
                }
                .foregroundStyle(Theme.ink)
                .disabled(model.recording || model.preparing)
                .accessibilityIdentifier("captureHairCondition")
                if kind == .naturalHair {
                    Text("For natural shape and texture, leave your hair loose and dry. Your selection is saved with this recording.")
                        .font(.footnote).foregroundStyle(Theme.ink)
                }
                if kind == .frontFace {
                    Toggle("Retain head tracking (experimental)", isOn: $trackedFrontCapture)
                        .disabled(model.recording || model.preparing)
                        .accessibilityIdentifier("trackedFrontCapture")
                    if trackedFrontCapture {
                        Text("Records a face-tracking estimate with depth. Keep one face visible. This mode still needs a physical calibration check.")
                            .font(.footnote).foregroundStyle(Theme.ink)
                    }
                    Toggle("Record more frames during turns", isOn: $denseFrontSampling)
                        .disabled(model.recording || model.preparing)
                        .accessibilityIdentifier("denseFrontSampling")
                    Text(denseFrontSampling
                        ? "Experimental: requests up to 15 saved frames per second. Uses roughly five times the storage and reaches the 900-frame limit sooner. Turn slowly; this does not remove motion blur."
                        : "Saves about 3 frames per second. For reconstruction experiments, denser recording can retain closer views during turns.")
                        .font(.footnote).foregroundStyle(Theme.ink)
                }
                if !model.recording {
                    Toggle("I’m the adult subject and agree to this local capture.", isOn: $consent)
                    Text("Nothing is uploaded. You can review, export or delete your capture. This build records evidence; head reconstruction and haircut generation are still being implemented.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    if model.recording { model.stop() }
                    else { Task { await model.start(kind: kind, store: store, denseFrontSampling: denseFrontSampling, trackedFrontCapture: trackedFrontCapture, hairCondition: hairCondition) } }
                } label: {
                    Label(model.recording ? "Finish capture" : "Start capture", systemImage: model.recording ? "stop.fill" : "record.circle")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).tint(model.recording ? .red : Theme.ink)
                    .disabled(model.preparing || (!consent && !model.recording))
                    .accessibilityIdentifier("captureButton")
            }.padding(24)
        }
        .background(Theme.paper)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.onFinish = { store.reload() } }
        .onDisappear { model.stop(interrupted: true) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stop(interrupted: true) } }
    }
}
