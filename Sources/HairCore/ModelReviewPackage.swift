import Foundation

/// Local research handoff. Contains the actual ordered model artifact and
/// original scalp-review evidence so the phone can replay, rather than trust,
/// the import and face/scalp correspondence.
public struct ModelReviewPackage: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var input: HairDesignInput
    public var sourceArtifactData: Data
    public var mapping: ModelGuideImportRequest
    public var scalpReview: ScalpReviewDocument
    public var researchRevision: ResearchReviewRevision? = nil

    public func prepare() throws -> PreparedModelReview {
        guard schemaVersion==1,sourceArtifactData.count<=64_000_000,
              let guardRequest=input.brief.envelopeGuard else {
            throw CaptureError.invalid("Model review requires a bounded source artifact and retained envelope guard.")
        }
        let completion=try scalpReview.latestResult()
        guard input.scalp.subjectSessionID==completion.request.subjectSessionID,
              input.scalp.coordinateConvention==completion.scalp.coordinateConvention,
              try HairArtifactHash.digest(input.scalp.vertices)==HairArtifactHash.digest(completion.scalp.vertices),
              input.scalp.triangles==completion.scalp.triangles,
              input.scalp.triangleOrigins==completion.scalp.triangleOrigins,
              completion.scalp.sourceSHA256.allSatisfy({input.scalp.sourceSHA256.contains($0)}),
              try HairArtifactHash.digest(guardRequest.envelope)==HairArtifactHash.digest(completion.request.envelope) else {
            throw CaptureError.invalid("Recorded face, reviewed scalp and model binding profile do not match.")
        }
        let imported=try ModelGuideImport.apply(sourceData:sourceArtifactData,input:input,request:mapping)
        let haircut: HaircutRevision
        if let revision = researchRevision {
            guard revision.sourceImportSHA256 == imported.validation.haircutSHA256,
                  revision.haircutSHA256 == (try HairArtifactHash.digest(revision.haircut)),
                  !revision.method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  revision.method.count <= 4096,
                  revision.haircut.id != imported.haircut.id,
                  revision.haircut.revision == 1, revision.haircut.parentSHA256 == nil, revision.haircut.edit == nil,
                  revision.haircut.generation.origin == .model,
                  revision.haircut.guides.map(\.id) == imported.haircut.guides.map(\.id),
                  revision.haircut.guides.map(\.region) == imported.haircut.guides.map(\.region),
                  revision.haircut.guides.map(\.materialID) == imported.haircut.guides.map(\.materialID),
                  try HairArtifactHash.digest(revision.haircut.materials) == HairArtifactHash.digest(imported.haircut.materials) else {
                throw CaptureError.invalid("Research revision must retain its source import, guide identities and materials, with a separate immutable identity.")
            }
            _ = try HaircutValidator.validate(input: input, haircut: revision.haircut)
            haircut = revision.haircut
        } else { haircut = imported.haircut }
        let mesh=try HairMeshCompiler.compile(input:input,haircut:haircut,radialSides:3,radiusScale:8)
        return PreparedModelReview(input:input,imported:imported,observedFace:completion.observed,mesh:mesh,haircut:haircut,scalpReview:scalpReview,researchMethod:researchRevision?.method)
    }

    /// The reviewed source may already be conditioned. Regeneration consumes
    /// its original sample/latent pair, retaining this package's mapping geometry.
    /// Resolve this declared reference after `prepare()`; it does not replay model computation.
    public func regenerationSampleSHA256() throws -> String {
        guard EvidenceHash.sha256(sourceArtifactData)==mapping.sourceArtifactSHA256 else {
            throw CaptureError.invalid("Reviewed model source bytes changed.")
        }
        let source=try ManifestCoding.decoder().decode(ResearchStrandArtifact.self,from:sourceArtifactData)
        if source.method == "personal_envelope_decoder_latents_v1" {
            guard source.implementation == "metal_decoder_personal_constraints_v1",
                  let hash=source.conditioning?.baseSourceSHA256,HairArtifactHash.valid(hash) else {
                throw CaptureError.invalid("Conditioned source lacks its original model sample reference.")
            }
            return hash
        }
        guard source.method == "pinned_haar_flattened_guides_adapter_v1",source.conditioning == nil else {
            throw CaptureError.invalid("Unsupported regeneration source.")
        }
        return mapping.sourceArtifactSHA256
    }
}

public struct PreparedModelReview: Sendable {
    public var input: HairDesignInput
    public var imported: ModelGuideImportResult
    public var observedFace: CanonicalObservedSurface
    public var mesh: CompiledHairMesh
    public var haircut: HaircutRevision
    public var scalpReview: ScalpReviewDocument
    public var researchMethod: String? = nil
}

/// Declared research provenance, not proof that the fitting algorithm was replayed.
/// Canonical validation and displayed-face clearance are independently recomputed.
public struct ResearchReviewRevision: Codable, Sendable {
    public var sourceImportSHA256: String
    public var haircutSHA256: String
    public var method: String
    public var haircut: HaircutRevision
}
