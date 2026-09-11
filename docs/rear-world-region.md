# Rear capture spatial filtering and multi-view preview

The rear pass now supports a capture-wide spatial crop at native depth resolution. A supplied world-space ellipsoid is projected through each recorded camera pose. Normal tracking, synchronized aligned depth, valid sensor ranges and confidence are required. This removes samples outside the selected region without inferring anatomy or modifying depth values.

Every processed pixel is counted as included, invalid depth, low confidence or outside the region. Tracking failures skip whole frames with an explicit reason. Masks preserve their selection provenance and source frame hashes; source bundle payloads are integrity-checked. Empty crops remain empty. The region is fixed in one capture's world coordinates and cannot compensate for subject movement.

This is **spatial filtering only**. Hair, clips, bun, neck, hands or background inside the volume remain. Mask output does not represent skin or skull segmentation and does not authorize fusion. Estimated region dimensions must not be presented as measurements of the person.

## Replay commands

After `tools/dev.sh swift build`, supply a request with `center`, `radii` (x/y/z in meters), `selectionProvenance`, `selectionMethod` and `minimumConfidence`; optionally set `minimumWorldY` to exclude depth below a supplied world-Y plane:

```sh
.build/debug/capture-inspect world-region-masks CAPTURE_BUNDLE REQUEST.json REPORT.json
python3 tools/reconstruct_rear_region.py CAPTURE_BUNDLE REQUEST.json NEW_OUTPUT_DIRECTORY
tools/dev.sh swift tools/render_world_preview.swift NEW_OUTPUT_DIRECTORY/world-preview.json OUTPUT.png
```

The replay script builds twelve separate depth patches by default, checks their frame hashes against the masks, and places them in the capture world using camera poses. It preserves per-frame geometry and hashes. It does not average, register or merge observations. Its `world-preview.json` uses a distinct diagnostic format with `acceptedForFusion: false`; it is not an accepted head/scalp asset. Colors in the four-view renderer identify contributing frames.

## Assisted physical capture, 2026-09-10

A provisional region was estimated from rear frame 56's face patch: its median position shifted 90 mm deeper into the camera view, with world-axis radii 170/190/170 mm. These are engineering crop choices, not measured anatomy.

- 86 frames inspected; 3 initializing frames skipped and 83 normal-tracking frames processed.
- 745,987 original depth samples included across the 83 frames; per-frame range 4,679–22,506.
- Twelve sampled views produced 26,476 unmerged mesh vertices in the world preview.
- Four-view render visually inspected. The overall head outline, rear and crown become visible, but overlapping layers, rough facial detail, neck/hair geometry and cropped boundaries remain. Camera poses alone do not establish accurate subject registration.

Private masks, individual surfaces and rendered evidence are in ignored `outputs/rear-world-region/` and `outputs/rear-world-preview/`. No subject media is stored in this document.

Regression coverage includes world-fixed crop behavior under camera translation, intrinsic scaling, exclusion accounting, empty regions, tracking/timing/calibration validation, bundle replay and payload-corruption rejection. The next reconstruction step must address head motion and semantic separation before treating the aggregate as a scalp-fitting surface.
