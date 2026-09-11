# Native generated-hair review

Open **Capture lab → Review generated hair** on the paired phone. The installed build contains the 763-guide guarded model result on its inferred scalp, together with the fixed recorded face. The phone is left at saved revision 1. No camera recording or physical-phone edit was performed during verification.

This is a native review of real model output, with explicit fit limitations. It remains a generic generated style mapped to an inferred head, not a completed person-conditioned recommendation or photorealistic preview.

## Local handoff and verification

`ModelReviewPackage` contains the exact ordered research artifact, canonical design input, mapping request and original `ScalpReviewDocument`. Preparing it replays the anatomical/scalp construction and model import. It verifies subject and source hashes, exact target geometry/provenance, retained envelope parameters and canonical haircut validation before compiling the mesh. The app does not trust a precomputed “passed” flag from a desktop report.

The example package is about 14.5 MB. The file importer caps packages at 100 MB and the core model artifact at 64 MB. An app-owned staged `Documents/model-review.json` can be loaded once; after successful import it is consumed. A package selected from Files is read under its security-scoped grant and its external source is retained.

The review is stored under Application Support/ModelHairLab, independently of the synthetic studio, camera captures and separate scalp review. Its package, immutable revisions and selection use complete file protection and backup exclusion. An existing review cannot be replaced by a new import; deletion is an explicit UI action. Restore replays the package and verifies that saved history still matches its exact original haircut and input.

## Viewer and edits

- Orbit, pinch and reset the 3D view; the face remains fixed as hair revisions change.
- Gray shows the recorded face, amber the inferred scalp and green the fringe. Sparse guides use an explicitly enlarged diagnostic radius. The scalp and rough face patch remain visible as evidence limitations.
- Preview fringe shortening, less crown volume or more crown volume. The persistent envelope guard rejects edits that violate its inferred-geometry constraint. Validation does not silently repair a saved edit.
- Save/discard, compare with the original, undo/redo and restore the selected revision after relaunch.
- Delete the imported review and its edits while retaining the original camera captures and separate scalp review.

Import, validation, edit computation, history replay and model mesh compilation run away from the main actor. Main-thread SceneKit presentation consumes prepared meshes. The model viewer uses the existing bounded three-sided compiler with diagnostic radius scale 8; the synthetic viewer keeps its original small-fixture settings. No sustained FPS, thermal or edit-latency target is claimed by the UI tests.

Explanatory text was darkened after inspecting the first simulator screenshot. The final physical screenshot was inspected for readable text, visible geometry and revision state. The source face is visibly rough/incomplete, and this view does not improve or certify that reconstruction.

## Verified flows

The actual model package passed a simulator flow covering import, 763-guide rendering, fringe edit/save, rejection of a crown reduction, crown enlargement/save, undo/redo, relaunch and original comparison. Direct storage inspection found revision 3, three immutable records, a retained guard and a consumed staging file.

A separate simulator deletion test removed the model review, relaunched to an empty review screen and confirmed the app-owned staging file was absent. Direct hashes confirmed the separate scalp review and reconstructed-head file were unchanged where present.

The signed app and package were installed on the paired iPhone 15 Pro. The physical test loaded the package, displayed revision 1 and rotated the scene without editing it. Reading back the saved package/input/haircut matched the prepared desktop data exactly. Participant screenshots and geometry stay under ignored `outputs/` paths.

All 90 core tests pass, including package replay and rejection of wrong subjects, changed source evidence, mismatched scalp geometry and missing guards. Aggregate evidence: [native model review verification](evidence/native-model-review-2026-09-10.json).

## Reproduction and outstanding scope

The prepared private package is `outputs/personal-model-guarded-v2/model-review.json`. The desktop command `tools/dev.sh swift run capture-inspect model-review-check PACKAGE.json REPORT.json` exercises the same core preparation used by the phone. Staged UI tests are selected explicitly and require their documented package/history setup; the physical test preserves revision 1, while the editing/deletion experiments run only on the simulator.

This advances the interactive-viewer path. Live-view parity, person-dependent generation beyond fitting, natural-hair observations, accepted reconstruction, realistic density/materials, supported-device performance and broader quality evaluation remain unfinished. No M1–M5 gate is declared complete.

## Live alignment follow-up

The selected saved revision can now enter [manual live alignment](model-live-alignment.md) from the review screen. The handoff preserves its exact guides and mesh settings. Physical alignment and live/viewer parity remain unverified.

## Displayed-revision face clearance

Generated-hair review now checks its currently displayed original, saved revision or unsaved preview against the package's recorded canonical face surface. The report is computed off the main thread and shown only when its haircut hash matches the displayed compiled mesh. Switching revisions cancels obsolete work and removes the old report; core clearance checks observe cancellation between guides. Face geometry is hash-bound in the constructed anatomy input, and all existing margin/material-radius checks remain active.

The panel distinguishes fixed-root conflicts (review scalp shape, hairline and attachment mapping), curve-only conflicts (revise the curves), and no conflicts against the supplied surface. It always explains that the face is incomplete/noisy, ears are unavailable and physical/style suitability is not established. Errors remain explicit instead of being presented as clearance. This is research review guidance; it does not automatically alter roots, delete guides, approve a design, or navigate to a potentially unrelated scalp document.

All 125 core tests and the iPhone SDK build pass. The simulator test passes: previewing a shorter fringe changes the checked haircut hash, switching to original changes it again, and leaving comparison restores the preview hash. The temporary preview is discarded at the end. The screenshot was inspected and shows readable status; the lower explanatory text extends below the captured viewport and remains scrollable. Saved model data is preserved; no phone build was replaced. Native fixed-root and curve-conflict branches still need separate UI fixtures; the tested retained model showed no conflicts with its supplied face.

## Conflicting attachment markers

When the displayed revision's clearance report contains root violations, the 3D scene now adds red 2 mm-radius diagnostic markers at those exact guide roots. A legend explains that markers are enlarged and visible through surfaces to aid location; they are not physical hair dimensions or normal occlusion rendering. Markers live in a separate scene node, so receiving a report does not rebuild the hair mesh. Their signature includes the haircut hash and sorted root IDs. An obsolete report cannot mark another displayed revision, and changing to a revision without matching conflicts clears them. No roots or source geometry are moved.

The iPhone SDK build passes. Positive-conflict marker rendering and interaction still require a dedicated simulator/physical fixture; the preceding simulator report-switching test used a no-conflict model. No updated build was installed on the phone during this work. The latest read-only phone listing still contains the nine earlier capture folders and no denser capture folder.

The conditioned-decoder artifact route subsequently supplied a real positive-conflict case. Its isolated simulator test loaded the 763-guide result, verified the six-attachment legend and “Review scalp attachments” status, displayed the red marker cluster on the inferred forehead/scalp boundary, and removed the isolated test review. The screenshot was inspected. This verifies positive-conflict rendering in the simulator; physical behavior and artifact acceptance remain unproven. See [conditioned artifact binding](model-guide-import.md#explicit-conditioned-decoder-artifacts).

## Explicit refined research revisions

A review package can now retain an optional `researchRevision` containing a separate revision-1 haircut, its canonical hash, the replayed original import hash and a declared method. Preparation still replays the original source import and scalp/face correspondence. It then checks the new artifact's hash, canonical geometry, guide identities/regions/material assignments and unchanged materials. Mismatched source links, invalid geometry, changed identities and empty method declarations are rejected. This linkage does not independently replay or authenticate the declared fitting algorithm.

The native repository and compiler consume the exact refined haircut, while the original import remains in the package for provenance. The scene shows an explicit research-fitting notice; clearance is recomputed against the displayed revision and the incomplete-face/missing-ear warning remains. No personal acceptance is inferred. Legacy packages without this field continue to display their replayed import.

Verification: all 139 core tests pass, including legacy-package replay and rejection of stale source links, modified candidate payloads, canonically invalid geometry, changed guide IDs and empty provenance descriptions. The unsigned iPhone build passes. The actual participant research package replays to canonical hash `09083db360d74d4fa82d56f6c602f667796ce75b39a877fe85654a7a95b99798`, with 763 guides and 214,613 compiled vertices. Phone installation is deliberately deferred while the user may be recording.

The isolated `testRefinedResearchRevisionShowsExactHashAndIncompleteEvidence` passes against the actual research package (2026-09-11 04:41 simulator result). It imports the refined candidate, verifies the exact displayed clearance hash, zero supplied-face conflict status, missing-ear warning and absence of red conflicting-root markers, captures the scene/clearance views, and deletes only the isolated test library through the app. Both screenshots were inspected. The first attempts exposed scene gestures intercepting scrolling; test scrolling now uses the page margin. The rendered face remains rough and incomplete, and guide rendering is explicitly enlarged for inspection. Private screenshots are retained under `outputs/refined-review-passed/`.

## Anatomy-aware native edits and exact alignment handoff

Native model editing now passes the recorded face to `HaircutEditor.apply`, using the same 1 mm clearance and observed-face hash as the review panel. Previously the editor checked canonical geometry/envelope but the face check only ran afterward in the display. A failed supplied-anatomy edit now returns an error before a preview can be saved; the prior selection remains intact. Missing ears still prevent a full physical-fit claim.

Actual-candidate replay checks under `outputs/refined-edit-verification/` establish:

- A 41 mm fringe cut changes 146 fringe guides, preserves all 617 other guides and every attachment, and passes supplied-face clearance.
- A separate 20% crown-volume increase changes 85 crown guides, preserves the other 678 and all attachments, and also passes supplied-face clearance.
- The native slider run selects 38 mm, saves revision 2, survives app relaunch, and hands that exact revision to manual live alignment without opening the camera. The native artifact was copied back and independently replayed from its declared parent/edit, yielding the identical full haircut and hash `273b4347eccc810fa4f68ec2e313d05e89778872105146ade5bc8218462272d2`.

`testRefinedEditPersistsAndHandsExactRevisionToAlignment` passes in the simulator (2026-09-11 04:43 result); its alignment screenshot was inspected. The unsigned iPhone build passes. This verifies a saved-edit/setup handoff, not calibrated live-camera placement, sustained rendering performance, or stylistic suitability. The installed phone capture build remains unchanged.

The negative native case also passes: the earlier participant candidate with six conflicting attachments rejects a fringe preview with a supplied-anatomy error, keeps its original saved hash/revision and exposes no Save button. `testConditionedReviewShowsConflictingAttachmentMarkers` verifies this before deleting its isolated test library. This closes the actual native failure path as well as the successful refined-edit path.

## Native design preparation

Model review now exposes “Check inputs for a new design” when the saved revision is selected. It snapshots that revision's guide bindings, the matching observed face and personal input. A saved guided/automatic brief is replayed from the preferences directory; if absent, a deterministic automatic brief is prepared without asking style questions. The current preparation radius supports guide materials up to 0.05 mm; larger materials are rejected locally rather than checked with an undersized radius.

The preparation screen requires explicit consent before sending personal face/scalp geometry, attachments and brief to the configured service. It uses the existing credential vault, idempotent session/job creation, upload protocol, cancellation and deletion. Personal state is stored separately from the synthetic processing lab and keyed by the full preparation request hash. Reopening replays cached results and checks the selected haircut/source identity. State writes/reads are bounded and protected; a changed brief or revision cannot silently reuse an earlier preparation.

The actual participant simulator flow passes (`Test-PersonalizedHair-2026.09.11_05-08-54-+0200.xcresult`): submission is disabled until consent, one real worker job completes, the zero-conflict result and both missing-ear warnings appear, relaunch restores it, and deletion removes local preparation state and service artifacts while keeping the same saved haircut hash. The screenshot under `outputs/native-personal-preparation/screens/` was inspected. The database records one attempt; after deletion its output hash is cleared, and no session JSON artifacts or local preparation state files remain. All 141 core tests and the final unsigned iPhone build pass. The temporary loopback service was stopped; no camera was activated and the installed phone capture build was unchanged.

This completes the native preparation path only. Neural generation is not started by this screen, and no prepared result is labeled a generated or physically accepted haircut. A consumer service configuration and full personal model-stage orchestration remain outstanding.


## Automatic preparation refresh

Active preparation jobs now refresh every two seconds while their screen is present and the app is active. No automatic submission occurs without an existing job. Completion, cancellation, failure, deletion or a changed job identity stops the loop; errors pause network retries until the user acts. The job identity and terminal state are checked again after each wait, preventing a delayed refresh from recreating deleted work. View-task cancellation does not become a displayed service error. The synthetic processing mode is unchanged.

The native test now performs no refresh taps. `tools/verify_native_preparation.py SERVICE_STATE NEW_REPORT_DIRECTORY` starts a temporary loopback service on port 8767 and holds its worker until a queued status response has been produced for the app. It requires the isolated refined revision-2 simulator fixture; repeat runs reuse the service database so guest credentials still match the simulator Keychain.

The gated run passes in 59.33 seconds, with one queued job, one worker publication, automatic result retrieval, verified cache after relaunch, and deletion. Evidence remains local in `outputs/native-personal-preparation-gated/`. The final unsigned iPhone build passes. Background/foreground gating is implemented but was not physically exercised by this simulator scenario. No neural model or phone camera ran, and the installed capture build was unchanged.

## Prepared pipeline output in native review

The actual output of `run_prepared_personal_generation.py` now passes native model-package replay using its own source bytes, mapping and exact prepared input, together with the retained face/scalp review. Both the importer and compiled mesh identify revision `ead3e0a23212a708f130b9f331b9ee2ad72a25f05f30bda6ad7158f193306846`: 763 guides, 230,426 vertices and 8,979 observed face vertices. This is the uncorrected pipeline candidate, not the separate subsequent rotation/attachment experiments.

An isolated simulator fixture uses `--prepared-pipeline-model-review-test`, `Documents/prepared-pipeline-model-review-test.json` and `Application Support/PreparedPipelineModelReviewTest`. It preserves the older conditioned/refined fixture stores. `testPreparedPipelineRevisionRetainsCurveReviewAfterRelaunch` imports the actual package, verifies the exact revision, relaunches, and checks that independently recomputed clearance still identifies 24 conflicting guide curves, missing ears and no root-conflict markers. The test passes in 30.385 seconds. Its retained screenshot was inspected; the curve-review message, missing-anatomy explanation and checked revision are readable.

The unsigned iPhone build passes; no new phone build was installed and no camera was activated. Package/replay evidence is in `outputs/personal-conditioning-pipeline/`, with the native screenshot under `outputs/prepared-pipeline-native-screens/`. This proves local artifact compatibility and native review persistence. It does not connect native submission to the model worker or establish physical fit, rendering performance or style quality.

## Native conditioning screen

A ready preparation now links to **Create a research candidate**. The new screen requires an explicit model-run toggle/start action, retrieves the exact verified preparation bytes, and creates a separate session for the conditioning job. It uploads the five bound artifacts, submits once with a persisted request key, automatically refreshes while visible/active, verifies the returned source/import/mesh/clearance, and renders the actual-radius guide mesh with the retained observed face. The currently selected haircut is not replaced.

State is scoped by preparation job and service origin under protected, backup-excluded `Application Support/PersonalConditioning`. Metadata and the original published response bytes are separate files, each bounded at 100 MB. Relaunch replays verification against the retained inputs and original output hash. A damaged result cache retains verified metadata and offers explicit retrieval or deletion; malformed metadata is not silently overwritten. Cache-corruption recovery is implemented but has not yet been exercised as a native failure scenario. Cancellation intent persists before the network request, and deletion removes this candidate's service session and local directory. The separate preparation session has its own deletion control.

Native preparation now resolves a previously conditioned artifact back to its declared original model sample. It preserves the selected revision's attachment bindings and all mapping geometry/bounds. This fixes an actual native run that requested the conditioned artifact hash, for which no original latent texture was provisioned. `ModelReviewPackage.regenerationSampleSHA256()` resolves this reference after ordinary package verification; it is not proof of model computation. A regression test covers original versus conditioned sources and changed source bytes. All 145 core tests and the unsigned iPhone build pass.

The actual candidate rendered and survived native relaunch with the same revision, 24 conflicting guide curves and two missing anatomy regions; the selected source stayed at revision 2. The restored screen was inspected in `outputs/native-conditioning-v4-screens/`. The candidate's native deletion also completed in that run; its combined test subsequently failed by tapping the separate preparation deletion control while that screen was restoring. Preparation controls now use an explicit readiness wait in this scenario. The design-preparation action also has a full-width 44-point tap target. The final complete-scenario rerun is recorded separately below when finished.

This remains a research candidate from an existing model sample. Fresh preference-driven sampling, finished strand density/style quality, promotion into a new editable design history, physical fit and camera performance remain outstanding. The installed phone capture build is unchanged.

The complete native scenario now passes. `tools/verify_native_conditioning.py SERVICE_STATE REPORT_DIRECTORY` runs the isolated refined revision-2 fixture with a temporary enabled loopback worker on port 8767. The passing run takes 175.50 seconds overall (162.58 seconds in the UI test), with exactly one preparation publication and one conditioning publication. It checks explicit model consent, automatic retrieval without refresh taps, identical candidate revision after relaunch, retained 24-curve/two-region warnings, unchanged selected source, and native deletion of both sessions. The helper independently confirms both session artifact directories contain no JSON after deletion and shuts the API down.

Readback additionally confirms removal of the candidate directory and preparation cache, while the source selection remains exactly `273b4347eccc810fa4f68ec2e313d05e89778872105146ade5bc8218462272d2`. The final restored screenshot was inspected: model geometry, revision `68c2512719`, limitations and controls are readable. Evidence is in `outputs/native-personal-conditioning-v5/` and `outputs/native-conditioning-v5-screens/`. Earlier failed-test caches were preserved under ignored diagnostic outputs before their test service sessions were removed; no source capture or selected haircut was deleted.


## Verified candidate handoff

`capture-inspect conditioning-review-package RESULT.json OUTPUT_SHA256 CONTEXT.json SCALP_REVIEW.json PACKAGE.json` verifies the original published response against its retained preparation context before packaging a generated candidate with the scalp review. It refuses existing output paths and bounds input files. The core package factory replays the import and scalp correspondence, requires the exact candidate revision and retains its original model-sample reference. Callers of that factory must first verify the processing result. Packaging does not establish physical or style acceptance.

The retained native model response replays through this command and independently through `model-review-check`: 763 guides, 8,979 observed face vertices, and the unchanged candidate hash `9683708ff2f1de8b78c7770d0a68d6c3ca779cec3d239f2f8c364c3282f73a0c`. Evidence is in ignored `outputs/conditioning-editing-handoff/`. The synthetic regression checks exact revision/source preservation and rejects changed candidate geometry, mismatched scalp evidence and a style-acceptance claim; all 146 core tests pass. This is an artifact handoff foundation. A separate native editing workspace and discoverable candidate history still need implementation, and curve-clearance failures must not be hidden to enable edits.


## Separate candidate studios

The conditioning screen now offers **Save and open separate studio** when the retained scalp review is available. The verified candidate is replayed before its package and initial selection are stored under `Application Support/CandidateStudios/<full-original-haircut-hash>`. Existing studios reopen their own selection rather than resetting edits. Both import and restore check the original revision against the directory identity; the source studio is not a target of these writes. Files use the existing protected, backup-excluded model studio storage.

**Saved candidates** in Capture lab provides independent access after processing data is deleted. Each studio offers the existing geometry-checked edit, undo/redo and deletion controls. The processing deletion message distinguishes saved studios from processing caches. The captured face/scalp review is propagated through preparation to packaging. Curve conflicts remain blocking for edits that fail the existing clearance gate; no acceptance threshold was weakened. The core suite (146 tests) and unsigned iPhone build pass. Native lifecycle verification is in progress; successful editing of this new conflicting candidate is not established.


The real native run in `outputs/native-candidate-studio-v1/` published both jobs, saved/opened the separate candidate studio, restored the original source at revision 2, and deleted both processing sessions. Its final library check failed because the test omitted entering Capture lab after relaunch; the navigation is corrected. A separate native test, `testSavedCandidateStudioSurvivesProcessingDeletion`, then passed in 40.06 seconds using that retained studio with no service running. It opens the exact candidate from the library, deletes the studio and reopens the unchanged source. Independent filesystem snapshots confirm the separate candidate existed after processing cleanup and was removed afterward, with source hash `273b4347eccc810fa4f68ec2e313d05e89778872105146ade5bc8218462272d2` unchanged. The full corrected combined scenario has not been rerun.

The retained screenshot in `outputs/candidate-studio-library-screens/` was inspected: the sparse 763-guide candidate, incomplete observed face and amber inferred scalp are displayed with readable revision/diagnostic text. This demonstrates independent candidate storage, opening and deletion, not successful edits of the new conflicting candidate or a finished personalized hairstyle.


The corrected combined scenario now passes in 205.62 seconds (`outputs/native-candidate-studio-v2/report.json`): both real worker publications, separate studio creation, source revision preservation, candidate restoration, processing-session deletion, independent library reopening and studio deletion all complete in one test. Independent post-test file inspection confirms no candidate selection or conditioning cache remains and the source hash is unchanged (`local-verification.json`). The temporary API/worker shut down after verification. No phone installation or camera session occurred.


## Direction editing

The studio now previews a fringe direction adjustment from −45° to +45° in one-degree steps. `rotate_around_root_normal` uses a right-handed rigid rotation about each guide's attachment normal; roots and guide lengths stay fixed and other regions are unchanged. Each preview runs the existing canonical envelope/length checks and, when supplied, face-clearance checks before save. This is an explicit styling adjustment, not a measurement of follicle growth direction. The edit is retained in revision provenance and independently replayed by the repository.

Core tests check the known +Y-axis fixture rotation, every pairwise point distance, unchanged root bindings/other region, base immutability, transition replay, invalid/no-op values and supplied-face rejection. All 147 core tests pass. The native synthetic scenario verifies preview → save → relaunch → undo → redo with unchanged reported lengths, then deletes its fixture. Final one-degree-control verification is recorded below when finished.

A retained model-derived revision-2 haircut was also tested offline against supplied face anatomy. −5° fails face clearance (four segments); +5° and +1° fail the unchanged inferred-envelope correction bound. −1° passes and saves as revision 3, hash `4922225ac4e4a8b8a9333235892ea873a270f55618b7cd03c657cd3e3eb07909`. Independent inspection finds 146 changed fringe guides, fixed roots, and maximum per-segment length difference 2.70e−17 m; both ears remain missing. An initial CLI attempt passed geometry but could not save because its new repository lacked the revision-1 parent; replay succeeds after copying the complete retained parent chain into the isolated test repository. Evidence is under `outputs/direction-edit-probe/`. No selected phone/simulator model revision was replaced, and the new 24-conflict generated candidate has not been repaired by this work.


The final one-degree-control native scenario passes in 31.46 seconds, and the unsigned iPhone build passes. The retained screenshot (`outputs/direction-edit-ui-screens/`) was inspected: direction, length and history controls are readable. After relaunch the adjustment control resets to zero relative to the saved revision; its wording now explicitly states that relationship. The screenshot shows the controls and history state, not a physical-person rendering comparison.


Direction edits now have an exhaustive design-details explanation instead of being mislabeled by the old two-operation volume fallback. The signed angle, region, and preserved roots/lengths are shown after relaunch and undo/redo. The final native scenario passes in 40.22 seconds; its screenshot in `outputs/direction-details-screens/` was inspected and shows the +35.0° edit with unchanged 133.7 mm guide lengths. The first assertion used a child accessibility identifier inherited from the disclosure group; the corrected test queries the displayed explanation text. The iPhone SDK build passes.

A new synthetic live-package regression serializes the direction-edited revision, compiles it with the model-review settings, and compares the entire mesh to the interactive compiler output. Both retain the exact edited hash and operation. All 148 core tests pass. This verifies package/mesh parity; physical camera alignment, frame timing and real-person live rendering remain unproven.


## Conflicting curve segment overlay

The studio now highlights exact conflicting guide segments in purple. `GuideConflictOverlay.segments` binds selections to the haircut hash, rejects stale reports and unavailable segment references, and deduplicates repeated segment findings. The overlay is a separate batched SceneKit geometry, enlarged to 0.8 mm radius and visible through surfaces for diagnosis. At most 4,096 segments are drawn, with an explicit displayed/total count. The source haircut mesh is unchanged; red attachment markers remain separate.

The fresh short research package is retained in an isolated simulator fixture (`--fresh-short-review-test`, `FreshShortModelReviewTest`). Native verification loads revision `eb21601869`, waits for all 68 conflicting segments, relaunches and checks the same revision/overlay. The screenshot under `outputs/segment-overlay-screens/` was inspected: purple marks appear near the temple/hairline, and the fringe range and diagnostic legend are readable. The final native test also checks the original-comparison toggle. In this studio, original means its initial fitted candidate, so both views retain 68 conflicts at revision 1; the earlier test incorrectly expected the underlying raw import's 134 conflicts and was corrected. It does not prove switching between different clearance reports.

All 149 core tests pass, including exact overlay endpoints, deduplication, stale-hash and invalid-reference rejection. The direction-edit anatomy test was also corrected to use a valid-sized surface and explicitly demonstrate real intersections before expecting rejection. The unsigned iPhone build passes. No phone installation or camera session occurred. Six guides remain in conflict and the incomplete face/scalp geometry remains unaccepted for physical styling.
