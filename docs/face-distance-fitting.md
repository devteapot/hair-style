# Surface distance in decoder fitting

2026-09-11. This experiment addresses the plan's physical-constraint solver work. It is not an accepted haircut or a physical-accuracy result.

`tools/face_distance.py` provides differentiable unsigned point-to-triangle-surface squared distances in Torch. Interior projections use barycentric membership; exterior projections use closest edges/vertices. Degenerate triangles reduce to edges/vertices. Triangle chunking limits individual intermediate allocations, though autograd retains work across chunks. The function does not depend on face winding and does not establish inside/outside status or clearance between curve samples.

Five tests in `tools/test_face_distance.py` pass, including known plane/edge/vertex distances, degenerate geometry and finite gradients, finite-difference gradient checks, rigid-transform and winding invariance, chunk equivalence, invalid inputs, and CPU/MPS values and gradients. Run with `.research/metal-env/bin/python -m unittest discover -s tools -p test_face_distance.py -v`.

An actual participant-derived check evaluated 199 vertex/midpoint samples on guide `haar-00632` against 17,370 observed-face triangles. CPU and MPS distance values and proximity-loss gradients agreed at the recorded tolerances; both had finite gradients. The local report is `outputs/face-distance-probe/report.json`. This establishes numerical agreement, not measured anatomical accuracy.

The decoder probe now accepts optional `--face-distance-penalty`, restricted to single-guide experiments to bound memory. It retains root preflight, verified preparation replay, frozen decoder weights, the ±0.25 latent trust region, envelope objective and optional regional length constraints. Vertex/midpoint proximity contributes an additional mean-plus-maximum squared penalty; its target is supplied anatomical clearance plus material radius plus a 1 mm experimental buffer. This does not replace final canonical segment clearance. The backend runner does not enable this experimental mode.

## First actual decoder experiment

`outputs/face-distance-latent-632-v2/` uses the fresh short-fringe sample and its verified preparation. It starts from that source latent, not the subsequently rotated/attachment-adjusted studio candidate. The first attempt, retained separately in `outputs/face-distance-latent-632/`, incorrectly specified a 0.1 mm material radius; preflight rejected seven roots before loading the model. The corrected run uses the existing 0.05 mm radius from the earlier verified candidate.

The 200-step run completed in 17.94 seconds of optimization. Decoder-loss gradients agreed between CPU and MPS. Minimum sampled distance increased from approximately 0.0191 mm to 0.0806 mm, but **45 samples remain below the 2.05 mm experimental target**. Root displacement is zero; maximum curve-point displacement is 3.448 mm; length changes from 40.968 to 43.709 mm and remains within the brief. The inferred-envelope check passes. Independent float64 tensor replay confirms the length result, exact root preservation, and movement below the existing 20 mm candidate bound.

No canonical haircut was exported, no studio candidate was replaced, and no collision-free or physically feasible result is claimed. Unsigned distance can push samples to either side of an open face surface; it is insufficient as a sole containment constraint. The six conflicts in the saved fresh-short candidate remain unresolved. Further fitting must preserve the existing movement/length/attachment limits and pass exact continuous-segment checks; more samples or a lower loss alone cannot establish clearance.

## Exact segment evaluation of the decoder result

The follow-up `tools/check_single_latent_clearance.py` creates an explicitly labeled research copy and runs the canonical checker before and after substituting the single optimized curve. It verifies input/anatomy snapshot hashes, one-guide identity, finite tensors, exact tensor-root preservation, and the 20 mm movement bound. It restores only the 1.12 nm float32 root-coordinate rounding difference to the existing canonical attachment. No selection or publication occurs.

On `haar-00632`, exact segment violations decrease from 11 to 8. Total violations decrease from 68 to 65, with 762 other guide records and their clearance results unchanged. Root checks remain unchanged. The research candidate canonical hash is `bada94af384273a4f271649054829644bf4a607f16dbd5a0b5c7c1845cc03efd`; artifacts are under `outputs/face-distance-latent-632-clearance/`. This is evidence of partial geometric improvement, not successful fitting.

An additional 104-orientation fixed-root rotation search leaves all eight conflicts unresolved and retains the input curve. This motivates testing attachment and direction jointly with the new decoded shape, without changing existing bounds. The previously saved studio remains unchanged throughout these experiments.

The joint follow-up completed in 120.63 seconds, testing all 16 shortlisted attachments with the existing rotation search and 4 mm root-movement limit. None clears the selected guide; residual conflicts range from 7 to 15. No proposal was selected or written as a final haircut. Reports are under `outputs/face-distance-latent-632-joint/`. This exhausts this bounded attachment/direction search for this decoder output, not the space of possible personal hairstyles. The next fitting experiment needs a different curve-generation or optimization strategy; repeating these root/orientation trials is not justified by the result.

The single-curve evaluator also rejected a deliberately mismatched generation-input snapshot before creating any candidate directory. Participant artifacts remain local and ignored.

## Reusing anatomy for candidate checks

`GuideClearance.checkBatch` and the `capture-inspect hair-clearance-batch INPUT.json HAIRCUTS.json ANATOMY.json REPORTS.json` command reuse the existing anatomy acceleration structure across at most 256 candidates and 10,000 total guides. Every candidate still receives canonical validation and the existing complete root/segment checks. Output reports preserve order and individual haircut hashes. The command exits with status 2 if any candidate fails surface clearance; missing anatomy and physical acceptance remain explicit in each report.

All 150 core tests pass, including equality with independent individual checks, differently sized candidates, invalid geometry rejection, and empty/oversized batch rejection. Eight actual participant-derived candidate reports match their individual-check reports in every field (`outputs/clearance-batch-parity/verification.json`). This reduces repeated setup work without introducing an approximate clearance path. It is not a physical-accuracy validation.

## Regional decoder-neighbor search

`tools/probe_face_clear_latent_neighbors.py` searches the 32 closest same-region source latents at four interpolation fractions, clamps deviations to ±0.25 from the selected original latent, and decodes all 128 shapes with the selected guide's local frame. CPU/MPS decoded coordinates must agree. Roots stay fixed; regional length, continuous inferred-envelope and 20 mm original-decoder movement bounds filter candidates before exact anatomical clearance. The search uses verified preparation and root preflight before loading the model. Same-region latent interpolation can change curl or styling intent; a geometric pass alone would not establish a coherent hairstyle.

For `haar-00632`, 108 of 128 candidates pass the preliminary bounds. All 108 fail exact face clearance; the best retains eight segment violations. No candidate is selected or promoted. The initial sequential exact-check stage takes 330.71 seconds (`outputs/face-clear-neighbors-632/report.json`). This rules out this particular bounded set, not all generated shapes or all possible fitting strategies.

Replaying all 108 identical candidates with shared anatomy produces reports equal in **every field** to the sequential reports and takes 7.24 seconds for the batch invocation (`outputs/clearance-batch-full-parity/verification.json`). The older timing includes its per-candidate copy/serialization loop as well as subprocess checks, so this is a workflow timing comparison rather than an isolated kernel benchmark. The neighbor-search runner now uses the batch command. The unsigned iPhone build passes; no phone install or camera action was performed.

A complete rerun through the updated runner (`outputs/face-clear-neighbors-632-batch/`) produces the same 108 candidate decisions, including lengths, movements and collision counts, and again selects none. Its whole candidate-check stage, including copy/serialization work, takes 24.51 seconds versus 330.71 seconds previously. The narrower 7.24-second timing above measures only the standalone batch invocation. Model loading and decoding are outside both candidate-check stage timings.

## All six unresolved guides

The runner now constructs only the single-guide haircut records needed for batch checking. It assembles a complete haircut only if a candidate clears the supplied anatomy, avoiding a retained full 763-guide copy for every trial. The regression run for guide 632 reproduces all previous candidate decisions exactly, with candidate-check time reduced from 24.51 to 7.19 seconds. No weaker geometric checks are introduced.

The subsequent local sweep completes in 141.95 seconds including repeated preparation checks and model loading. It explores 768 decoded candidates across the six unresolved guides; 666 pass preliminary constraints and receive exact segment checks:

| Guide | Eligible/tested candidates | Fewest remaining segment conflicts |
|---|---:|---:|
| 632 | 108 | 8 |
| 633 | 106 | 9 |
| 656 | 121 | 6 |
| 657 | 107 | 9 |
| 678 | 113 | 7 |
| 679 | 111 | 9 |

No guide obtains a clear candidate. An independent replay of all 666 serialized candidate records confirms exact root coordinates and bindings, lengths within their respective brief bounds, at most 13.161 mm movement from original decoded points, and nonempty exact segment-conflict reports with no root conflicts. Reports and candidates remain local under `outputs/face-clear-neighbor-sweep/`; the summary and independent-check files identify the unchanged original research candidate. No studio or physical-phone state was modified.

This exhausts this bounded same-region latent neighborhood for all six guides. It does not prove that these constraints are infeasible or that the model cannot generate a fitting style. Repeating these candidates is not warranted. Further work should investigate the personal attachment/frame mapping and a different conditioning strategy rather than treating the lowest collision count as a valid haircut. A read-only phone inventory still contains the same nine capture entries, so no newly saved dense capture was available during this sweep.

## Actual template-frame audit

`tools/audit_personal_root_frames.py` replays the exact canonical clearance report, verifies all source root positions against the pinned decoder template, and derives transformed surface normals from the actual global-to-local frame. Normals use the inverse transpose of the nonuniform point transform. The upstream float32 frames have maximum orthogonality residual 0.000104, so the diagnostic does not assume their inverses are exact rotations. An earlier diagnostic rejected that overly strict assumption; the model itself was not changed.

Three numerical tests cover nonuniform scale combined with shear, rotation, and invalid/reflected frames. On all 763 actual frames, inverse-transpose normals agree with independently crossed transformed tangents to 2.22e-16. Source root replay error is zero. Artifacts are local under `outputs/personal-root-frame-audit-v4/`.

The six conflicting guides have median source-to-inferred-scalp normal mismatch 5.33° (maximum 7.31°), compared with 6.99° median among the other 757 guides. Their initial tangents point outward from the inferred scalp. This does not support a simple flipped local frame as the cause; anatomical orientation and correspondence are still unverified.

An experimental minimal rotation aligning each actual source normal with its inferred target normal preserves all roots and pairwise curve distances. All six proposals remain within the length/envelope constraints and 20 mm original-decoder movement bound (maximum 5.63 mm). Exact segment conflicts remain: 10, 11, 13, 11, 8, and 10 for guides 632, 633, 656, 657, 678, and 679 respectively. Reports in `outputs/root-normal-transport/` remain diagnostic; none was promoted. Normal alignment alone does not resolve these conflicts.

## Collision localization on the observed surface

`tools/diagnose_curve_surface_conflicts.py` first replays the exact canonical report, then locates each reported collision triangle within edge-connected surface components and computes its graph distance to an open edge. Four topology tests cover open/disconnected surfaces, a closed tetrahedron, an interior triangle, and winding/nonmanifold diagnostics. No surface cleanup or collision suppression is performed.

On the current face mesh, all 68 collision records refer to 17 distinct triangles in the largest connected component (17,215 of 17,370 total triangles). The complete mesh has nine components, 592 boundary edges, zero nonmanifold edges, and zero inconsistent winding edges. The collision-witness triangles have open-edge hop counts 0/1/2/3/4 in 6/9/11/37/5 records respectively. Thus detached fragments do not explain these conflicts; an open edge alone also does not identify an erroneous triangle.

Every reported conflicting segment lies within the first 7.68 mm of its curve measured from the root. Earliest conflict starts are 0.63, 0.23, 1.28, 0, 0.65, and 0 mm for guides 632, 633, 656, 657, 678, and 679. This motivates a root-departure constraint against nearby observed geometry instead of another whole-curve orientation sweep. The result does not establish sensor accuracy, classify the underlying tissue, or prove that a new constraint will succeed. Local outputs are in `outputs/curve-conflict-topology/`.

## Experimental local departure planes

`tools/root_departure.py` constructs triangle-separating planes using each triangle's closest point to the fixed root. The root-to-closest-point vector gives a plane direction independent of triangle winding, including when the closest point lies on an edge. Every triangle is checked to lie on the opposite side of its plane from the root. Triangles within 12 mm are considered; the target margin is anatomical clearance plus material radius plus a buffer capped by the fixed root's existing distance. Root preflight remains authoritative.

The single-guide decoder probe enables this optional objective with `--root-departure --face-distance-penalty`. It applies to the first 12 mm of the original curve's arc length (fixed sample indices), while retaining the envelope and length objectives, fixed root, ±0.25 latent bound, and CPU/MPS gradient comparison. It is not enabled in the production conditioning runner. These conservative half-spaces may reject valid routes around triangle edges and do not establish anatomical inside/outside status.

Four tests pass for interior/edge projections, winding invariance, fixed-root feasibility, invalid inputs, and the direction and CPU/MPS agreement of loss gradients. On guide 632, 101 nearby planes constrain 30 samples. The 200-step run completes in 16.40 seconds, with CPU/MPS decoder gradients agreeing. Maximum plane violation decreases from 9.81 to 4.40 mm but remains nonzero. The curve shortens to 29.886 mm, violating its 40 mm minimum by 10.114 mm. Independent float64 replay confirms this failure, exact root preservation, and 12.220 mm maximum movement from the original decode.

Canonical validation rejects the substituted research curve for its length violation before producing a candidate clearance report. No collision-free result is claimed, no studio selection changes, and no invalid curve is promoted. Local reports remain under `outputs/root-departure-632/` and `outputs/root-departure-632-clearance/`. This experiment demonstrates that this weighted objective can trade away required length; further optimization must preserve feasibility rather than accept a lower plane loss as progress toward a usable haircut.

## Continuous rotation with length preserved

`tools/probe_continuous_root_rotation.py` optimizes proper rigid rotations around the existing roots, using the departure-plane and inferred-envelope losses. Rotation preserves each curve's shape and length by construction. Each of the six guides uses seven initial orientations and 300 Adam steps, constrained to the existing 20° rotation budget. The final geometry is reconstructed in float64 and filtered by envelope and 20 mm movement from the original mapped decoder curve before exact canonical batch clearance.

`tools/root_rotation.py` uses a sinc-based axis-angle formula with finite derivatives at zero. Four tests verify a known quarter turn, finite-difference gradients at zero and nonzero angles, proper rotation matrices, and CPU/MPS gradient agreement. All 13 rotation/departure/distance tests pass. Full objective gradients also agree between CPU and MPS in the actual six-guide experiment.

The final replay completes in 13.95 seconds and checks all 42 candidate orientations. Independent checks confirm exact roots and bindings, all regional length bounds, pairwise curve-distance preservation to 2.43e-17 m, and maximum movement 14.144 mm from the original mapping. All candidates still collide; best remaining segment counts are 24, 12, 10, 10, 16, and 10 for guides 632, 633, 656, 657, 678, and 679. These results do not improve the saved candidate. This confirms that preserving length alone does not make the conservative plane objective adequate for the observed geometry.

Artifacts remain under `outputs/continuous-root-rotation-v3/`. The first run completed geometry checking but failed JSON report serialization; the corrected runs retain native booleans and record the original mapping as the cumulative movement reference. No candidate is promoted, and the default conditioning pipeline and native studio remain unchanged.
