# Live inspection framing

The pre-camera inspection view previously placed a perspective camera at a fixed
multiple of the largest world-axis extent. The participant-derived guide asset
occupied only a small part of the 320-point view, and the bounds omitted an
observed face when one was displayed.

`InspectionCameraFrame` projects the rendered hair, scalp and available observed
face into a fixed three-quarter camera basis. Its projected bounds determine the
target and vertical orthographic half-height. Both viewport width and height are
used, with 15% padding, so a tall/narrow view also accommodates the asset's width.
Near/far planes account for the projected depth. This affects the inspection
camera only; canonical geometry and the AR tracking camera are unchanged.

`HairInspectionView` applies this framing when a package loads or its viewport
size changes. Ordinary layout callbacks with the same size leave the user's orbit
and zoom alone. A viewport resize intentionally returns to the default framing.
The default fit covers the initial orientation; arbitrary subsequent orbit or
zoom can still move geometry outside the view.

Two new core tests check every corner of an asymmetric box in wide and tall
viewports, translation invariance, degenerate geometry and invalid viewports.
All 167 core tests and the unsigned iOS build pass. Physical camera alignment,
occlusion and sustained rendering performance are separate, unresolved gates.

The actual candidate's simulator edit/reopen/undo/redo/live-inspection UI test
passes with the new framing. Its screenshot was inspected: the initial view fills
the inspection area with margin, and the exact revision hash is unchanged. Evidence
is private under `outputs/inspection-framing-ui-private/`. The first UI rerun
lacked the prepared import file because the preceding test consumed it; restoring
that private fixture allowed the complete rerun. No phone camera or installation
was involved.
