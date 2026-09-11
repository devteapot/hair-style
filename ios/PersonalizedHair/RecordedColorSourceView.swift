import SwiftUI
import HairCore

struct RecordedColorSourceView: View {
    let subjectSessionID: String
    let selected: (RecordedHairColor, HairRegion) -> Void
    @EnvironmentObject private var captures: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var region: HairRegion = .fringe
    @State private var sources: [Source] = []
    @State private var loading = true
    @State private var failures = 0
    private struct Source: Identifiable, Sendable {
        let id: String
        let color: RecordedHairColor
        let frameNumber: Int
        let date: Date
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Apply to", selection: $region) {
                        ForEach(HairRegion.allCases, id: \.self) { r in Text(name(r)).tag(r) }
                    }.accessibilityIdentifier("recordedColorRegion")
                    Text("Uses the recorded image color as an approximation. Lighting affects the result. Guide paths stay unchanged.")
                        .font(.footnote)
                }
                Section("Saved image reports for this person") {
                    if loading { ProgressView("Checking image reports…") }
                    else if sources.isEmpty { Text("No color reports are available. Import a hair analysis report in capture review first.") }
                    ForEach(sources) { source in
                        Button {
                            selected(source.color, region)
                        } label: {
                            HStack {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color(.sRGB, red: source.color.rgb[0]/255, green: source.color.rgb[1]/255, blue: source.color.rgb[2]/255))
                                    .frame(width: 32, height: 28)
                                VStack(alignment: .leading) {
                                    Text("Frame \(source.frameNumber)")
                                    Text(source.date, format: .dateTime.month().day().hour().minute()).font(.caption)
                                }
                            }
                        }.accessibilityIdentifier("recordedColorSource")
                    }
                    if failures > 0 {
                        Text("\(failures) saved reports could not be used. Reopen their capture review to check the evidence.").font(.footnote)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden).background(Theme.paper)
            .navigationTitle("Color from capture").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                let bundles = captures.passes.filter { $0.manifest.subjectSessionID == subjectSessionID }.map(\.url)
                let result = await Task.detached { () -> ([Source], Int) in
                    var values: [Source] = [], invalid = 0
                    for bundle in bundles {
                        if Task.isCancelled { break }
                        do {
                            let manifest = try CaptureBundle.load(bundle)
                            for (index, frame) in manifest.frames.enumerated() {
                                if Task.isCancelled { break }
                                do {
                                    if let color = try RecordedHairColor.saved(bundle: bundle, frameID: frame.metadata.id),
                                       color.subjectSessionID == subjectSessionID {
                                        values.append(Source(id: manifest.id+frame.metadata.id, color: color, frameNumber: index+1, date: manifest.createdAt))
                                    }
                                } catch { invalid += 1 }
                            }
                        } catch { invalid += 1 }
                    }
                    return (values, invalid)
                }.value
                guard !Task.isCancelled else { return }
                sources = result.0; failures = result.1; loading = false
            }
        }
    }
    private func name(_ region: HairRegion) -> String {
        switch region {
        case .fringe: return "Fringe"
        case .top: return "Top"
        case .crown: return "Crown"
        case .anatomicalLeft: return "Left side"
        case .anatomicalRight: return "Right side"
        case .nape: return "Nape"
        }
    }
}
