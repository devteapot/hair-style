# Model guides mapped into the canonical editing pipeline

The pretrained HAAR template output now enters `HaircutRevision` through `ModelGuideImport`, with an explicit coordinate mapping, exact target-scalp bindings and regional length constraints. The recorded participant experiment retains all 763 source guides, applies two edits and compiles matching render derivatives. This connects real model geometry to the existing editing pipeline; it does not establish person-conditioned style generation or an accepted personal scalp.

## Import contract

`hair-model-import INPUT.json SOURCE_STRANDS.json MAPPING.json RESULT.json` accepts the ordered artifact emitted by `tools/inspect_haar_output.py`. The importer checks the exact source-file SHA-256, pinned model/adapter format, root-to-tip order, full guide count, and exact target scalp hash. Each mapping names the corresponding source guide, its anatomical region and a barycentric target root. Missing, duplicated or reordered guides fail import.

The request records a source center, target center in meters and positive per-axis scale. Every source curve is transformed by that mapping, then translated as a whole to its declared target root. Root correction is bounded by an explicit threshold, limited by the API to at most 30 mm. Exceeding it rejects the import rather than removing a guide. This is an unreviewed correspondence assertion, not a physical accuracy tolerance.

Curves exceeding the brief's regional maximum are trimmed along their existing arc. A curve shorter than the required minimum is rejected rather than stretched. Every decision records transformed/constrained length and root correction. The canonical validator checks final attachments, length limits, available-length conflicts and hashes. Generation provenance remains `model`, with a method containing the mapping-request hash; the request also binds the exact research source artifact.

The result always retains `acceptedForPersonalHaircut: false` and `personalizationBeyondFittingVerified: false`. Global fitting alone is not individual hairstyle design. Materials and region assignments remain diagnostic, and absent natural-hair observations remain unknown.

The optional [continuous inferred-envelope guard](ellipsoid-guide-guard.md) now provides bounded import corrections and remains bound into the design brief for later edits. The original experiment below predates that guard; current guarded results and rejected/accepted edits are recorded separately.

## Recorded participant experiment

`tools/propose_model_mapping.py` fits an axis-aligned ellipsoid to the upstream scalp vertices, maps it to the existing inferred target envelope and proposes nearest-triangle bindings. It creates a new UUID binding profile while preserving the target vertices, topology and inferred provenance exactly. The original scalp review document, observed face and phone data are not modified. Its coarse region rules are explicit heuristics, not measured hairline/part labels.

For the recorded 763-guide output:

- Root correction: median **1.535 mm**, p95 **4.601 mm**, maximum **9.752 mm**; none exceeded the requested 20 mm limit.
- All canonical root checks passed. Initial guide lengths were **35.4–144.5 mm**; current available lengths in all six regions remain unknown.
- A **30 mm fringe** edit changed 146 guides. A subsequent **20% crown tangent-volume reduction** changed 85 guides. Other regions, root bindings, model provenance and earlier saved revisions were preserved.
- Canonical meshes retained the exact revision hashes. Three-sided diagnostic tubes with radius scale 8 used 230,426 vertices before the fringe edit and 211,346 afterward, within the existing 250,000-vertex budget. No guide points were simplified. This is not a density-completed production hairstyle or a sustained device-performance result.
- The supplied partial observed face passed the 1 mm capsule-clearance check. Both ears are missing. This does not check a closed face volume or unseen geometry.
- A separate sampled analytic-cap diagnostic found two guides with points more than 1 mm inside the inferred envelope, maximum radial penetration **1.118 mm**. It is not an exact mesh signed-distance or between-sample test. The result remains unaccepted for personal use.

The six-view SceneKit comparison renders actual compiled revisions with face/scalp depth occlusion. The observed face is visibly rough and incomplete, the scalp remains a construction estimate, and the guide field is sparse. The private preview is `outputs/personal-model-mapping/comparison.png`; participant imagery is not copied into the public-facing evidence folder.

## Replay

Use new output directories. The proposal script invokes the existing Swift brief compiler through `tools/dev.sh`.

```sh
.research/metal-env/bin/python tools/propose_model_mapping.py \
  outputs/haar-metal-guides/research-strands.json outputs/scalp-candidate/result.json \
  .research/metal-assets/scalp/final_scalp.obj outputs/NEW-mapping
tools/dev.sh swift run capture-inspect hair-model-import \
  outputs/NEW-mapping/input.json outputs/haar-metal-guides/research-strands.json \
  outputs/NEW-mapping/mapping.json outputs/NEW-mapping/imported.json
```

The returned `haircut` uses the existing `hair-edit`, repository, clearance and mesh contracts. `hair-mesh INPUT.json HAIRCUT.json OUTPUT.json [RADIAL_SIDES] [DIAGNOSTIC_RADIUS_SCALE]` now exposes the existing compiler through the CLI. `tools/render_model_mapping.swift` renders two compiled revisions beside the same observed face/inferred scalp. All Swift tools run through `tools/dev.sh`.

## Verification and next work

All **84 core tests** pass. New tests cover source tampering, stale scalp hashes, negative scale, excessive root correction, missing/reordered guides, minimum-length conflicts, region-specific trimming and immutable edit replay. Independent Python checks verify the real transformed source curves, exact roots, unchanged scalp provenance, both edited regions, three saved revisions, compiler hashes and known closest-triangle cases. The unsigned iPhone SDK build passes; no new phone UI or installed build is claimed.

Aggregate evidence is in [the mapping verification record](evidence/model-guide-import-2026-09-10.json). Remaining work includes correspondence/region review, scalp clearance correction, accepted head/hairline reconstruction, observed-hair and personal-feature conditioning beyond fitting, native model-result editing, shared live preview and physical/quality evaluation. This experiment does not complete M1, M2 or M3.

Follow-up: the [continuous envelope guard](ellipsoid-guide-guard.md) and [native model review](native-model-review.md) now provide bounded inferred-envelope correction and on-device review/edit persistence. Anatomical acceptance, true person-conditioning and shared live preview remain unresolved.

## Fresh durable-generation candidates

Two newly generated candidates (“short wavy hair with a side part”, seeds 43 and 44) were tested against the same second-repeat face-derived brief and inferred scalp mapping. Only the source-artifact hash changed between mapping requests. Both actual 763-guide model outputs failed the unchanged 2 mm inferred-envelope correction limit: seed 43 at guide `haar-00032`, seed 44 at `haar-00364`. Neither emitted a canonical haircut result or changed phone data. The two-attempt experiment stopped without widening the limit.

For the first rejected nape guide, an independent analytic segment-minimum calculation after root attachment/regional trimming found normalized radius 0.970957 versus the permitted minimum 0.995235 before correction. This confirms inset crossing but does not independently replay the iterative correction budget or establish anatomical scalp accuracy. The bulk diagnostic attempt failed JSON serialization and is not evidence; the saved single-guide diagnostic completed successfully.

This is evidence that the present axis-scaled, translated mapping does not reliably accommodate fresh model curves. It does not isolate mapping error from generated geometry or the uncertain scalp estimate. Next investigate local attachment-frame orientation and model geometry before further seed retries. Source-seed provenance must also be carried from generation into the adapter/import record rather than inferred from a design-brief seed. No accepted personal hairstyle or aesthetic evaluation is claimed. [Sanitized attempt evidence](evidence/fresh-generation-fit-2026-09-11.json); private inputs and diagnostics remain under `outputs/fresh-generation-personal-fit/`.

## Model sampling seed provenance

Verified Metal run reports now retain the trajectory's actual `samplingSeed`, and the ordered-guide adapter carries it into the source artifact. Imported `HairGenerationRecord.modelSamplingSeed` records that value separately from `seed`, which remains bound to the design brief. Old source artifacts decode with unknown model sampling seed; no brief value is substituted. Previously saved revisions are not rewritten. The generation client requires the artifact seed to match its requested seed, and the durable worker rejects a mismatched adapter result.

All 123 core tests pass, including a model seed different from the brief seed and preservation across serialization/editing. Adapter checks cover known/unknown seeds and Boolean rejection; 15 backend tests and the iPhone SDK build pass. Reverification of the retained real 50-step output recovered seed 42, imported all 763 guides and produced geometry exactly identical to its prior personal-policy import. Personal fitting remains unaccepted. Private evidence is under `outputs/model-seed-provenance/`; no phone data or previous saved revisions changed.

## Optional root-frame rotation experiment

Mapping requests can opt into `maximumRootFrameRotationRadians` (0…π/2). This requires an explicit validated inferred-envelope guard. For each guide, the importer computes ellipsoid-gradient normals at the axis-scaled source root and target attachment, applies the unique minimal rigid rotation between them to root-relative points, then runs existing length/continuous-envelope validation. Roots remain attached and per-guide rotation angles are recorded; the source curve shape/arc length is preserved before trimming/guard correction. Missing/undefined normals or excessive angles reject the import. This does not measure natural hair growth direction. Omission preserves the previous mapping exactly.

A known 90° synthetic rotation verifies coordinates, arc length and rejection bounds; all 124 core tests and the iPhone SDK build pass. The two rejected real candidates were replayed with an explicit 30° research mapping limit and the unchanged 2 mm correction budget. Both still reject at the same guides. Independent calculations show only 0.0515° root-normal mismatch for seed 43's nape guide and 0.2883° for seed 44's crown guide. Their minimum normalized radii after rotation remain 0.970977 and 0.955476, below the permitted 0.995235; their axis-scaled curves already cross the inferred envelope before attachment. Segment lengths are preserved to within 3.7e-17 m in the independent replay.

This rejects simple attachment-normal mismatch as a sufficient explanation for these failures. It does not distinguish model-curve defects from template/envelope mismatch, anisotropic scaling or an inaccurate personal scalp estimate. No new personal candidate was accepted or installed. Further work should compare curves against the actual template scalp and evaluate deformation/constraints during generation; additional blind seed retries are not justified by this experiment. Private evidence: `outputs/fresh-generation-personal-fit/root-frame-verification.json`.

## Comparison with the actual upstream head

`tools/diagnose_template_guides.py` now compares selected ordered source curves with the original upstream head triangles, before any personal mapping, trimming or guard correction. It records closest-surface distances/oriented local offsets and double-sided segment/triangle intersections, with source/mesh hashes. The head mesh has 5,023 vertices, 9,976 triangles, 62 boundary edges and no nonmanifold edges by edge incidence. It is open, so the report does not assert global inside/outside classification or physical units.

Both first-rejected guides cross this actual template surface: seed 43's nape guide crosses on segment 11 at fraction 0.985282; seed 44's crown guide crosses on segment 93 at fraction 0.467505. Both also have a segment-zero hit only about 1e-5–3e-5 of the way from a root lying 1e-8–2e-8 source units from the surface; those near-root hits can reflect numerical precision and are not the substantive evidence. All four intersections were independently replayed by solving a 3×3 linear system, with interior triangle barycentrics and residuals no larger than 1.5e-17 source units.

The away-from-root crossings establish a generated-template geometry problem for these selected curves, independent of the personal ellipsoid mapping. This does not prove every guide is defective or identify whether constraints should be imposed during sampling, decoding or bounded curve optimization. The pipeline needs a template-surface constraint/validation stage before treating generic neural output as an eligible personal design. Existing personal fit checks remain unchanged; no rejected result was published as a haircut. Private reports and exact triangle/segment references are in `outputs/fresh-generation-personal-fit/template-intersection-verification.json`. No core/iOS code changed during this diagnostic, so their preceding tests were not repeated.

## Explicit conditioned-decoder artifacts

The importer now supports a separately named research format: `personal_envelope_decoder_latents_v1` with implementation `metal_decoder_personal_constraints_v1`. It is not accepted under the untouched HAAR adapter name. Its conditioning record binds the canonical full HairDesignInput and mapping geometry, plus original source, optimization report, regional-search report and decoder hashes. Mapping-geometry hashing excludes only output UUID, source-artifact hash and descriptive method to avoid circular identity; all numerical mapping parameters, attachments and guard bounds stay bound. `hair-conditioning-binding` emits the two canonical Swift hashes for the producer.

A conditioned artifact requires a recorded model sampling seed. Moving it to another brief or mapping is rejected. The normal source-order, root, length and envelope checks still run, and generation provenance names the conditioned route. The phone validates binding and resulting geometry; it does not replay neural optimization or authenticate report claims merely because their hashes are well-formed. `acceptedForPersonalHaircut` and `personalizationBeyondFittingVerified` remain false.

All 126 core tests pass, including stale brief/mapping rejection, and the iPhone SDK build passes. The actual 763-guide conditioned result was packaged with its matching second-repeat scalp-review evidence and loaded through native ModelReviewPackage preparation. An isolated simulator test confirmed six conflicting-attachment markers and the attachment-review message, then deleted its isolated review. The renderer and explicit enlarged-marker legend were visually inspected. The test uses a simulator-only storage directory and prepared-file name; the original saved review and physical phone were not replaced. Raw artifacts and screenshots remain under `outputs/conditioned-model-review/`.
