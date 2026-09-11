import SwiftUI
import HairCore

enum Theme {
    static let paper = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let ink = Color(red: 0.13, green: 0.23, blue: 0.24)
    static let accent = Color(red: 0.18, green: 0.40, blue: 0.36)
    static let secondaryInk = Color(red: 0.29, green: 0.36, blue: 0.36)
}

@main
struct PersonalizedHairApp: App {
    @StateObject private var store = SessionStore()
    var body: some Scene {
        WindowGroup {
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--credential-probe-write") || ProcessInfo.processInfo.arguments.contains("--credential-probe-read") {
                CredentialProbeView()
            } else {
                HomeView().environmentObject(store).tint(Theme.accent).preferredColorScheme(.light)
            }
            #else
            HomeView().environmentObject(store).tint(Theme.accent).preferredColorScheme(.light)
            #endif
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: SessionStore
    private let report = DeviceCapabilities.report()
    @State private var addingFixture = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 43.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PERSONALIZED HAIR").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(Theme.accent)
                        Text("A cut that\nstarts with you.")
                            .font(.system(size: titleSize, weight: .regular, design: .serif)).tracking(-1).foregroundStyle(Theme.ink)
                        Text("First, get to know your head and hair.")
                            .font(.title3).foregroundStyle(Theme.secondaryInk)
                    }.padding(.top, 12)

                    if report.eligible {
                        Label("Your camera system is supported", systemImage: "checkmark.seal")
                            .font(.subheadline).foregroundStyle(Theme.accent)
                        VStack(spacing: 0) {
                            ForEach(Array(CaptureKind.allCases.enumerated()), id: \.element) { index, kind in
                                NavigationLink { CaptureView(kind: kind) } label: {
                                    HStack(spacing: 16) {
                                        Text(String(format: "%02d", index + 1)).font(.caption.monospaced()).foregroundStyle(Theme.secondaryInk)
                                        Image(systemName: kind.symbol).frame(width: 26).font(.title2)
                                        Text(kind.title).font(.headline)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption)
                                    }.foregroundStyle(Theme.ink).padding(.vertical, 22).padding(.horizontal, 18)
                                }
                                if index < CaptureKind.allCases.count - 1 { Divider().padding(.leading, 60) }
                            }
                        }.background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Capture needs a compatible iPhone", systemImage: "camera.metering.unknown")
                                .font(.headline).accessibilityIdentifier("capabilityNotice")
                            Text(report.isSimulator ? "The simulator can review test evidence, but it has no TrueDepth or LiDAR camera." : "This preview requires front TrueDepth, rear LiDAR and face tracking. You can still inspect saved evidence.")
                                .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        }.padding(20).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Your captures").font(.title2.weight(.medium))
                            Spacer()
                            Text("\(store.passes.count)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondaryInk)
                        }
                        if store.passes.isEmpty {
                            Text("Saved passes will appear here for review and export.")
                                .foregroundStyle(Theme.secondaryInk).padding(.vertical, 14)
                        }
                        ForEach(store.passes) { pass in
                            NavigationLink { PassReviewView(pass: pass) } label: {
                                HStack {
                                    Image(systemName: pass.manifest.source == .syntheticFixture ? "cube.transparent" : pass.manifest.kind.symbol).font(.title2).frame(width: 36)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pass.manifest.source == .syntheticFixture ? "Calibration fixture" : pass.manifest.kind.title).font(.headline)
                                        Text("\(pass.manifest.frames.count) frames · \(pass.manifest.source == .syntheticFixture ? "Synthetic" : pass.manifest.status.rawValue)")
                                            .font(.caption).foregroundStyle(Theme.secondaryInk)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }.foregroundStyle(Theme.ink).padding(18)
                                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                            }.accessibilityIdentifier("savedPass")
                        }
                    }

                    DisclosureGroup("Capture lab") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("\(report.model)\n\(report.osVersion)").font(.caption.monospaced())
                            Text("Capture and replay are available in this build. Personalized generation is not connected yet.")
                                .font(.footnote).foregroundStyle(Theme.secondaryInk)
                            Button(addingFixture ? "Creating fixture…" : "Create synthetic calibration fixture") {
                                addingFixture = true
                                Task { await store.addFixture(); addingFixture = false }
                            }.disabled(addingFixture).accessibilityIdentifier("createFixture")
                            NavigationLink("Open reconstructed head") { HeadPreviewView() }
                                .accessibilityIdentifier("openHeadPreview")
                            NavigationLink("Review estimated scalp") { ScalpReviewView() }
                                .accessibilityIdentifier("openScalpReview")
                            NavigationLink("Open synthetic guide studio") { HairLabView() }
                                .accessibilityIdentifier("openHairLab")
                            NavigationLink("Review generated hair") { HairLabView(modelReview:true) }.accessibilityIdentifier("openModelReview")
                            NavigationLink("Saved candidates") { CandidateStudioLibraryView() }.accessibilityIdentifier("savedCandidateStudios")
                            NavigationLink("Open live preview lab") { LivePreviewView() }
                                .accessibilityIdentifier("openLiveLab")
                        }.padding(.top, 12)
                    }
                    if let error = store.error { Text(error).foregroundStyle(.red).font(.footnote) }
                }.padding(24)
            }.background(Theme.paper).navigationBarHidden(true)
        }
    }
}

#if targetEnvironment(simulator)
private struct CredentialProbeView: View {
    @State private var status = "Checking synthetic Keychain fixture…"
    var body: some View {
        Text(status).accessibilityIdentifier("credentialProbeStatus").task {
            do {
                let endpoint = URL(string: "https://credential-probe.invalid")!
                let equivalent = URL(string: "https://CREDENTIAL-PROBE.invalid:443/")!
                let other = URL(string: "https://credential-probe.invalid:8443")!
                let vault = ProcessingCredentialStore()
                let fixture = try GuestCredential(owner: "00000000-0000-0000-0000-000000000001",
                    token: "synthetic_test_only_01234567890123456789012345")
                if ProcessInfo.processInfo.arguments.contains("--credential-probe-write") {
                    try vault.save(fixture, endpoint: endpoint)
                    status = "Synthetic credential saved"
                } else {
                    let loaded = try vault.load(endpoint: equivalent)
                    guard loaded?.owner == fixture.owner, loaded?.token == fixture.token,
                          try vault.load(endpoint: other) == nil else { throw CaptureError.invalid("Credential isolation failed") }
                    try vault.remove(endpoint: endpoint)
                    guard try vault.load(endpoint: endpoint) == nil else { throw CaptureError.invalid("Credential deletion failed") }
                    status = "Credential restored, isolated and deleted"
                }
            } catch { status = "Credential probe failed: \(error.localizedDescription)" }
        }
    }
}
#endif
