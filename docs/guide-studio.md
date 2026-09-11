# Native guide studio

Open **Capture lab → Open synthetic guide studio** in the iOS app. Create a fixture to inspect two guide curves attached to a flat scalp. This is a diagnostic integration of the canonical contract and local history, not a generated hairstyle, reconstructed head, mobile hair compiler, or live camera filter.

The separate **Review generated hair** screen now reuses the editing controls with verified model packages, a captured face and inferred scalp. It stores its data independently; see [native model review](native-model-review.md). The descriptions below refer to the original synthetic mode.

## Interaction

- Orbit and pinch the SceneKit viewport; reset returns to the fixture's three-quarter view.
- Choose a fringe length in millimeters and preview the shortened curve. The root and original curve prefix are preserved.
- Preview a 20% reduction in crown volume. This scales displacement tangent to the scalp while preserving the normal component and root binding.
- Save a preview as a new immutable revision, discard it, compare with the original, or undo/redo saved selections.
- Relaunch to reopen the selected saved revision. Delete the fixture to remove its original, edits and selection history.

The displayed revision status distinguishes saved results, unsaved previews and the original comparison. Curve lengths reflect the displayed geometry. The small hash identifies the saved selection, including while the original is temporarily shown for comparison; it is not an identifier for an unsaved preview.

The fringe is green and the crown amber. Tubes and root dots are intentionally enlarged for inspection; these colors/radii do not replace canonical hair materials or strand radii. The fixture remains visibly a plane. The viewer has a 2,000-segment limit and explicitly reports oversized assets. There is no inference of strand density and no physical styling simulation.

## State and storage

The main-actor view model keeps presentation state. Detached work validates preview edits against an explicit source hash; a request counter discards superseded results. Camera position remains intact across curve edits and original comparison. Geometry rebuilding uses the displayed haircut hash as its identity.

`HairLabWorker` serializes selection changes on an actor. Saving checks that the selected base is still current, persists the immutable artifact, loads/verifies the next snapshot, and then atomically writes the selection. Undo/redo move among exact saved hashes; they do not regenerate curves. An error preserves the previous valid selection. A process stopping between artifact and selection writes can leave an unselected valid branch, but does not publish a pointer to an unwritten artifact.

Data is local under Application Support/HairLab. The selection and artifacts use iOS complete file protection and backup exclusion. A deletion action removes this lab directory. A failed restore offers removal of unreadable lab data; it does not silently replace the original. These behaviors are limited to this synthetic lab, not the unfinished full product/session/cloud lifecycle.

## Remaining product work

The studio is not connected to reconstructed personal heads or a model generator. The full hair viewer still needs identity-preserving head rendering, production strand/card compilation, material/lighting evaluation, supported-asset budgets and physical-device performance measurements. Front-camera tracking, registration to the canonical head, occlusion and viewer/live parity remain unfinished. No 30 FPS, 150 ms edit-latency, physical feasibility or personalized-design quality claim follows from this lab.
