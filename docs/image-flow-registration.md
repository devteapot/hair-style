# Calibrated image-flow registration

The rear registration worker now matches nearby native RGB images with Vision optical flow, checks the matches in both directions, and lifts them into metric camera coordinates using the original depth and intrinsics. It estimates a rigid transform without changing scale or using a camera-pose initializer. Run `capture-inspect flow-register BUNDLE REQUEST.json REPORT.json` with source/target frame IDs and explicit native-depth masks.

Normal tracking, aligned depth, native unmirrored images, synchronized timestamps, valid depth/confidence and intact payload hashes are required. Up to 400 surviving matches are split between fitting and validation. These samples share the same images and sensor errors: withholding matches from fitting does not make this an independent accuracy measurement.

## Verification

Vision revision 1 passed the known 8×5-pixel translation and reverse-consistency test. Revision 2 did not meet that same test's displacement tolerance, so this worker explicitly selects revision 1. An end-to-end test encodes two JPEGs and calibrated depth bundles, then recovers their expected 20 mm horizontal and 12.5 mm vertical translation within 1 mm. Synthetic evidence stays labelled synthetic and does not authorize full-head acceptance. All 77 core tests pass.

Four adjacent pairs from the existing assisted rear capture were evaluated without changing registration thresholds:

| Frame indices | Consistent matches | Local gate | Withheld median / p95 |
|---|---:|---|---|
| 10 → 11 | 1,263 | No consistent rigid fit | — |
| 30 → 31 | 425 | Pass | 3.33 / 8.28 mm |
| 56 → 57 | 968 | Fail | 2.93 / 10.85 mm |
| 80 → 81 | 1,838 | Pass | 1.91 / 7.40 mm |

Both passing transforms were checked against every vertex of independently constructed single-frame depth patches, without refitting or trimming. Pair 30 → 31 has bidirectional nearest-surface p95 distances of 10.63 / 10.51 mm; pair 80 → 81 has 5.04 / 6.02 mm. These comparisons include mask boundaries and occlusions and are diagnostic rather than anatomical ground truth. Local landmark acceptance alone is insufficient to authorize full-head fusion.

Reports, requests and partial surfaces remain in ignored `outputs/rear-image-flow/`. Aggregate evidence and hashes are in [the verification record](evidence/image-flow-registration-verification-2026-09-10.json). No phone model was replaced. The next reconstruction work is to establish reliable connected multi-view alignment, handle subject motion and semantic masks, and evaluate closure and front/rear registration before fitting a scalp.

## Vendor coordinate audit

A separate same-session Object Capture audit requested default and explicit identity-transform model exports. Their 4,755 vertices and 9,506 triangles were identical, including positions. This rules out a default-versus-explicit-identity export transform as the cause of the previously observed depth disagreement. It does not prove camera-pose conventions or metric accuracy. The audit tool is `tools/audit_vendor_coordinates.py`; private model evidence remains in `outputs/object-capture-coordinate-audit/`.

## Complete rear-pass graph and short loops

`tools/register_rear_flow.py BUNDLE MASKS.json NEW_OUTPUT_DIR` now evaluates all adjacent masked frames, writes each request/report, and records graph components including isolated frames. It never bridges a missing mask silently, adjusts thresholds, or emits a fused head. `tools/audit_flow_loops.py BUNDLE GRAPH_DIR NEW_OUTPUT_DIR` separately matches endpoints of each passing two-edge chain and compares the direct transform with the composed transform.

On this assisted capture, all 82 adjacent pairs across 83 masked frames finished successfully as tool runs. Only 23 local registrations passed; 45 failed the withheld-match gate and 14 produced no consistent rigid candidate. The resulting graph has 60 components, including 50 isolated frames. Its largest component is seven frames (indices 41–47), so it does not provide an orbit-wide registration.

Of 13 eligible two-edge chains, five direct endpoint fits passed. Their direct-versus-chain discrepancies, evaluated at the original masked depth points rather than the camera origin, were:

| Frame chain | Surface median | Surface p95 |
|---|---:|---:|
| 42 → 43 → 44 | 1.35 mm | 1.73 mm |
| 45 → 46 → 47 | 1.04 mm | 2.18 mm |
| 71 → 72 → 73 | 0.60 mm | 1.36 mm |
| 80 → 81 → 82 | 1.98 mm | 4.41 mm |
| 81 → 82 → 83 | 0.73 mm | 1.66 mm |

These are consistency checks using shared sensor data, not physical accuracy measurements. Failed endpoint fits cannot establish whether their chains are correct. The passing loops support retaining some local candidates, but do not repair graph disconnection or establish front/rear alignment. The present optical-flow route alone cannot support complete-head fusion on this capture. Next work must address correspondence and semantic selection or revise the reconstruction approach; retrying the same full pass is not justified by these results.

Graph connectivity and noncommuting transform composition checks pass with `python3 tools/check_flow_graph.py`. Aggregate results and source report hashes are retained in [graph evidence](evidence/rear-flow-graph-verification-2026-09-10.json). Original captures and the installed preview remain unchanged.
