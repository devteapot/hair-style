# Dense surface agreement

`DenseSurfaceAgreement` checks two single-view observed surfaces with the fixed transform from their accepted captured landmark registration. It compares every point in both directions using exact nearest-sample search. It does not fit a new transform, trim outliers, impose a search-distance cutoff, or declare anatomical accuracy.

```sh
.build/debug/capture-inspect surface-agreement SOURCE_SURFACE.json TARGET_SURFACE.json CAPTURED_REGISTRATION.json OUTPUT.json
```

The single-frame metadata hashes and capture/frame names must match the captured registration, both surfaces must use their original optical coordinates, and all supplied points/normals must be finite and within processing bounds. The report binds canonical hashes of all three inputs. Like the remesher, this offline tool does not authenticate arbitrary external JSON; use artifacts produced by the verified capture-backed commands.

Each direction reports sample count, median, nearest-rank p95, maximum, fractions within 3 and 10 mm, opposing-normal fraction and every sample's nearest index, Euclidean distance, signed point-to-plane distance and normal dot product. No samples are discarded from these statistics. This preserves visibility into mismatched mask boundaries or unmatched areas that a one-directional or trimmed comparison could hide.

Nearest samples are not verified anatomical correspondences. Surface sampling density, mask differences, depth noise and occlusion influence the result. Pixels are correlated, and these clouds include areas used for landmark registration; this is not independent ground truth. The 3/10 mm fractions are descriptive, not acceptance gates. Per-point residuals support local inspection and future quality masks.

## First physical replay

All four accepted pairs around reference frame 20 were replayed. Native depth remained unchanged.

| Source frame | Source→reference p95 | Reference→source p95 | Largest distance in either direction |
|---|---:|---:|---:|
| 18 | 3.54 mm | 3.66 mm | 13.01 mm |
| 19 | 2.32 mm | 2.42 mm | 38.47 mm |
| 21 | 2.30 mm | 2.22 mm | 43.41 mm |
| 22 | 3.03 mm | 3.04 mm | 40.14 mm |

An inspected residual heatmap for frame 21 versus reference 20 places the largest reference-side disagreements in small boundary fragments. Central facial samples mostly have much smaller distances. This supports investigating connected-fragment and mask quality before relaxing alignment thresholds. It does not explain all remeshing holes or establish metric accuracy. Reports and participant-derived renders remain under ignored `outputs/dense-agreement/`.

Three tests verify asymmetric missing coverage without trimming, exact nearest search against brute force with signed residuals, and rigid normal transformation/evidence mismatch rejection. The full core suite has 62 passing tests. An unsigned iPhone SDK build passed; no new camera or live preview behavior was exercised.
