# Landmark-defined anatomical frame

`AnatomicalFrame.canonicalize` moves a partial observed surface from its reference camera into the coordinate convention required by hair assets. This is part of M1.3, not head completion or automatic landmark detection.

Select four distinct mesh vertices on the native, unmirrored observed surface: anatomical left/right eye landmarks, a superior landmark, and an anterior landmark such as the visible nose. The first two estimate eye centers; the superior point estimates an upward direction. The operator/model supplying these semantic labels remains responsible for their anatomical interpretation.

The origin is the eye-landmark midpoint. +X points from anatomical right to left. +Y is the superior-point direction after removing its component along X. +Z is X cross Y. The anterior point must lie in front of that plane; it checks orientation and does not participate in fitting the frame. Swapped eye labels fail this check for otherwise consistent input. A bad combination of several landmark labels can still be geometrically consistent, so this is not automatic anatomical verification.

Because the superior point lies on the face, its posterior/anterior displacement can tilt the estimated frame. It is a landmark-defined convention, not an independently measured gravity/body axis. Better landmark estimation, anatomical fitting and repeated physical evaluation remain necessary.

## CLI

```sh
tools/dev.sh swift run capture-inspect surface-hash outputs/surface.json
# Copy that digest into selection.json:
tools/dev.sh swift run capture-inspect canonical-surface \
  outputs/surface.json outputs/selection.json outputs/canonical-surface.json
python3 tools/check_anatomical.py
```

Selection schema:

```json
{
  "schemaVersion": 1,
  "surfaceSHA256": "COPY_SURFACE_HASH_HERE",
  "anatomicalLeftEyeVertex": 0,
  "anatomicalRightEyeVertex": 1,
  "superiorVertex": 2,
  "anteriorVertex": 3,
  "method": "Describe the landmark selection method and version"
}
```

The example indices illustrate the schema; select actual landmarks for each surface. The digest uses this Swift schema's canonical JSON encoding, not arbitrary incoming JSON whitespace. `surface-hash` computes identity only; `canonical-surface` performs the structural and landmark checks. Hashes do not authenticate a subject, capture or anatomical label.

## Output and limits

Output includes both rigid transforms, the exact source-surface hash and selections, transformed vertices/normals, unchanged triangle indices and depth-pixel observations, and original frame evidence. Units remain meters. No scale fitting, deformation or hidden geometry is added. Original frame transforms remain reference-camera transforms; compose `canonicalFromReference` with `referenceFromCamera` to obtain canonical camera poses. Retain the source surface/capture bundles for replay.

Synthetic frame evidence cannot be relabeled as sensor evidence. Mesh indices, normal validity, source-frame references and transform validity are checked. Provisional selection limits require eye separation 20–120 mm, superior orthogonal separation 10–250 mm, and anterior separation 3–100 mm. These are engineering sanity bounds, not measured accuracy or a promise of support for all anatomy.

The output explicitly remains a partial observed surface with no inferred scalp. It cannot be used as a completed `ScalpProfile` merely by renaming the object. Hair masking, scalp completion, coverage and quality assessment remain separate requirements.

Tests recover an independently specified rotation/translation, preserve scale and observation references, rotate normals, invert transformed positions, and reject swapped labels, stale surface hashes, unstable superior direction and malformed geometry. The CLI checks both transform directions numerically on synthetic landmarks. No physical anatomical accuracy has been measured.
