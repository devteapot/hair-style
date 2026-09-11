# Guide clearance against supplied anatomy

`GuideClearance.check` measures each guide segment's distance to supplied face/ear triangles. It includes the canonical material radius and an explicit additional clearance margin. A segment crossing a triangle, or passing closer than its capsule radius plus margin, is reported as a violation. This is part of M2.4's constraints, not a complete physical feasibility verdict.

`GuideClearanceInput` binds to the exact scalp hash used by the haircut. It contains `schemaVersion: 1`, `clearanceMeters` (0–0.02), and one to three surfaces. Each surface supplies a unique `region` (`face`, `anatomical_left_ear`, `anatomical_right_ear`), `origin` (`observed`, `inferred`, `synthetic`), `sourceSHA256`, canonical-meter `vertices` and `triangles`. Missing regions remain explicitly listed in the report. Supplied provenance and anatomical coverage still need external verification.

The checker first runs the existing haircut binding/length validation. It rejects invalid indices, nonfinite/degenerate geometry, duplicate regions, mismatched scalp revisions and excessive input sizes. A bounding-volume hierarchy prunes distant triangles; candidate distances include segment/triangle intersection, endpoint-to-triangle distances and segment-to-edge distances. Tolerances account for numerical precision. It reports the nearest violating triangle per guide segment/surface, not every touching triangle.

Processing limits are three surfaces, 100,000 vertices and 200,000 triangles per surface, ten million triangle comparisons and ten thousand violation records. Exceeding a budget fails the check; it does not publish a truncated passing report. Triangle-comparison counts are diagnostic workload information, not a device performance benchmark.

## Run and constrain edits

```sh
tools/dev.sh swift run capture-inspect hair-clearance \
  input.json haircut.json anatomy.json clearance-report.json

# The optional final anatomy argument checks the edited result before saving:
tools/dev.sh swift run capture-inspect hair-edit \
  input.json haircut.json edit.json result.json history-directory anatomy.json

python3 tools/check_clearance.py
```

`hair-clearance` exits 0 when guides clear the supplied triangles, 2 when violations are reported, and 1 for invalid input or processing failure. Exit 0 is not a physical feasibility approval. `HaircutEditor.apply(..., anatomy:)` and the optional CLI argument reject a violating edit before revision persistence. A successful result includes an optional `clearance` report bound to the new haircut and anatomy hashes. Calls without anatomy retain the earlier geometric-edit behavior; do not assume they performed clearance checks.

The immutable repository still stores the canonical input/haircut records. Keep the edit result and anatomy input alongside them if clearance evidence must be replayed. Repository validation alone does not imply anatomy was supplied or checked. Native guide studio remains a synthetic lab without face/ear meshes and does not run this additional check yet.

## Scope of a pass

All reports retain `publishableAsValidatedDesign: false`. A curve wholly inside closed anatomy can be distant from every boundary triangle; this version does not perform inside/outside classification. It also does not check scalp/root emergence, missing or mislabeled anatomy, interpolated strands between guides, physical hair deformation, hairline/flow or regional continuity. Open/partial face and ear surfaces cannot establish those properties. Do not convert `surfaceChecksPassed` into the product's strongest feasibility label.

Tests cover crossing, coplanar intersection, parallel separation, nearest edges/vertices, material radius and margins, hierarchy agreement with brute force, invalid inputs, and an expanding edit that passes length validation but fails supplied-anatomy clearance. The CLI verifies that the rejected edit writes neither a result nor repository revisions, while a safe shortening stores both parent and child. All geometry evidence here is synthetic; real-person meshes and rendered physical review remain required.

## Fixed-root feasibility

Clearance reports now separately include `rootViolations`, using point-to-triangle distance at each root with the same material-radius-plus-margin requirement and shared BVH/comparison budget. The existing segment violations are preserved. Legacy reports decode this field as unknown (`nil`), not an empty successful check. A root violation proves that curve-only regeneration preserving that root cannot satisfy this supplied surface constraint. It calls for attachment/scalp/anatomy review, not automatically removing guides or reducing the margin.

The geometry-conditioned research candidate has 353 segment violations across 23 guides, concentrated in fringe and anatomical-left regions. Six fixed roots violate the supplied partial face surface: distances 0.089–0.980 mm versus required 1.05 mm. Independent all-triangle nearest-point calculations reproduce every root distance within 1e-10 m. Both ears are still missing and the observed face is incomplete/noisy, so this is an inconsistency in the current supplied geometry, not proof of accurate biological attachment positions.

The root-classification validation passed all 125 then-current core tests and the iPhone SDK build. Actual candidate replay preserves all 353 segment violations and adds six root classifications. Reports remain under `outputs/personal-latent-regional/face-root-clearance.json` and `root-clearance-verification.json`. Native review now displays these classifications and attachment markers; attachment correction remains unfinished.

## Pre-generation root check

`GuideClearance.preflightRoots` checks proposed mapping attachments directly against supplied anatomy, before any haircut or neural curves exist. It uses the proposed material radius, the same clearance margin and geometry budgets, and records input, binding and anatomy hashes. Missing face/ear regions remain explicit and `physicalFitVerified` remains false even when supplied surfaces pass.

```sh
.build/debug/capture-inspect hair-root-preflight \
  input.json mapping.json anatomy.json 0.00005 root-report.json
```

The CLI verifies the mapping's scalp hash and exits 2 when attachments require review. Actual replay checks 763 proposed roots and flags the same six conflicting attachments, with both ears missing. Both local personal-conditioning research tools enforce this check before neural imports. Automatic backend/native personal-generation enforcement remains unwired. All 127 core tests and the iPhone SDK build pass.

## Localization at the inferred scalp seam

`tools/diagnose_attachment_seam.py INPUT MAPPING ANATOMY PREFLIGHT OUTPUT` first replays the canonical preflight and requires an identical report, then measures root distances to open scalp and anatomy boundary edges. It rejects nonmanifold surfaces and currently supports zero-offset bindings only.

Actual participant replay places all six conflicts on adjacent inferred scalp triangles 2894/2895 in the fringe region. All six lie within 3.711 mm of the construction boundary, and four are directly on it to numerical precision. Their closest points on the open face boundary are 3.965–6.428 mm away; five conflicting face triangles do not themselves touch a boundary. This localizes the problem to the inferred scalp seam/root mapping, rather than establishing that every conflict is a face-edge artifact. It does not decide whether scalp dimensions or face registration are anatomically correct. Review the seam and boundary-clamped root proposal before changing attachments; do not interpret the construction edge as a measured hairline. Private evidence: `outputs/personal-latent-regional/attachment-seam.json`.

The mapping proposer now separately reports open-boundary attachments, rather than treating every zero barycentric coordinate as a scalp-edge hit. The current 763-root mapping has 104 roots on its 64-edge open boundary: 75 fringe, 16 anatomical-left, eight anatomical-right and five nape. This exposes substantial clamping from nearest-triangle correspondence to a truncated cap. The report marks boundary review required; it neither discards roots nor changes scalp geometry. A synthetic square-mesh test verifies that a shared internal diagonal is not counted as the open boundary, while outer edges and corners are. Private replay: `outputs/personal-latent-regional/attachment-boundary.json`.

## Alternative cap correspondence experiment

`tools/propose_cap_correspondence.py SOURCE TEMPLATE INPUT MAPPING OUTPUT` tests a separate correspondence preserving source-root azimuth and fractional latitude within the source cap. It checks that the template's boundary traverses azimuth once, interpolates its angular extent, and transfers fractional latitude to the existing target cap. Out-of-range source coordinates are rejected rather than clipped. Target roots bind to the nearest triangle only after that cap mapping. Existing scalp, guide identities, region labels, material/clearance and root-correction limits are retained. This is a new unreviewed proposal, not an in-place repair of an accepted haircut.

Actual replay preserves all 763 guides and eliminates open-edge clamping (104 to zero). Canonical root preflight reduces supplied-face conflicts from six to one; both ears remain missing. However, maximum root movement is 25.213 mm, maximum source-to-attachment correction is 33.345 mm, and 18 guides exceed the unchanged 30 mm research correction bound. The proposal therefore remains rejected, and no neural run follows. It demonstrates a correspondence contribution to the failure without establishing a valid scalp shape, hairline or complete mapping. Private outputs: `outputs/cap-correspondence/`.

The optional `--transfer-fraction` interpolates angular latitude globally between the source latitude and full normalized-cap transfer. It validates a finite value in 0…1, records the value in the mapping method/report, and does not change correction limits. A bounded sweep tests whether a smaller transfer is sufficient:

| Fraction | Open-edge roots | Root face conflicts | Roots above 30 mm correction |
|---|---:|---:|---:|
| 0.25 | 86 | 5 | 0 |
| 0.50 | 58 | 2 | 1 |
| 0.75 | 25 | 3 | 1 |
| 1.00 | 0 | 1 | 18 |

Every tested candidate fails. All 18 full-transfer correction failures are fringe roots. The quarter-transfer candidate's maximum correction is 29.981 mm, but its five conflicts preclude neural processing. These results reject the tested global interpolation settings as a sufficient repair; they do not mathematically exclude all intermediate settings or other correspondences. Geometry and thresholds remain unchanged. Private sweep reports and canonical replays: `outputs/cap-correspondence-sweep/`.

## Bounded front-boundary proposals

`tools/probe_scalp_boundary.py SOURCE INPUT MAPPING REVIEW ANATOMY NEW_OUTPUT` builds four separate inferred-cap proposals with front boundary raised 1–4 mm through the canonical Swift scalp builder. Each retains all 763 barycentric guide bindings, source transform, original brief limits/profile, 30 mm source-to-root correction limit and observed anatomy. The material radius remains 0.05 mm and supplied clearance margin 1 mm. Only the inferred cap and its dependent hashes/revision change; no existing haircut is rewritten or accepted. The baseline root preflight is replayed before proposals are made.

| Front boundary raise | Root conflicts | Roots beyond unchanged correction limit | Maximum source correction |
|---|---:|---:|---:|
| 1 mm | 5 | 1 | 30.665 mm |
| 2 mm | 3 | 2 | 31.550 mm |
| 3 mm | 6 | 2 | 32.442 mm |
| 4 mm | 5 | 7 | 33.343 mm |

All four proposals fail. Both ears remain missing. This rules out these small uniform front-boundary shifts with fixed correspondence as a sufficient correction; it does not rule out other scalp models or establish measured hairline placement. No neural generation followed these failures, and the limits were not relaxed.

Independent nearest-triangle calculations verify all 19 reported conflict distances with maximum absolute difference below 1e-17 m. Replay also checks that observed surfaces, clearance, mappings, topology, brief length limits and hair profile remain identical where intended. Private artifacts and verification: `outputs/scalp-boundary-proposals-v2/report.json` and `verification.json`. The initial stopped attempt used an incorrect review field name and produced only a baseline; it was corrected before the complete run. Core and app behavior did not change in this experiment.

## Local surface attachment search

`tools/propose_local_attachments.py SOURCE INPUT MAPPING ANATOMY NEW_OUTPUT [--refine-directions]` keeps the scalp and observed anatomy fixed. Only roots failing a replayed canonical preflight are eligible for a new barycentric binding. The initial deterministic search uses 26 directions at 0.5, 1, 1.5 and 2 mm; refinement adds 256 uniformly distributed sphere directions. Each probe projects to the exact nearest scalp triangle and must retain movement ≤2 mm, source correction ≤the existing 30 mm bound, and clearance above the unchanged material-plus-margin distance (with an additional 0.01 mm numerical buffer). It rejects newly closer near-coincident roots, but does not establish root order or anatomical hairline placement.

The initial and refined searches both reduce supplied-face root conflicts from six to three. Refinement proposes movements of 1.269 mm for guide 633, 0.240 mm for guide 658 and 1.242 mm for guide 680. Guides 657, 679 and 700 remain conflicting; failure of a finite sample search is not a proof of infeasibility. All 763 guide identities/regions remain, 760 bindings are exactly unchanged, and no source correction exceeds the original limit. Canonical Swift preflight checks the entire proposed mapping after search and still rejects it. Both ears remain absent.

No scalp, observed face, guide curves, existing haircut or acceptance threshold was changed, and no neural run followed the failed preflight. Hairline, neighboring-root order, growth direction, emergence and whole-curve clearance still require validation. Private artifacts: `outputs/local-attachment-proposal-refined/report.json`, `preflight.json` and `verification.json`. This is a separate unaccepted mapping proposal, not a repaired or accepted personal haircut.

## Wider local proposal and whole-curve check

The optional `--maximum-movement-meters 0.004` extends the *research search radius* from 2 to 4 mm; it does not change the existing 30 mm source-correction limit or the material/face clearance threshold. With 282 directions and eight radial samples, it finds positions for all six conflicting roots. Actual movements range from 0.240 to 3.115 mm. All 763 guides remain, all source corrections meet the existing limit, and canonical root preflight reports zero supplied-face root conflicts. Both ears and anatomical hairline validation remain absent. This does not approve the mapping as a physically correct scalp attachment field.

`tools/probe_rebound_haircut.py SOURCE INPUT BASE_MAPPING PROPOSED_MAPPING HAIRCUT ANATOMY NEW_OUTPUT` validates the original canonical haircut and proposed roots, verifies mapping lineage and unchanged limits, then translates only the six changed whole-guide curves to their proposed roots. It writes a separately identified research artifact with source hashes and retained model-sampling provenance. It does not alter curve-relative shape or replace the original haircut. Root preflight uses the largest material radius present in the validated source haircut.

Actual canonical validation passes all 763 rebound guides, including root binding, lengths and the unchanged inferred-envelope guard. Full face clearance still fails: 343 segment violations across 23 guides, zero fixed-root violations, and both ears missing. Independent array comparison verifies 757 guide records are exactly unchanged and the six translated curves retain relative coordinates within 7e-18 m. No complete hairstyle or physical fit is accepted. The next geometry problem is whole-curve clearance with roots held fixed, rather than another root-only correction.

Private evidence: `outputs/local-attachment-proposal-4mm/` and `outputs/rebound-personal-haircut/` contain the mapping, preflight, canonical validation, all segment violations, lineage report and verification. These remain research artifacts; no native selected haircut or installed phone build was changed.

## Fixed-root whole-guide rotations

`capture-inspect hair-rotate-proposal INPUT HAIRCUT ANATOMY OUTPUT` tests 24 orientations per conflicting guide: ±5, ±10, ±15 and ±20 degrees around each canonical axis. The source must already pass canonical validation and have no fixed-root conflicts. Point movement is bounded to 20 mm. Each candidate is checked with canonical length/root/envelope validation and exact supplied-anatomy segment distances; the final report checks every guide together. Unresolved guides are retained, never omitted. A prepared anatomy hierarchy is reused internally without skipping candidate validation.

All 137 core tests and the unsigned iPhone build pass. Synthetic tests verify a solved plane obstacle, unchanged roots and all pairwise curve distances, preservation of unaffected guides, rejection of root conflicts and explicit retention of unsolved curves.

The actual rebound participant candidate clears 16 of 23 conflicting guides. Full clearance decreases from 343 to 122 segment violations, across seven remaining guides, with zero root violations. All 763 roots are exactly unchanged; 747 guide records remain identical. Independent all-pairs distance comparison verifies rigid shape retention within 2.1e-17 m, and maximum point movement is 17.167 mm. The before/after front and side diagnostic was inspected. Neighbor continuity, actual growth direction, interpolated hair, both missing ears, physical fit and style suitability remain unverified. The proposal is not accepted or installed as the selected haircut.

Private replay: `outputs/rotated-personal-haircut/proposal.json`, `haircut.json`, `verification.json` and `comparison.png`. The CLI exits 2 while segment conflicts remain. `acceptedForPersonalHaircut` remains false even when supplied surfaces pass.

## Diagonal and dense rotation search

The rotation CLI also accepts `--diagonal-axes` (13 unoriented axes, 104 signed-angle candidates) or `--dense-axes` (adds 64 equal-area hemisphere directions, 616 candidates). Both retain the same ±5/10/15/20-degree angles, 20 mm maximum point movement and exact canonical/anatomy gates. Rodrigues rotation supports arbitrary axes. Tests verify axis normalization, right-hand-rule direction, inverse rotation and complete retention of unresolved geometry; all 138 core tests and the unsigned iPhone build pass.

Applied only to the seven remaining conflicting guides, diagonal axes clear six more. Maximum additional point movement is 16.723 mm, all roots remain exactly fixed, and pairwise curve distances agree within 2.3e-17 m. The final one-guide dense search checks all 616 orientations but finds no passing candidate. It leaves the geometry unchanged: 52 segment violations, all on guide 633; zero fixed-root violations and both ears still missing. This is not a proof that no rigid orientation can work, only that this bounded discrete search did not find one.

Private evidence: `outputs/diagonal-rotated-personal-haircut/` and `outputs/dense-rotated-personal-haircut/`. The latter verification checks the six additional changed guides, 757 unchanged guide records, fixed roots and unchanged dense-search output. The overall hairstyle remains unaccepted. Joint attachment/direction selection is the next candidate investigation; independently minimizing root movement can choose a point from which the source curve remains difficult to clear.

## Joint attachment and direction search

The remaining guide could not clear the supplied face by rotation about its fixed root. `tools/probe_joint_attachment_direction.py` therefore samples roots on the same inferred scalp within 4 mm of the original binding, retains the existing 30 mm source-correction limit, and tries the 104-orientation rigid search at a spatially diverse shortlist of feasible roots. Scalp and supplied face geometry remain unchanged. This is an explicitly bounded research proposal, not a measured attachment correction.

The second shortlisted root clears the remaining curve. Independent replay of `outputs/joint-attachment-direction/haircut.json` passes canonical validation for 763 guides, root preflight, and all supplied-face root/segment checks. The selected root moves 3.9997 mm from its original binding; the largest point movement from the preceding candidate is 9.7848 mm. All other 762 guide records are unchanged; pairwise point distances within the changed curve agree to 1.39e-17 m. Maximum source-root correction remains 29.7873 mm. The new root is 1.4714 mm from its nearest other root. The actual-radius mesh compiles to 214,613 vertices.

Artifacts and independent verification remain local under `outputs/joint-attachment-direction/`. The canonical revision hash is `09083db360d74d4fa82d56f6c602f667796ce75b39a877fe85654a7a95b99798`. Zero distance-check conflicts against the supplied partial face do not establish anatomical containment, ear clearance, neighboring/interpolated strand safety, natural growth direction, physical styling feasibility or aesthetic suitability. All personal acceptance flags remain false.

## Isolated joint search within a conflicting haircut

The joint search now accepts `--guide-id` when several guides conflict. It evaluates only that guide's translated/rotated candidates, merges a selected guide into the unchanged full haircut, and reruns canonical supplied-anatomy clearance. Selection requires the target to clear and every other violation plus the missing-region list to remain exactly unchanged. A non-conflicting target is rejected. Omitting the option still requires exactly one conflicting guide; the existing 4 mm root, 20 mm total point-movement and source-correction bounds are unchanged.

Applied to guide 632 in the new prepared candidate after dense rotation, the fourth shortlisted attachment clears its 15 intersections. Full replay leaves 113 segment violations on six other guides. Independent checks confirm 762 unchanged guide records, 3.99916 mm root movement, 17.50188 mm maximum point movement, 4.29968 mm source-root correction and pairwise curve-distance error below 4.17e-17 m. The moved root is 1.48952 mm from its nearest other root. The actual non-conflicting-target test rejects guide 0 before candidate generation. Evidence is in `outputs/prepared-joint-guide-632/` and `outputs/prepared-joint-nonconflicting-rejected/`.

A subsequent sequential search retains each failed guide unchanged and uses the same original mapping as the root-movement reference. The first two targets, 633 and 657, exhaust 16 shortlisted attachments each without a valid correction (101.28 s and 106.49 s). This establishes failure of this finite search only. Remaining target attempts are recorded under `outputs/prepared-joint-remaining/`; no result is accepted for personal use.

The sequence has now completed in 526.57 seconds. Guides 658 and 700 clear in addition to the earlier guide 632; guides 633, 657, 678 and 679 remain unchanged after exhausting their candidates. Final full clearance has 76 segment intersections across those four guides, no root conflicts and both ears still missing. Independent checks against the dense-rotation baseline find exactly three changed guide records and 760 unchanged records. Maximum point movement is 19.25010 mm, maximum root movement 3.99916 mm, and within-guide pairwise-distance error is below 4.17e-17 m. All three changed roots retain their original source-correction bound. This does not establish that a continuous search or a newly decoded curve cannot resolve the remaining intersections.


A subsequent read-only arc-length diagnostic locates the first conflicting segment at 4.445 mm (633), 3.413 mm (657), 2.507 mm (678) and 3.452 mm (679) from the root along each curve, whose total lengths are 73.896–80.700 mm. These are arc lengths to segment starts, not exact contact positions. `outputs/prepared-joint-remaining/root-proximity-diagnostic.json` retains the measurements. Because conflicts begin near the attachments, truncation alone has not been shown to yield a usable fringe; fitting and head-evidence quality remain the next constraints to resolve. No curves or thresholds changed for this diagnostic.
