# Rear face reconstruction and cross-camera alignment

The assisted rear pass provides 1920×1440 images and aligned 256×192 scene depth. The experimental face-patch script now scales native image landmarks into depth coordinates and accepts `--stride 1` to retain the available rear depth samples. Calibration and triangulation still run through the capture-backed core builder.

```sh
python3 tools/reconstruct_face_patch.py REAR_BUNDLE REAR_LANDMARK_REPORT.json NEW_OUTPUT_DIRECTORY --stride 1
```

The mask remains a provisional landmark convex hull plus an 80 mm depth band; it is not semantic skin segmentation. Invalid/degenerate hulls and mismatched landmark image dimensions are rejected. No depth upsampling, facial completion or precision claim is introduced.

## Physical replay

Rear frame 60 produces a partial surface with 2,106 vertices and 3,998 triangles. Visual inspection shows coarse facial shape, but little fine eye/mouth detail compared with the front capture. Original front frame 20 was replayed after the coordinate-mapping change: its mask runs, all vertex records and all triangles are exactly unchanged (10,108 vertices / 19,480 triangles).

Vision reports were extracted for rear frames 56, 58, 59, 60, 61, 62 and 64. Eye-center separation inferred from their sampled landmark depths varies from approximately 62.5 to 68.0 mm within this same pass. These are unstable model/depth estimates, not anatomical measurements. They illustrate why one fixed 2D region index is an unreliable 3D correspondence across viewing conditions.

Seven original-depth registration replays against front frame 20 fail the unchanged rigid acceptance path: frame 56 reaches a transform but fails held-out validation; the others fail fit consensus. A broader diagnostic screen used the same fixed eye/nose index policy across seven rear views and fourteen previously extracted front views: zero of 98 pairs were accepted. No thresholds or metric scale were changed, and no front/rear fusion was published. The broad screen uses extracted 3D reports; only the seven frame-20 trials were independently replayed through the original-depth adapter.

This is evidence against the current correspondence method, not proof that the sensors cannot be combined. Next work needs geometry-based alignment and correspondences that survive viewpoint changes, with independent checks on dense overlap and measured fixtures. Repeating the same index-matching search or relaxing gates would not establish a usable personal head.
