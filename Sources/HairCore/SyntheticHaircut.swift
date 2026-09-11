import Foundation

/// A curved-guide engineering fixture, not a generated personalized hairstyle.
public enum SyntheticHaircut {
    public static func create() throws -> (input: HairDesignInput, haircut: HaircutRevision) {
        let scalp = ScalpProfile(id: UUID().uuidString, revision: 1, subjectSessionID: "synthetic-haircut",
            vertices: [Point3D(x: -0.1,y: 0.1,z: -0.1), Point3D(x: 0.1,y: 0.1,z: -0.1),
                       Point3D(x: 0.1,y: 0.1,z: 0.1), Point3D(x: -0.1,y: 0.1,z: 0.1)],
            triangles: [[0,2,1], [0,3,2]], triangleOrigins: [.synthetic,.synthetic],
            sourceSHA256: [EvidenceHash.sha256(Data("synthetic-scalp-plane-v1".utf8))], method: "synthetic plane; not head reconstruction")
        let profile = HairLengthProfile(id: UUID().uuidString, revision: 1, subjectSessionID: scalp.subjectSessionID,
            regions: [RegionalLengthObservation(region: .fringe, maximumAvailableMeters: nil, origin: .unknown,
                quality: .unknown, evidenceReferences: [], method: "unknown fixture length"),
                RegionalLengthObservation(region: .crown, maximumAvailableMeters: 0.2, origin: .userSupplied,
                quality: .medium, evidenceReferences: ["synthetic-value"], method: "fixture value; not participant evidence")])
        let brief = HairDesignBrief(id: UUID().uuidString, scalpSHA256: try HairArtifactHash.digest(scalp),
            hairProfileSHA256: try HairArtifactHash.digest(profile), mode: .autonomous,
            lengthLimits: [.fringe,.crown].map { RegionalLengthLimit(region: $0, minimumMeters: 0.005,
                maximumMeters: 0.3, origin: .defaultValue) }, allowGrowth: false, stylingAssumptions: [], seed: 42)
        let guides = try [HairRegion.fringe,.crown].enumerated().map { index, region in
            let root = ScalpBinding(triangleIndex: index, barycentric: [0.2,0.3,0.5], normalOffsetMeters: 0.0001)
            let p = try HaircutValidator.attachment(root, scalp: scalp).position
            return HairGuide(id: region.rawValue, region: region, materialID: "dark",
                root: root, points: [p, p+Point3D(x: 0.01,y: 0.025,z: 0.02),
                    p+Point3D(x: 0.025,y: 0.06,z: 0.055), p+Point3D(x: 0.04,y: 0.07,z: 0.1)])
        }
        let haircut = HaircutRevision(id: UUID().uuidString, revision: 1, scalpSHA256: brief.scalpSHA256,
            hairProfileSHA256: brief.hairProfileSHA256, briefSHA256: try HairArtifactHash.digest(brief),
            generation: HairGenerationRecord(origin: .syntheticFixture, method: "curved-guide-fixture", version: "1", seed: 42),
            materials: [HairMaterial(id: "dark", linearRGB: [0.03,0.02,0.01], roughness: 0.45, radiusMeters: 0.00005)], guides: guides)
        return (HairDesignInput(scalp: scalp, hairProfile: profile, brief: brief), haircut)
    }
}
