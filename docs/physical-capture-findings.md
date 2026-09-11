# First front-camera capture findings

2026-09-10, iPhone 15 Pro, iOS 27. The participant recorded one completed front-face pass with 87 RGB/depth frames. Both streams are 640×480. Bundle payload integrity passed. Raw participant images, depth, landmark reports and mesh outputs remain under ignored `outputs/`.

One startup frame has 66.7 ms timestamp skew; the remaining frames agree at the recorded precision. Geometry sampling and surface building now require at most 10 ms skew from the actual source timestamps. The raw pass remains intact. This threshold is provisional; zero recorded skew is not a measured synchronization-accuracy guarantee.

Vision detection succeeded at eight sampled positions after fixing handling of a single out-of-image landmark in frame 55. Such a point is omitted with an explicit note; valid points in the frame remain available. Usable depth does not guarantee a point belongs to the face: frame 55 included background depth near an eye. These samples need anatomical/visibility checks before correspondence generation.

Seven widely spaced views were tested against reference frame 30 with fixed eye/nose landmark-index correspondences, even indices for fit and odd indices for held-out validation. A duplicate nose/nose-crest landmark was identified and the redundant nose-crest region removed from the experiment. Every resulting trial failed the existing rigid-fit acceptance path. No thresholds were relaxed and no multi-view surface was fused. Failure can reflect correspondence/pose sensitivity, depth noise or calibration issues; this experiment does not identify a single cause.

A single-view patch from frame 20 contains 10,108 vertices and 19,480 triangles. Its provisional mask uses a Vision landmark convex hull and an 80 mm depth band around the median available landmark depth. This is not validated skin segmentation. The render shows recognizable central/lower facial structure, but is noisy, has holes and lacks complete forehead/head coverage. It is not suitable for personal haircut fitting yet.

Reproduction after building the CLI:

```sh
python3 tools/reconstruct_face_patch.py CAPTURE_BUNDLE LANDMARK_REPORT.json NEW_OUTPUT_DIRECTORY
```

The tool retains the mask request and delegates metric projection, timing checks, payload verification and triangulation to the existing surface builder. It now maps native-image landmark coordinates into aligned depth dimensions, including the rear sensor's lower resolution. It does not fuse views, infer hidden scalp or publish a complete head.

Next experiments: inspect nearby-frame correspondences; reject background/occluded landmark depths using local surface evidence; compare observed nose/eye-region geometry; validate metric projection on a measured rigid fixture; then attempt dense registration. Rear coverage remains necessary for the intended complete head workflow.

## Nearby-view replay and fusion follow-up

Seven additional nearby pairs were tested with the same fixed eye/nose correspondence policy and unchanged thresholds. Six pass using nearest-pixel depth: frames 18, 19, 21 and 22 against 20; frames 29 and 31 against 30. Frame 32 against 30 fails held-out validation (median 5.37 mm, maximum/nearest-rank p95 20.23 mm). These are residuals between model-generated landmarks, not measured anatomical accuracy.

A diagnostic 5×5 median experiment, with and without a local depth-spread gate, produced mixed residual changes and did not rescue the failed pair. Some samples were excluded, so aggregate residuals are not directly comparable on identical point sets. Production sampling remains unchanged.

The four accepted pairs around frame 20 were replayed through the captured-depth adapter, which verifies original payloads and recomputes all selected 3D points. The failed 32→30 pair was also replayed and remained rejected. The repeatable tool is:

```sh
python3 tools/register_face_views.py CAPTURE_BUNDLE REFERENCE_REPORT.json NEW_OUTPUT_DIRECTORY SOURCE_REPORT.json [SOURCE_REPORT.json ...]
```

Every pair retains its pixel selection, registration report when available, and acceptance status. Reports are candidate model correspondences; their anatomical identities have not been manually validated. This tool does not automatically fuse accepted pairs.

An experimental five-frame surface used reference 20 and sources 18, 19, 21 and 22, with each source's provisional convex-hull/depth-band mask. The existing surface builder independently rechecked registration. Output: 27,161 vertices and 86,217 triangles; 13,445 vertices have observations from multiple frames. Raw data and derived surfaces remain in ignored outputs.

Visual inspection shows recognizable but rough, incomplete facial structure. A topology count finds 20,408 edges incident to more than two triangles (versus zero for the single-frame patch), plus 5,765 boundary edges. The radius-based vertex fusion retains overlapping per-view triangle sheets; passing landmark registration does not make this a consistent mesh. Do not use this result for haircut fitting or scalp completion. The next reconstruction change needs a unified surface extraction strategy and explicit topology checks, followed by independent dense-overlap validation. Merely smoothing vertices or dropping excess triangles would not establish accuracy.


## Additional front passes received 2026-09-11

Two additional completed front captures were copied from the phone and passed full capture-bundle integrity checks, with 128 and 115 synchronized image/depth frame pairs. No app recording settings changed. The first contact sheet and second frontal segmentation diagnostic were inspected: facial framing is usable for another registration experiment, with tied-back hair and additional large turns/up/down poses that must not be fused without validated registration.

The requested distance was approximately 40 cm; sensor-reported median face depth in frame 8 is approximately 28 cm and 30 cm, respectively. These are not controlled 40 cm measurements. Independent mask/vertex replay passes for both sampled frames. This establishes usable local evidence, not reconstruction accuracy or repeatability.

[Sanitized intake evidence](evidence/repeat-front-intake-2026-09-11.json) records counts, input hashes, sampled-depth statistics and remaining checks. Raw bundles and diagnostics remain in ignored local outputs. Both copies were confirmed before telling the user the phone could be disconnected.


## Repeat-pass registration experiment

Frames 6, 8 and 10 from each new pass were selected as a fixed initial-frontal sample. All nine cross-pass combinations and all three within-pass combinations per pass were evaluated with the existing eye/nose even-index fitting and odd-index held-out policy. No acceptance thresholds changed.

- Cross-pass: 5/9 pass the registration gate (4 mm held-out median, 10 mm nearest-rank p95). Only 2/9 meet the implementation plan's stricter proposed repeatability target (3 mm median, 8 mm p95). The repeatability gate remains unproven.
- First pass: 1/3 within-pass pairs pass; the other two exceed the held-out p95 limit.
- Second pass: 3/3 within-pass pairs pass. Dense bidirectional nearest-sample p95 spans approximately 2.69–3.58 mm on these accepted pairs.
- Accepted cross-pass pairs have dense bidirectional p95 approximately 3.09–7.20 mm. Every accepted pair was measured; failed transforms were not used for fusion.

A new NumPy verifier reconstructs selected rays from original depth payloads and inverse lens tables, checks proper rigid rotation, and replays every fitting/held-out residual plus the held-out gate decision. All 15 reports pass this arithmetic replay. It does not independently establish anatomical landmark correspondence, calibrate physical dimensions or refit poses. All six single-view semantic-mask surfaces also pass the existing independent mask/vertex replay.

These findings support trying a local fusion of the second pass next. They do not justify combining the two captures into an accepted head, replacing the app's review model, or claiming repeatability from a selected successful pair. The small frame grid is correlated, not a population sample.

[Sanitized registration evidence](evidence/repeat-front-registration-2026-09-11.json) records all pairs, including failure residuals, and aggregate dense reports. Full participant-derived reports remain under ignored `outputs/repeat-front-landmark-grid/`. `tools/register_face_views.py` now accepts an optional `--source-bundle` for cross-pass replay; its default same-pass behavior is unchanged.


## Wider-pose survey of the second repeat pass

Nineteen frames were sampled: thirteen every eight frames through the later capture, then six every two frames during the two turn transitions identified in the contact sheet. Seventeen yielded face landmarks; the two upward-looking frames did not. Every detected frame was registered directly to reference frame 8 under unchanged thresholds.

Six of seventeen attempted registrations pass. Their estimated total relative rotations are only about 1.1–4.5 degrees, so they provide additional frontal observations rather than meaningful profile coverage. Two transition fits estimating approximately 19 and 26 degrees fail held-out validation; larger profiles cannot produce a consistent rigid fit. These angles are outputs of fitted transforms, not independently measured physical head turns.

All eleven generated registration reports (accepted and rejected) pass independent raw-depth replay of 220 residuals. Six other attempts fail before producing a transform. Three additional accepted frontal-frame masks pass independent depth/vertex checks and remain available for later analysis. No new fusion was performed because this survey did not establish safe off-axis coverage.

The next pose investigation should replace or supplement direct eye/nose model-landmark correspondences with visibility-aware correspondence or dense head-relative registration, retaining held-out checks and rejecting accumulated drift. More near-frontal frames, denoising or relaxed thresholds do not establish the missing side coverage.

[Sanitized survey evidence](evidence/front-turn-survey-2026-09-11.json) preserves both sampling stages, all failures and successful arithmetic replay. Private images and reports remain under `outputs/repeat-turn-survey/`. The survey wrapper now accepts an explicit `--cli` path and records subprocess exit code and runtime, allowing a freshly built release executable to avoid debug-only overhead. One accepted report exactly matches debug output; a failed-fit trial also retains its failure outcome.
