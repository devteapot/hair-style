# Saved model revision to live alignment

Date: 2026-09-10. Experimental manual alignment; M3's physical parity gate remains open.

## Native path

In **Capture lab → Review generated hair**, select a saved revision and choose **Align saved revision for live preview**. The link is disabled during an unsaved edit, original comparison or an operation in progress. The destination holds that exact selected snapshot; it does not regenerate, refit or edit the haircut.

1. Select seven named features on the recorded face. Selection is snapped to a vertex of the visible hit triangle. The inferred scalp is not present in the picker. A missing feature must not be guessed.
2. Explicitly start the alignment camera, keep a neutral expression and choose **Use neutral face**. ARKit's face-local vertices and triangle connectivity are copied into a temporary in-memory reference. The camera then pauses. No RGB frame, video, depth capture bundle or Face ID template is saved by this flow.
3. Select the same seven features on the frozen tracker mesh. The 3D pickers are unmirrored; labels use the person's anatomical left/right. Undo is available for each selection. Retaking the reference clears its selections.
4. Check alignment. Nose tip, chin and both outer eye corners fit a rigid transform. Both mouth corners and the nose bridge are held out. Existing registration gates reject inconsistent points; scale and facial deformation cannot absorb a mismatch.
5. Open the selected revision in the existing live screen. Starting that camera and calibrating remain explicit actions. Calibration recomputes its fit against the current neutral face and checks tracker vertex count and triangle topology before displaying hair.

The reference and point selections are temporary. Leaving setup requires selecting them again. This is an engineering alignment workflow, not the final autonomous consumer experience or an identity check.

## Revision and rendering integrity

`LiveReviewCorrespondences` requires the observed canonical surface's hash in the haircut's scalp provenance. It checks distinct, in-range, mesh-connected points with observation evidence. It prepares a `LivePreviewPackage` containing the unchanged saved haircut and input, four fitting landmarks, three validation landmarks and the frozen tracker topology identity.

The package explicitly carries the model review's three-sided, eight-times-radius diagnostic mesh settings. The live loader uses these settings, retaining its compiler's vertex budget and the haircut validator's envelope/length/binding checks. Legacy packages without settings still use six sides and radius scale one.

The in-memory live handoff also shows the same observed face and inferred scalp in its inspection pane. Live face occlusion still uses ARKit geometry; the recorded face is not rendered over the camera. Hair remains rigid under face expressions, using the existing tracking gate. Green fringe and brown guides preserve the model-review diagnostic colors. Enlarged sparse guides are not final hair density or a production hairstyle material.

## Verification scope

- 94 core tests pass, including an edited-revision round trip with identical compiled-mesh hashes between review and live.
- New controlled tests recover an independently specified rigid transform, reject changed held-out points and scale, and reject wrong-face provenance, duplicate/missing/out-of-range selections, malformed tracker geometry and topology changes.
- Simulator and signed iPhone builds compile the manual picker and handoff. The final simulator run passed two tests; the physical iPhone 15 Pro passed the manual-picker test. Its selection JSON matches the pre-test saved revision exactly. No camera was started by these tests.
- Native UI results and exact source hashes are recorded in [the evidence record](evidence/model-live-alignment-2026-09-10.json). Tests navigate the actual imported 763-guide review and select/undo one visible surface vertex without opening a camera. This is selection mechanics, not anatomical correspondence.

The first UI test attempted to tap the center of the recorded face, which is a hole in this partial scan. Inspection confirmed that no point was selected. The test was corrected to tap a visible cheek patch; no geometry was filled or acceptance threshold relaxed. A subsequent run exposed that scene rotation consumed scrolling gestures needed to reach Undo. Undo and Continue/Check now stay in a fixed bottom bar; the final two-test simulator run passed, including selection and undo with those controls.

Physical neutral-face selection, complete manual correspondence, actual on-camera alignment, tracker stability, occlusion, sustained frame rate and consumer usability remain unverified. The current recorded face is incomplete and rough; this workflow does not make it an accepted head reconstruction. Model generation remains generic text conditioning followed by fitting, not demonstrated personal style generation.
