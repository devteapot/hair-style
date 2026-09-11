# Native ARKit preview lab

Open **Capture lab → Open live preview lab**. Import a live package and inspect its scalp and hair in 3D. On a compatible iPhone, pin existing hair back, start the camera, hold a neutral expression and choose **Calibrate alignment**. Camera permission is requested only after Start. Unsupported devices can import and inspect, but show an explanation without camera controls.

The JSON package contains:

| Field | Meaning |
|---|---|
| `schemaVersion` | `1` |
| `input` | Complete `HairDesignInput` for this scalp/profile/brief |
| `haircut` | Validated-source canonical `HaircutRevision` |
| `fitLandmarks` | 4–200 distinct landmark selections |
| `validationLandmarks` | 3–200 different held-out selections |

Each selection has `id`, `canonicalPoint` (`x`, `y`, `z` in meters) and `faceVertexIndex`. Indices must be deliberately matched to corresponding points on the current AR face mesh; no example indices are supplied because arbitrary selections would create false alignment. Landmark selection/export tooling and automatic reliable correspondence remain unfinished.

Import limits JSON to 100 MB and runs decoding, haircut validation and tube compilation outside the main actor. Rendering uses scale 1 material radii and the same canonical mesh compiler as inspection. UI-side SceneKit resource creation remains synchronous. Loading a new package stops the session and hides existing hair. No package is uploaded or saved by this lab.

The package schema now lives in HairCore. Preparation rejects duplicated target indices, nonfinite/source points outside bounds, degenerate landmark layouts, stale source bindings and invalid haircut geometry before camera use. This validates the selected data, not semantic correspondence with AR vertices.

Inspection shares the imported hair geometry with the live root and frames the camera from scalp/hair bounds. It displays exact revision/hash identity. The scalp surface is shown as supplied; the viewer does not claim a completed head or add inferred anatomy. Import resets the root transform so a previous live pose cannot shift the next asset's inspection view.

The simulator includes **Load synthetic preview test**, which writes a temporary labeled fixture package and loads it through the ordinary file path. Its thick diagnostic guides and arbitrary fixture landmark indices are for import/inspection tests, not physical calibration. The control is not compiled into physical-device builds. The temporary package is removed after loading; the imported geometry remains in memory for the screen's lifetime.

Calibration samples selected vertices from a currently tracked face, fits the existing held-out-validated rigid transform, and binds it to the current session/anchor and scalp hash. Synthetic scalp provenance remains synthetic even when targets are sampled from a live camera. The source-to-target registration is hashed in memory; full calibration evidence export is not yet provided.

A display link reads new AR frames and applies the tracking gate. It timestamps new frame arrivals using the display-link monotonic clock, avoiding an assumed equivalence between AR frame timestamps and that clock. Repeated unchanged AR frames do not refresh the watchdog. A fresh frame without a face explicitly reports tracking loss. AR face transforms are explicitly converted from SIMD column-major layout to the core row-major convention and back for the root node. Expressions do not deform hair geometry.

The live scene now includes an `ARSCNFaceGeometry` with filled mesh, updated from each face sample. It writes depth without writing color and renders before the hair batches. It follows the face anchor directly, while hair follows the calibrated canonical transform. Both nodes hide when tracking is lost, calibration fails, or the session stops. This implements face-surface occlusion only; it does not reconstruct ears, hair or hands. Rendering quality and depth alignment still need a real-person test.

Stop, navigation away, app backgrounding, AR interruption or AR failure pauses the session and hides the overlay. Interrupted sessions require an explicit restart and fresh calibration. Permission responses and background import results use cancellation tickets, so stale completions do not start a camera or replace active content.

## Limits and verification

This is an imported-asset engineering path, not the complete capture-to-generation experience. It does not authenticate that the scanned subject is the person in front of the camera. Face occlusion is implemented but unverified on a person. Hairline/ear/hand occlusion, fade animation, photorealistic shading, existing-hair removal, stable physical alignment, sustained FPS and thermal evaluation remain unfinished. Geometry appears only after numerical calibration, but numerical agreement alone does not establish semantic landmark correctness.

The iPhone target builds. Core tests check package round trips, exact mesh revision identity and invalid-selection rejection. The simulator UI test checks the unsupported-device explanation, absence of Start camera controls, and loading/inspection of the synthetic package through the file path. It does not exercise the system document picker, sensor, calibration or live rendering. Real-device import, permission/lifecycle handling and alignment still need runtime verification.

## Multiple-face gate (2026-09-11)

The native session now requests `ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces`, instead of limiting detection to one tracked anchor. Calibration requires exactly one reported face anchor and normal tracking. Each display sample carries the complete reported face-anchor count, including untracked anchors. More than one anchor immediately latches recalibration-required and hides both hair and the face occluder. Returning to one anchor cannot restore the old overlay; the user must explicitly calibrate again. Zero anchors reports loss even if a caller incorrectly marks its sample tracked. Negative counts fail closed into recalibration-required.

This is not identity recognition or a guarantee that every nearby person is detected. Devices may support only one tracked face, occluded faces may not be reported, and anchor continuity is not proof of personal identity. The supported-use instruction remains to stay alone in frame. A physical two-person entry/exit case and performance with the increased tracking capacity are still required before A10 or M3 can pass.

Validation: 114 core tests pass. The new sequence starts with a visible calibrated anchor, adds a second face while retaining that same anchor, verifies immediate hidden presentation, and verifies that subsequent one-face frames do not restore it. It also checks explicit zero-face loss. The unsigned iPhone SDK build succeeds. No camera was started and no build was installed on the participant's phone for this change.
