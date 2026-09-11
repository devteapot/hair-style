# Partial observed surfaces

The shared Swift core and Mac CLI can triangulate masked, calibrated depth frames and fuse registered contributors. This is an incremental part of M1.3. It does not produce a canonical complete head, infer a hidden scalp, identify hair automatically, or establish physical accuracy.

## Input and execution

Unzip each capture bundle into `CAPTURE_ROOT/<capture UUID>/`. Supply a JSON-encoded `SurfaceRequest`, whose first frame defines the output camera coordinates. Each frame identifies its capture/frame UUID and a native-depth-resolution inclusion mask. All captures must belong to the same subject session and be completed front-face or rear-head passes.

```sh
tools/dev.sh swift run capture-inspect surface \
  CAPTURE_ROOT request.json surface.json surface.ply
python3 tools/check_surface.py
```

`tools/check_surface.py` constructs a complete request and exercises success and rejection paths using synthetic bundles. The request fields are:

| Field | Meaning |
|---|---|
| `schemaVersion` | `1` |
| `frames` | 1–8 selected frames; duplicate capture/frame pairs rejected |
| `frames[].captureID`, `frameID` | IDs recorded in capture manifests |
| `frames[].mask.size` | Width/height matching the depth image |
| `frames[].mask.includedRuns` | Sorted, disjoint `{start,count}` runs of included row-major pixels |
| `frames[].mask.provenance` | `user_selected`, `model_inferred`, or `synthetic_fixture` |
| `frames[].mask.method` | Description or version of the process that supplied the mask |
| `frames[].registrationToReference` | Required for contributors, absent on the first frame; the pixel selection contract in [registration](registration.md) |
| `samplingStride` | 1–8; default 2 |
| `minimumConfidence` | 0–2; default 1, applied where confidence exists |
| `maximumEdgeMeters` | 0.002–0.05; default 0.02 |
| `fusionRadiusMeters` | 0.0001–0.003; default 0.0015 |

These are experimental processing limits, not sensor accuracy claims. The synthetic 64×48 fixture needs stride 1 at the default edge threshold (or a larger threshold at stride 2). Its pixel spacing is much larger than a typical close-range depth capture.

## Processing and evidence

1. Verify capture payload checksums, frame associations, calibration, dimensions and coordinate convention. Reject synthetic mask/calibration provenance attached to sensor captures.
2. Recompute each contributor's rigid registration from its selected depth landmarks against the reference. Require independent validation to pass. Both fitting and validation selections must fall inside their respective inclusion masks. Do not use AR world poses as stationary-head poses.
3. Project native depth pixels using calibration and inverse lens point correction when required. Reject unknown rectification, invalid depth, insufficient recorded confidence, and nonfinite/extreme projection. Missing confidence is reported through original frame evidence; it is not invented.
4. Triangulate the depth grid. A coarse cell is excluded if any full-resolution sample inside it is masked or invalid. Reject excessively long edges and degenerate faces, preserving depth discontinuities and masked holes within each view.
5. Fuse close samples from different views only when their normals agree. Match to a fixed first-observation anchor, avoiding an unbounded chain of nearby averages. Keep every contributing depth-pixel reference. Remove duplicate/collapsed faces and faces whose post-fusion edges or orientation fail checks.

Processing is bounded to one million depth pixels per mask and 250,000 fused vertices. Output uses the first frame's optical camera axes: x right, y down, z forward, meters. This is not yet a canonical anatomical coordinate frame.

The JSON output stores frame and mask hashes, the full registration report, the request hash, transforms, triangles, normals, and each vertex's `(frameIndex, depthPixelIndex)` observations. Any synthetic input marks the combined output synthetic. The PLY includes positions, normals and triangles; keep its JSON alongside it because PLY does not carry the full provenance. Hashes bind the supplied artifacts and do not independently authenticate a sensor or subject.

## Verified scope and remaining work

Tests cover mask holes between coarse samples, discontinuities, normal orientation, identical-view fusion, evidence retention, withheld-landmark disagreement, masked registration landmarks, mismatched subject sessions, malformed masks, altered payloads, and extreme calibration. The CLI independently checks the synthetic fixture's expected 3,024 vertices and 5,753 triangles, verifies both observation references, exports PLY and rejects failed registration without creating an output.

This is local depth-grid fusion, not dense ICP/TSDF reconstruction. Imperfect overlap may leave seams, duplicate layers, or nonmanifold topology; manifoldness is not guaranteed. No hidden surface is filled. A gap in one view can legitimately be observed by another. Caller-supplied mask semantics and landmark correspondence still require review. Automated segmentation, motion/quality gating, dense overlap refinement, canonical coordinates, head completion, and repeated physical captures remain necessary for the personal-head milestone.
