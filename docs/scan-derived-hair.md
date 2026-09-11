# Scan-derived hair appearance

Status: image-space hair-mask and recorded-color extraction implemented as a
local research command; natural-hair validation, 3D fitting and viewer integration
remain open.

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

## Native review of image evidence

In a saved capture's review screen, select the source frame and choose “Import
hair analysis for this frame” to import the local command's `report.json`.
The app checks the exact manifest hash, capture/frame identity, image hash and
payload, dimensions, preparation provenance and review-only claims. It displays
recorded color and texture-support counts; it does not import mask rasters or
claim that the segmentation has been visually verified inside the app.

The report is saved under the capture's `analysis/hair` folder with iOS complete
file protection and revalidated when the frame is reopened. Capture deletion
removes that folder too. The existing capture ZIP exports raw evidence only;
derived reports are not included. A revised manifest invalidates the report
binding instead of silently carrying it forward. Import does not alter the
personal hair profile, generate guides or change either preview's haircut.

Core tests cover persistence, unchanged capture integrity, wrong-frame rejection,
invalid color/measurement claims, preparation provenance and stale manifests.
The iOS build passes. A simulator UI test imports the report through Files,
verifies its summary, relaunches the app to check persistence and switches frames
to confirm that evidence clears. Its screenshot was visually reviewed. The test
also exposed a missing `UIFileSharingEnabled` key in the built app; the explicit
Info.plist now preserves Files access, the configured version and camera purpose.
Physical-device interaction remains unverified for this change.

The same validator is available as `capture-inspect hair-image-review
CAPTURE_BUNDLE FRAME_ID REPORT.json`. It successfully checked the existing
local tied-frame report (459,683 inferred hair pixels); this verifies contract
compatibility and source binding, not physical analysis accuracy.

### Recorded-color revision

The canonical editor supports `match_recorded_color` for one region. Its edit
record retains the source capture/frame, report and image hashes, subject session
and recorded RGB. The report must pass native image validation, and its subject
must match the design input. RGB is treated as sRGB and converted to linear RGB
for the material: this is an explicit preview approximation with no illuminant
or camera-profile correction, not a measurement of intrinsic hair color.

The editor clones shared materials as needed so other regions keep their
appearance, preserves every guide point/root and retains the parent revision.
Repository replay reproduces the change, and both tube and ribbon compilers
receive the same materials. A supplied clearance report is retained; a color
change neither resolves existing intersections nor changes their geometry.

```sh
tools/dev.sh swift run capture-inspect hair-image-color \
  INPUT.json HAIRCUT.json CAPTURE_BUNDLE FRAME_ID REPORT.json fringe OUTPUT.json
```

The actual tied-frame experiment changes material assignments for 146 fringe
guides while preserving geometry for all 763 guides and leaving every other
region unchanged. The diagnostic revision remains private and does not replace
the saved studio candidate. All 159 core tests and the iOS build pass. Native
source-selection controls for this edit and visual evaluation remain unfinished;
color alone does not establish personalized haircut design or realism.

## Local image-evidence command

With the existing pinned face-parsing model and local research environment:

```sh
.research/metal-env/bin/python tools/segment_face_capture.py \
  CAPTURE_BUNDLE FRAME_INDEX PRIVATE_OUTPUT_DIRECTORY \
  --target hair --capture-condition untied --rotation clockwise90 --compare-cpu
```

Choose rotation from the recorded image; `clockwise90` is an example, not a
universal sensor rule. New app captures can store `declaredHairCondition` from
the “Hair in this recording” selection: tied, untied or unknown. The selection
defaults to unknown and is disabled during preparation/recording. It records a
participant declaration, not a camera classification; dry preparation remains
guidance, not a measured property. Legacy manifests without the field stay
unknown, including those labeled `natural_hair`.

Omit `--capture-condition` to use the saved declaration. For older captures, an
explicit flag records an operator assertion; use `tied` for diagnostic processing
of pinned hair. A flag contradicting a saved tied/untied declaration is rejected.
No output is automatically accepted as a natural-hair baseline, even when
`untied` is declared.

The command verifies the capture and pinned local weights, preserves full native
RGB resolution, and writes class labels, hair posterior, binary hair mask, an
eroded interior mask, a diagnostic plot and a provenance report. Recorded color
percentiles use interior pixels to reduce boundary mixing; fewer than 100
interior pixels yields unknown color. A two-pixel erosion does not guarantee
removal of segmentation errors. The report keeps lighting-dependent recorded
color distinct from calibrated intrinsic color and leaves roots, density, scalp
shape and metric volume unknown. This RGB-only branch does not require depth
synchronization and produces no fused surface.

An existing tied-hair rear frame was processed locally on CPU and MPS: class
labels agreed on all pixels and hair posteriors differed by at most 2.1e-6.
The diagnostic mask was visually inspected; this checks plumbing and basic
plausibility, not segmentation accuracy or untied-hair quality. Four synthetic
tests cover boundary-color exclusion, native coordinate bounds, low-confidence
and nonhair rejection, image-edge erosion and invalid arrays:

```sh
.research/metal-env/bin/python -m unittest discover -s tools \
  -p test_hair_image_observations.py
```

The reused model remains research-only under the recorded model-card terms;
commercial use is not cleared by this implementation.

### Apparent texture orientation

Hair extraction also writes `texture-axis.f32`: an H × W × 3 interleaved
little-endian float32 field in native image coordinates. Each supported pixel
contains `(cos(2θ), sin(2θ), coherence)` for an undirected local texture axis.
The doubled angle deliberately prevents a root-to-tip direction claim.
Unsupported pixels are `(0, 0, 0)`. The file hash and processing parameters are
included in the report, with a separate native-image diagnostic overlay.

The current estimator uses a 15 × 15 box-averaged image gradient tensor and its
smaller-eigenvalue axis. It requires the window and derivative halo to lie within
the inferred hair mask, with sufficient gradient energy and anisotropy. These
thresholds are experimental. Coherence is a property of image texture, not a
calibrated probability that the axis matches a strand. Highlights, clump edges,
motion blur and segmentation errors can mislead it. It performs no 3D lifting or
root inference, and does not automatically update `HairCharacteristics`.

The tied-frame diagnostic had 95,324 supported pixels out of 459,683 inferred
hair pixels (about 21%). Visual inspection showed sparse support and variation
around highlights; no orientation-accuracy or styling-quality gate is claimed.
Seven synthetic tests now cover image observations and orientation, including
known horizontal/vertical/diagonal texture tangents, contrast reversal,
quarter-turn coordinate behavior, absent texture and boundary exclusions.

### Projected-guide comparison

`tools/compare_hair_image.py` compares a saved guide asset against one frame's
hair mask and texture axes. It requires an explicit rigid transform into the
frame's optical camera coordinates (x right, y down, z forward, meters). Only
aligned rear-camera or synthetic pinhole images are supported; unrectified
front-camera images are rejected until this path implements lens correction.

```sh
.research/metal-env/bin/python tools/compare_hair_image.py \
  CAPTURE_BUNDLE IMAGE_EVIDENCE_DIRECTORY HAIRCUT_JSON ALIGNMENT_JSON OUTPUT_JSON
```

The alignment JSON contains `cameraFromHairRowMajor` (16 numbers),
`haircutFileSHA256` and `evidenceReportSHA256`. These hashes bind the transform
to the exact files, but do not validate anatomical registration. The tool checks
the manifest/frame identity, raster hashes, dimensions, rigid transform and
texture support before comparison. The output records all three input hashes.

Segments are sampled in image space at a maximum spacing of two pixels. The
report counts out-of-frame samples, samples inside the hair mask, and samples
with orientation evidence. It reports median and p95 axial errors from 0–90°.
Camera-crossing segments and degenerate projections are excluded and counted.
Absent evidence gives null errors rather than a perfect score. Segment
subdivision affects sample weighting; sparse guides cannot provide a complete
silhouette, density or reconstruction score. By default, occlusion is not tested.

Add `--use-capture-depth` to test samples against aligned capture depth. This
verifies the depth and confidence payload hashes and requires image/depth
timestamps within 10 ms. Only confidence-level 2 depth in the 0.05–5 m range
supports a visibility decision; invalid or lower-confidence samples remain
unknown and do not contribute orientation scores. A guide sample farther than
the observed surface plus `--occlusion-margin` (default 0.01 m, experimental)
is counted as occluded. Projected segments use reciprocal interpolation of
camera Z. The margin is not a claim about sensor precision.

The raw in-image mask agreement remains available separately from agreement on
depth-supported visible samples. Neither metric includes silhouette coverage or
validates registration. Sensor artifacts, transparent hair and coarse depth
boundaries still require physical evaluation. This image-fitting diagnostic is
separate from occlusion rendering in the live camera viewer.

Six synthetic tests cover scaled intrinsics, undirected comparison, orthogonal
error, missing support, camera crossings, invalid transforms/calibration and an
end-to-end file-bound CLI comparison with stale-input rejection. They also cover
hidden/unknown-depth exclusion, perspective interpolation, timestamp rejection,
and tampered depth payloads. Physical registration and occlusion validation remain necessary before using this diagnostic
as a fitting objective. It never automatically accepts a haircut or registration.

```sh
.research/metal-env/bin/python -m unittest discover -s tools \
  -p test_compare_hair_image.py
```
