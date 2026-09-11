# Scan-derived hair appearance

Status: design extension; extraction, fitting and viewer integration remain open.

The untied-hair capture supplies a personal appearance baseline for both the
current-hair reconstruction and the proposed haircut. Keep these as separate
assets: a new haircut may intentionally have a different silhouette and length,
while retaining supported texture, color variation and growth constraints.

## Evidence and processing

1. Confirm the capture condition from reviewed images or participant input.
   Legacy `rear_head` and `front_face` records do not establish whether hair was
   tied. Never silently label a bun as natural volume or scalp geometry.
2. Select sharp views covering front, sides, back and crown. Preserve source
   capture/frame hashes, calibration, timestamps, view transforms and exclusions.
3. Infer hair masks in RGB; review boundaries around ears, skin, clips and
   background. Model posterior scores are not calibrated accuracy.
4. Register usable views to the personal head through visible rigid skin regions.
   Reject uncertain alignment and moving hair from metric fusion. Preserve
   image-space observations even when 3D registration is unavailable.
5. Estimate the visible hair envelope from silhouettes and valid aligned depth.
   Save observed support separately from inferred completion. This is an outer
   envelope, not a measurement of scalp position, strand count or follicles.
6. Extract visible texture, clump scale, apparent strand orientation and color
   variation. Image orientation initially has a 180-degree ambiguity; it is not
   root-to-tip direction. Illumination-dependent RGB must not be presented as
   calibrated intrinsic hair color. Hidden roots and growth direction stay
   unknown unless supported by additional evidence or explicit correction.
7. Fit editable guides and appearance parameters against the supported views.
   Use a held-out view to check silhouette and appearance rather than accepting
   a fit solely because it reproduces its training views.

The existing `HairCharacteristics` contract covers regional texture, flow and
hairline. Add a versioned appearance artifact for masks, view registration,
supported envelope, color/lighting estimates and per-region confidence. Bind
that artifact to the input profile and generated revision by content hash.
Do not overload `estimatedRootGrowth` with image-space orientation.

## Generation and previews

The current-hair asset targets the observed shape. The proposed haircut uses the
same personal observations plus the design brief, with explicit overrides for
intentional texture, color, length or part changes. Unknown current lengths must
not become a claim that a proposed cut is achievable immediately.

Both the orbit viewer and live viewer compile the same saved haircut and
appearance revision. Tubes, ribbons or textured cards are rendering derivatives;
switching them must not change personal evidence or edit history. A splat or
image reconstruction may serve as an appearance reference, but does not by
itself supply editable haircut strands or hidden-root measurements.

## Verification before acceptance

- Reject stale profile, calibration and appearance hashes; preserve unknowns.
- Review masks and registration on the actual untied capture before fitting.
- Compare current-hair silhouettes and visible texture against held-out views;
  report regional errors and missing coverage, with no invented completion score.
- Compare generation with and without personal hair observations while holding
  head geometry, brief and seed fixed. Record which design properties change.
- Verify an edit survives save/reload and reaches both viewers with matching
  haircut and appearance hashes.
- Evaluate visual quality and device performance separately. Lower mesh counts
  do not establish realism, frame rate or physical haircut feasibility.

Capture images, masks, derived personal models and review renders remain private.
