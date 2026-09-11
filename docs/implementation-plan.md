# Implementation and validation plan

Version: 0.1 · Date: 2026-09-10 · Status: implementation in progress; gates unproven

Read with the [product and technical specification](product-technical-spec.md) and [implementation status](implementation-status.md). Every threshold below is a proposed engineering acceptance target. Software tests and synthetic replays are recorded separately from physical capture quality, model performance, cost, and device runtime, which remain unmeasured.

## 1. Delivery strategy

Build the smallest complete path that proves individual design: capture one person, generate one haircut conditioned on their evidence, make one meaningful edit, and display the exact revision in both viewers. Expand candidate diversity and input coverage only after this path works.

The product and data contracts are stable enough to begin implementation. Sensor quality, registration, model selection, mobile rendering and physical feasibility remain experiments. Reduce the tested hair domain if necessary, but retain custom geometry and document coverage honestly.

No calendar delivery promise is assigned before M0–M2. Those milestones determine hardware availability, research reproducibility, GPU requirements and the amount of custom development. The milestone sequence expresses dependencies rather than equal-sized work packages.

## 2. Milestones and exit gates

| Milestone | Deliverable | Exit gate | Depends on |
|---|---|---|---|
| M0: establish feasibility tools | Device capture harness, research inventory, recorded test fixtures, environment manifest | Both sensor paths recorded and replayable; at least one usable strand-generation route evaluated; device/backend choices justified | None |
| M1: personal head | Guided capture, registered visible geometry, inferred scalp completion, quality review | Repeatability and registration targets met on pilot captures; artifacts distinguish measured and inferred regions | M0 |
| M2: custom haircut | Personal profile, structured brief, constrained guides, one candidate and one edit | Demonstrable person-dependent design, valid attachment and bounds, edit changes the requested region | M1; generation experiments can start in M0 |
| M3: consistent previews | Interactive viewer, mobile asset compiler, live alignment and occlusion | Same haircut revision in both modes; acceptable framing, stability and sustained performance | M2 |
| M4: autonomous and guided experience | Up to three valid proposals, preference flow, explanations, edit history | Autonomous flow needs no mandatory style answers; guided changes respected; uncertainty preserved | M2–M3 |
| M5: consumer preview | Recovery, deletion, exports, accessibility pass, broader participant evaluation | End-to-end acceptance suite and documented support matrix pass | M1–M4 |

### M0 — Device and research feasibility

Tasks:

1. Inventory available physical iPhones, Xcode/SDK versions and provisioning needs. Select a lower-performance target and a newer comparison device with both required depth paths.
2. Build a small native capture harness that exports synchronized front RGB/depth, rear RGB/depth/poses, calibration, active formats, timestamps and quality metadata.
3. Capture an asymmetric rigid fixture of known dimensions and a consenting participant. Verify units, mirroring, depth validity and transform conventions.
4. Implement offline replay and inspection of capture bundles. Use physical hardware for camera validation; use fixture replay for reproducible processing tests.
5. Inventory candidate generation/reconstruction code, weights, terms, dependencies, GPU memory and example outputs. Reproduce an official example before integrating a method.
6. Evaluate direct strand generation and an image-to-strand route on the same simple head. Include a procedural person-conditioned guide generator as a baseline for validating the asset/constraint contracts, not as evidence of complete autonomous styling quality.
7. Compare mobile rendering of a small strand/card fixture against an optional Gaussian fixture. Establish which representations actually run within the phone budget.

Evidence: device capability report; two replayable sensor bundles; calibration report; research reproduction report with outputs, runtimes and licenses; proposed runtime, renderer, and minimum OS decisions.

Gate: sensor streams and calibration are sufficient for a registration experiment, and at least one generation route can emit editable strands with usable terms. If no route succeeds, explicitly keep generation as an unresolved research dependency; do not quietly change the product to stock hairstyle overlays.

### M1 — Personal head reconstruction

Tasks:

1. Build preparation, front capture, assisted rear capture, natural-hair capture and quality-review screens.
2. Implement masks and filtering for hair, clips, background, low-quality depth and subject motion.
3. Fit per-frame head pose, fuse usable observations, and register front/rear passes using visible skin overlap.
4. Fit scalp/head completion behind occlusion and retain inferred-region masks. Do not use a tied bun as skull geometry.
5. Derive a minimal hair profile: visible hairline, texture descriptors, part/flow and regional uncertainty. Build the current-hair appearance baseline from reviewed untied-hair views, including supported silhouette/envelope and appearance estimates, following [scan-derived hair appearance](scan-derived-hair.md). Record unsupported properties as unknown.
6. Reconstruct repeated captures and produce regional error reports, overlay renders and targeted rescan instructions.

Evidence: registered head asset and provenance report for each pilot; paired repeat scans; failure examples for motion and insufficient overlap.

Gate: frontal identity and profile are recognizable, repeatability targets pass, alignment errors are bounded, and missing data results in recapture or explicit inference. Failure of a rear sensor to add useful information should prompt a documented capture-design revision based on evidence.

### M2 — Personalized generation and edits

Tasks:

1. Implement versioned profile, brief, guide/strand, haircut and validation contracts.
2. Compile autonomous defaults and optional guided preferences into a structured design brief.
3. Generate a candidate conditioned on personal geometry and hair observations, then fit and constrain it.
4. Validate attachment, length bounds, region continuity, geometry, and feasibility conditions.
5. Implement a fringe-length edit with exact revision history and a second edit for regional volume or part placement.
6. Run controlled personalization experiments and compare person-conditioned output with the same pipeline deprived of personal parameters.
7. Produce standardized front/profile/rear views and explanation data derived from accepted design parameters.

Evidence: one real participant's custom haircut, meaningful edit, canonical assets, parameter diffs, constraint reports, and personalization comparisons.

Gate: valid geometry and a demonstrated change in design beyond global head fitting. Image-only results do not satisfy this milestone. An unvalidated synthetic length/density assumption cannot earn the strongest feasibility label.

### M3 — 3D and live preview

Tasks:

1. Build interactive orbit/zoom/reset/compare controls with evidence overlay and identity-preserving head rendering.
2. Compile canonical hair into a tested mobile representation with material, bounds, units and revision hashes.
3. Calibrate the canonical head to the live face tracker. Ensure expressions do not stretch the haircut.
4. Add temporal stabilization, face/ear occlusion, segmentation integration and safe tracking-loss behavior.
5. Test pinned-back hair, residual ponytails/buns, moderate turns, illumination changes and moving hands. Document the supported framing and turn range.
6. Measure sustained performance, thermal behavior, memory use and alignment error on target phones.

Evidence: recordings of viewer/live parity, scripted turn/occlusion cases, performance traces, and an explicit list of unsupported live situations.

Gate: both previews show the same revision and stay within quality/performance targets. Photorealistic loose-hair removal is not required for this gate; residual hair must not be concealed in evaluation reports.

### M4 — Autonomous and guided product behavior

Tasks:

1. Generate and rank up to three meaningfully distinct eligible designs within retry limits.
2. Add optional preferences, references, natural-language edits and undo.
3. Ensure explanations cite actual profile observations/defaults and avoid unsupported measurements or preferences.
4. Test unknown-property behavior, conflicting preferences, unavailable current lengths and candidate failures.
5. Add durable job execution, resumable transfers, progress stages and stale-result protection.

Gate: users can finish autonomous generation without a hairstyle questionnaire; corrections improve or constrain later designs; guided requests reach both previews; failures preserve prior valid work.

### M5 — Consumer preview readiness

Tasks:

1. Complete ownership, consent, retention, deletion and export behavior.
2. Verify interrupted capture, uploads, duplicate requests, failed workers, out-of-order edits, app relaunch and offline saved viewing.
3. Run accessibility checks and instrument capture completion and failure causes.
4. Evaluate the broadened cohort and publish a supported-device/hair-domain matrix with evidence.
5. Package an installable internal build and an evaluation script. External distribution and provider provisioning are separate execution actions, not outcomes claimed by this specification.

Gate: acceptance cases pass and unresolved limitations appear in product behavior, documentation and demonstration framing.

## 3. Acceptance targets

All numerical values are initial targets to be revised with recorded justification after M0/M1. Report numerator/denominator and raw samples; a small pilot cannot establish population-level performance.

| Area | Proposed target | Measurement |
|---|---|---|
| Rigid scale sanity | Median dimension error ≤2% on a measured fixture at intended capture distances | Compare several known dimensions; report each sensor separately |
| Face repeatability | Median corresponding landmark discrepancy ≤3 mm; 95th percentile ≤8 mm after rigid alignment of repeat captures | Stable landmarks, neutral expression, no nonrigid fitting to hide error; this measures repeatability, not absolute accuracy |
| Front/rear registration | Median held-out skin overlap discrepancy ≤4 mm; 95th percentile ≤10 mm | Use withheld surface samples; report overlap and regional failures; shared fitting bias remains a limitation |
| Geometry coverage | All required facial/profile/ear regions either observed at passing quality or explicitly identified as missing/inferred | Coverage audit with operator inspection; scalp under hair is not required to be observed |
| Capture completion | At least 10 of 12 pilot participants finish after at most one targeted retry | Full guided workflow, report each retry and failure reason |
| Personalization | All eligible controlled test pairs show relevant regional parameter/shape changes beyond a global transform | Fixed seed and intent; vary geometry or supported hair constraints; use ablation and expert review |
| Hair attachments | Every guide has a valid scalp binding; no invalid indices or nonfinite values | Automated validation; allow only declared offsets |
| Physical constraints | No known hard current-length violation without the corresponding feasibility label; no visible hair penetration through face/ears in review poses | Solver checks plus standardized rendered review |
| Design identity | Every preview/export references exactly the requested haircut revision and source hash | Manifest checks plus screenshots from aligned cameras |
| Live frame rate | ≥30 FPS for a 5-minute supported-use session on the lowest supported phone | Median and 95th percentile frame time, dropped frames and thermal state; target p95 frame time ≤40 ms |
| Live alignment | Stationary anchor jitter <1% of frame width RMS; drift <2% during documented moderate turns | Recorded anchor landmarks; distinguish tracking error from intended animation |
| Tracking loss | Overlay fades within 0.5 seconds of confirmed loss and does not float over another face | Scripted occlusion/exit/reentry test; no automatic subject switching |
| Cached local edit | Visible provisional response in ≤150 ms for supported bounded sliders | Input-to-first-updated-frame measurement on minimum device |
| Processing latency | One design p50 ≤5 minutes and p95 ≤12 minutes after upload, on declared GPU with no queue wait | Measure reconstruction and design separately; report queue/upload time too; small samples report max instead of misleading p95 |
| Resumability | Relaunch or network interruption resumes without a second billable generation | Job/usage IDs and stored checkpoints |
| Ownership and deletion | Unauthorized access rejected; deleted-session output cannot be served or republished | Integration tests with two identities and running jobs |

Performance targets apply to the explicitly tested asset sizes, hair domain and camera framing. Do not interpret them as guarantees for arbitrary generated geometry or every iPhone.

## 4. Evaluation set and method

### 4.1 Pilot fixtures and participants

Begin with one asymmetric rigid fixture and three consenting adult participants for iteration. Expand to a minimum of 12 adults, aiming for at least three examples each of straight, wavy, curly and tightly curled/coily natural hair. Capture variation in skin tones, lengths, visible hairlines and crown patterns; document gaps rather than claim representativeness.

Capture two geometry sessions per participant, plus natural-hair views. Repeat a representative subset on both selected device tiers. Tie/pin arrangements should include realistic obstructions. Preserve consent/retention choices independently of development convenience.

Evaluate challenging cases separately: short/fine hair, low apparent coverage, dark hair under low light, light/gray hair, heavy styling, bangs, dense curls, facial hair, glasses, head movement and limited head rotation. Braids, locs, elaborate protective styles, extensions and wigs require a declared supported/unsupported policy; they are not silently converted into an assumed loose-hair structure.

### 4.2 Personalization experiment

For each eligible pair, hold model/version, random seed and high-level design intent constant. Generate on both profiles. Measure regional changes normalized for overall head size, correspondence to known constraints, and preservation of identity/hairline.

Run three conditions: complete personal profile, geometry-only profile, and a generic profile baseline. The full system should show useful, explainable design differences and fewer constraint violations. Ask at least two hair professionals to review anonymized comparisons for plausibility and person-specific fit. Report disagreement; do not use one subjective score as objective proof.

Also test synthetic controlled changes within plausible bounds, such as a different forehead proportion or a supported crown direction, to isolate cause and effect. Synthetic results support engineering checks but do not replace human evaluation.

### 4.3 Appearance versus real-world feasibility

Evaluate visual fidelity, perceived personal fit, and practical plausibility separately. A participant may prefer a less physically supported concept; the UI must retain the correct label.

Review the cut specification and its styling assumptions with professionals. The preview does not require participants to cut their hair. A future voluntary before/after study is needed before claiming accurate prediction of a real cut's final appearance.

### 4.4 Research comparison

Compare candidate pipelines using the same inputs and output requirements: valid scalp-bound guides, controllable regional edits, cross-view consistency, visual quality, reproducibility, runtime, peak memory, per-job cost and usable licenses.

Capture both best results and failure rate. Exclude cherry-picked demo-only outputs from acceptance counts. A paper reporting fast reconstruction is not evidence that our person-conditioned generation has the same speed or fidelity.

## 5. End-to-end acceptance cases

| ID | Scenario | Required outcome |
|---|---|---|
| A01 | Eligible user completes autonomous flow | Generated personal haircut without mandatory style preferences; defaults visible/editable |
| A02 | User chooses guided length/maintenance limits | Candidate parameters respect constraints or explain conflict |
| A03 | Front and rear captures disagree | Registration rejected or affected region recaptured; no merged distorted head |
| A04 | Hair hides scalp/crown | Completion marked inferred; bun/clip not absorbed into skull |
| A05 | Current hair length unknown | Feasibility remains uncertain where relevant |
| A06 | User requests shorter fringe | New revision changes fringe as intended; previous revision preserved |
| A07 | Older edit finishes after a newer one | Newer selection is retained; old output available only under its own revision |
| A08 | Switch between 3D and live | Same haircut ID/revision, dimensions and part side |
| A09 | Head turns or facial expression changes | Stable root transform; expression does not distort haircut |
| A10 | Subject exits or a second face enters | Overlay fades/pauses; no transfer to another face without a fresh session choice |
| A11 | Long pinned-back hair remains visible | Supported limitations explained; no false claim that it was removed |
| A12 | App loses network during upload | Upload resumes with integrity checks and no duplicate evidence/job |
| A13 | Worker or external model fails | Bounded retry, durable failure, previous results accessible |
| A14 | Session deleted during generation | Access revoked; late output discarded/deleted; no resurrection |
| A15 | Another identity requests asset/job | Request rejected without leaking subject data |
| A16 | Unsupported device | Clear eligibility result and no unusable scan flow |
| A17 | Image concept changes face/hairline | Rejected or regenerated; never treated as the measured personal head |
| A18 | Only one candidate passes checks | Show one with honest status; no duplicates or invalid filler |
| A19 | User views saved haircut offline | Downloaded 3D result works; new generation shows connectivity requirement |
| A20 | Raw evidence expired before reanalysis | Request recapture only where necessary; retain usable saved results |

## 6. Failure codes and recovery

Use stable machine codes with short user-facing explanations. Include `unsupported_device`, `camera_permission_denied`, `capture_interrupted`, `insufficient_coverage`, `subject_motion`, `depth_unreliable`, `registration_failed`, `unsupported_hair_domain`, `input_incomplete`, `generation_failed`, `constraint_violation`, `budget_exhausted`, `asset_incompatible`, `tracking_lost`, and `session_deleted`.

Each failure reports retryability, affected pass/stage, preserved artifacts and next action. A failed model call does not instruct the user to repeat a valid physical scan. A geometry failure does not automatically retry expensive generation.

## 7. Decision register

| Decision | Working default | Resolve through |
|---|---|---|
| Minimum OS and phones | Require front TrueDepth and rear LiDAR; explicit runtime checks | M0 physical device inventory and capture probes |
| Front depth advantage | Candidate for improved facial geometry; no promised precision ratio | M0/M1 same-distance fixture and face comparisons |
| Reconstruction method | Robust RGB/depth fusion with head-relative registration and fitted completion | M1 comparison with available photogrammetry baseline |
| Hair generator | Strand-based output; direct generation and image-to-strand both candidates | M0 reproduction, licensing and M2 constraints |
| Image generation | Optional concept/conditioning stage | Keep only if it improves custom results without identity drift |
| Gaussian splatting | Optional reconstruction/rendering component | M0/M3 quality versus mobile budget comparison |
| Mobile representation | Hair cards/strands as initial candidate | M3 sustained tests and silhouette/part fidelity |
| Backend provider and GPU | Provider-neutral jobs/storage and model adapters | Reproduced model requirements, availability, privacy and measured cost |
| Initial hair domain | Narrow published pilot domain, expanded after evidence | M2 feasibility and M5 cohort coverage |
| Candidate count | Up to three; fewer when validation/budget requires | M4 diversity and cost evaluation |
| Retention | 24-hour raw expiry after success; 7-day abandoned upload expiry | Infrastructure implementation and user-facing policy review |
| Live loose-hair removal | Deferred beyond pinned-back preview | Separate temporal reconstruction experiment |

These unresolved implementation choices do not block initial capture/model experiments. Record decisions and evidence as they are made; do not quietly convert a proposed target into a measured result.

## 8. First implementation backlog

1. Set up the native app target, capability report and session manifests.
2. Implement/export front TrueDepth capture and rear RGB/depth/pose capture in separate sessions.
3. Build a fixture inspector with calibration overlays, frame quality and unit/coordinate checks.
4. Capture repeat fixture/face sessions with explicit consent and local storage.
5. Reproduce one strand-generation candidate and validate its exported geometry.
6. Establish the canonical profile/haircut manifest and a minimal 3D viewer.
7. Demonstrate registration of front and rear evidence before polishing capture UI.
8. Generate a personal candidate, constrain it, and implement one regional edit.
9. Compile the resulting asset and demonstrate live alignment on an actual phone.
10. Expand to the full milestone gates with saved evidence.

## 9. Required evidence before declaring completion

Keep an environment/version manifest, device matrix, consented evaluation inventory, reproducible job inputs, raw metric reports, standard comparison renders, failure counts, model/license inventory, cost traces, and passing acceptance results.

The technology preview is complete only when a recorded end-to-end run and the acceptance reports substantiate the product contract. A specification, a polished concept image, a researcher-provided demo, or a standalone camera filter does not satisfy that gate.
