# Joint rear-view pose refinement

`tools/refine_rear_views.py` fits rigid corrections for a set of unmerged world-positioned depth patches. This is an offline NumPy experiment, not an accepted head-registration path. It does not scale or deform geometry, merge vertices, change triangles or estimate hidden scalp.

The first view fixes the coordinate gauge. Bidirectional overlap forms a graph; fitting uses sparse source points, a 20 mm correspondence cutoff, normal dot product >=0.7 and 3 mm robust residual weights. Joint point-to-plane least squares estimates corrections for all remaining views. Geometry is centered before solving, rotation variables are scaled to a 10 cm lever arm, and degeneracy is checked before numerical damping. Disconnected/lost overlap, unobservable geometry and excessive corrections stop the solver. Per-step bounds are 3 mm/2 degrees; total bounds are 30 mm/10 degrees. These are provisional experiment limits, not physical accuracy gates.

Reports retain all-distance evaluation and fixed-initial-overlap evaluation in both directions. Overlap is not reselected after fitting to hide disagreements. Evaluated points include fitted and correlated samples; there is no independent ground truth. Every result remains `acceptedForFusion: false`. Per-patch corrections and original source hashes are preserved, including for the last bounded candidate before a stop.

```sh
python3 tools/refine_rear_views.py WORLD_PREVIEW.json NEW_OUTPUT_DIRECTORY
python3 tools/check_rear_refinement.py
```

Requires NumPy. Numerical checks recover known rigid transforms, preserve proper rotations, reject planar degeneracy before damping and reject disconnected clouds.

## Physical trials, 2026-09-10

| Trial | Initial crop | Revised head crop |
|---|---:|---:|
| Views | 12 | 12 |
| Overlap graph edges | 27 | 26 |
| Completed correction iterations | 10 | 5 |
| Median across directional overlap medians, before | 9.08 mm | 9.31 mm |
| Median across directional overlap medians, after | 6.19 mm | 7.77 mm |
| Median across directional overlap p95, after | 14.99 mm | 15.94 mm |
| Stop | Translation bound exceeded | Rotation bound exceeded |

These statistics summarize pairwise distributions rather than pooled independent samples. The two crops have different samples and should not be interpreted as a controlled algorithm-quality comparison.

The initial spatial crop included substantial neck geometry. To inspect that confound, `WorldRegionRequest` now accepts an optional lower world-Y plane. The revised crop uses the median lowest depth-backed Vision face-contour point across seven rear views as a provisional jaw-height estimate. Those estimates span about 7.2 mm vertically. The center is 100 mm above the estimate; all radii are 170 mm; a lower plane lies 15 mm below the estimate. Original source captures remain unchanged. A fixed plane is not semantic neck segmentation and may clip anatomy if the head moves.

The revised crop contains 20,187 mesh vertices in the twelve-view preview. It visibly removes most lower neck geometry, but layered surfaces and rough facial geometry persist. The attempted final correction reaches 11.10 degrees; it is rejected before application. Last bounded candidate corrections reach 15.27 mm at a patch centroid. Increasing limits merely to get a successful termination is not justified by these trials.

Private inputs, reports and four-view renders remain under ignored `outputs/rear-pose-refinement/`, `outputs/rear-head-region-preview/` and `outputs/rear-head-pose-refinement/`. This remains an unresolved registration experiment. Stronger RGB/anatomical correspondences and measured-fixture validation are needed before treating the result as a scalp-fitting surface.
