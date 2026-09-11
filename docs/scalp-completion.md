# Editable inferred scalp candidate

`ScalpCompletion` adds an explicit starting surface for hidden scalp geometry. It recomputes the anatomical frame from the original observed surface and landmark selection, retains that face separately with its pixel observations and topology, and emits a `ScalpProfile` that existing hair-root bindings can reference. No observed face triangles are relabelled as scalp.

The starting shape is an ellipsoid cap. Its heuristic dimensions scale with estimated eye-landmark separation; its anterior boundary depth uses the selected superior facial point. These constants are construction defaults, not a learned population model or validated anatomical proportions. Width, height, depth, center and front/side/back boundary heights can be changed in the request. The native **Capture lab → Review estimated scalp** screen supports those dimensions, boundary corrections and position on all three axes. Position controls use 1 mm steps; vertical translation also shifts all boundary heights so the cap moves without deforming. Positive directions are explicitly labeled as anatomical left, up and forward. Saving retains the existing revision-history and validation flow; no movement is automatically selected or treated as an accepted fit.

All 3,008 cap triangles are marked inferred for sensor input, or synthetic for fixture input. An edited request and scalp revision receive new hashes; the observed face remains identical. Parameters cannot claim an observed origin. The cap has one open boundary; it does not close the face, ears, neck or forehead and does not represent a measured hairline. `acceptedForHeadFitting` remains false and shape/hairline review remains required.

## Replay

After building `capture-inspect`, use:

```sh
capture-inspect scalp-suggest SURFACE.json SELECTION.json ENVELOPE.json
capture-inspect scalp-complete SURFACE.json REQUEST.json RESULT.json
```

`tools/propose_scalp.py SURFACE.json LANDMARKS.json SUBJECT_SESSION_ID NEW_OUTPUT_DIR` prepares an inferred anatomical selection and request from a matching single-frame face patch and its depth-backed Vision landmarks. It requires NumPy. It selects pupil/nose vertices and a central superior point, then checks orientation through the existing canonicalization gate. This selection still needs anatomical review. Subject identity is supplied explicitly; the tool does not infer it from the face.

`tools/render_scalp_preview.swift RESULT.json OUTPUT.png` renders four views with the observed face in gray and inferred scalp in amber.

## Current evidence and limits

The recorded front-face patch produced a 1,537-vertex inferred cap. The four-view render was inspected: the cap and face are separate, and gaps remain at the forehead/temples. The cropped observed patch contains little geometry above the eyebrows. No fitting-quality, hairline, physical-accuracy or complete-head claim follows from this output. No hair/bun surface was used to fit skull shape, and the installed phone model was not replaced.

Tests cover ellipsoid membership, outward triangle winding, a single open boundary and Euler characteristic, unchanged observed evidence after parameter edits, source/revision hashing, and rejection of invalid envelopes and false measurement claims. All 80 core tests and an unsigned iPhone build pass. Private outputs are in `outputs/scalp-candidate/`; aggregate evidence is in [the verification record](evidence/scalp-completion-verification-2026-09-10.json).

Remaining work includes recovering visible forehead/temple coverage, fitting/reviewing the boundary and head shape, preserving regional uncertainty through corrections, adding native correction controls, and validating the completed head and hairline before using it for personalized generation.

The newer translation controls pass a whole-cap geometry test: every inferred vertex moves by the requested offset, topology stays identical, and the observed face hash is unchanged. All 128 core tests and the iPhone SDK build pass. The simulator adjustment/save/relaunch test also verifies the changed vertical position persists (`Test-PersonalizedHair-2026.09.11_03-00-50-+0200.xcresult`). This is control/persistence verification, not a reviewed correction of the participant's anatomy. The installed phone capture build was not replaced.

## Native review and revision persistence

The review screen imports a `ScalpReviewDocument` containing one observed source and up to 20 consecutive parameter revisions. All revisions are checked against the same subject, scalp identity and anatomical selection before display. Validation runs away from the UI thread. Saving an adjustment appends a revision; it does not replace the original face or earlier requests. The preview updates only after a successful save, and unsaved controls are labelled explicitly.

The screen supports orbit/zoom/reset, hiding the inferred scalp, discarding unsaved adjustments, export, and confirmed deletion of the review document and its revisions. Stored review data has file protection and is excluded from backup. Capture bundles and the separate textured head preview remain separate. `tools/propose_scalp.py` now emits `scalp-review.json` for import alongside its result and construction request.

The staged simulator test changed width by 2 mm, saved revision 2, relaunched, and verified the revision persisted. Direct inspection of the saved document confirmed the original source and revision 1 were unchanged. The initial test run failed on the UI automation's stepper selector; the corrected selector passed the complete flow. Core tests now total 81 passing, including history serialization and rejection of changed subjects, nonconsecutive revisions and false measurement origins.

The signed build and initial review package were installed on the connected iPhone. A read-only physical UI test loaded and rotated the preview successfully; its screenshot was inspected. A device readback matched the initial package contents and retained revision 1. The width-change test affected only the simulator. See [native verification](evidence/scalp-native-review-verification-2026-09-10.json).
