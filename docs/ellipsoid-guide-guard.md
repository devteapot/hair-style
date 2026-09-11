# Continuous guide constraint for the inferred scalp envelope

`EllipsoidGuideGuard` now checks complete guide segments against the explicitly inferred head envelope. It provides a bounded correction during model import and a check-only rule during subsequent validation, edits and repository replay. It does not establish anatomical or physical clearance.

## Geometry and scope

The guard verifies that the supplied envelope matches the target scalp vertices and exact scalp hash. It rejects incompatible geometry, stale hashes, negative/invalid dimensions and a claim that the construction envelope was observed. The source scalp may be inferred or synthetic; neither becomes measured anatomy through this check.

For every segment, endpoints are transformed to normalized ellipsoid coordinates. The minimum radius along the segment is found analytically from the clamped minimum of its quadratic squared length. This catches penetration between vertices, which the earlier sampled-point diagnostic could miss.

The recorded experiment permits a 0.5 mm radial-depth upper bound to accommodate roots on planar mesh triangles inside the analytic surface. The normalized threshold is `1 - inset / largestRadius`. If every segment stays above that threshold, radial penetration anywhere along the centerline is bounded by the declared inset. This is conservative and is not an exact signed distance to the triangulated scalp.

The guard uses the full ellipsoid, including volume outside the open cap. It does not include hair radius, face/ear geometry or self-collisions. The envelope itself remains an unreviewed shape estimate.

## Correction and persistence

During import, violating segment endpoints are lifted radially with at most 32 local passes. Roots never move. Any point requiring more than the request's correction limit rejects the entire import. The experiment uses a 2 mm limit; the API caps it at 5 mm. Guide IDs/order and all unaffected geometry remain intact. Length constraints are checked again after correction; they are not widened to accommodate it.

The optional `envelopeGuard` is retained in `HairDesignBrief`, so its parameters contribute to the brief hash. The importer requires the request's guard to match that brief. `HaircutValidator` performs a check-only pass for guarded designs. Consequently, an edit or a saved artifact cannot reintroduce penetration or replace the guard without failing geometry or source-hash validation. Validation never silently repairs an edited revision.

`tools/propose_model_mapping.py ... --guard` emits a matching guarded input and import request. Without the flag, the earlier unguarded research workflow remains available and explicitly unvalidated.

## Actual model-output result

The current experiment uses the same 763 generated guides and inferred participant scalp as the [mapping experiment](model-guide-import.md):

- Three guides required correction; 20 points changed. Maximum displacement was **1.266 mm**, below the 2 mm limit.
- All root positions remained exact. Independent calculations confirmed the continuous-segment threshold and the **0.5 mm** radial-penetration upper bound.
- The **30 mm fringe** edit passed and changed 146 guides.
- A **20% crown-volume reduction** failed the guard. It created no saved revision and preserved the original and fringe revision.
- A **20% crown-volume increase** passed and changed 85 guides. The guarded history now contains three revisions with the same bound guard.
- The separately supplied partial face still passed its 1 mm capsule-clearance check. Both ears remain missing; this does not complete physical validation.

The current artifacts are in `outputs/personal-model-guarded-v2/`. The earlier `personal-model-mapping` and `personal-model-guarded` directories are retained as prior experiments, not silently rewritten.

## Verification

All **88 core tests** pass. New cases prove between-vertex detection despite exterior endpoints, unchanged exterior curves, fixed roots, bounded correction, rejection of a different/stale envelope, and rejection of an otherwise geometrically valid volume edit that violates the guard. Altering the guard in the brief invalidates the old haircut hash binding. Independent Python checks recompute segment minima, supplement them with samples and verify point deltas and both accepted edits.

The unsigned iPhone SDK build passed for this guard implementation. A subsequent [native model review](native-model-review.md) now verifies physical rendering and simulator edit persistence. Sustained performance, accepted head fitting and personalized styling remain unverified. Aggregate guard evidence is in [the verification record](evidence/ellipsoid-guide-guard-2026-09-10.json).
