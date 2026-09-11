# Capture bundle v1

Implemented by `HairCore` and used directly by the iOS harness and macOS inspector. All tests and fixtures currently exercise the file/projection contract, not the accuracy of a real facial scan.

## Layout

```text
<pass UUID>/
  manifest.json
  frames/<frame UUID>/
    frame.json
    image.jpg
    depth.f32       # if depth is present
    confidence.u8   # optional ARKit confidence, same dimensions as depth
```

The manifest indexes every published frame. Each file reference includes a relative path, byte count and SHA-256. Frame metadata is also saved beside each frame so a frame written just before a manifest-write failure can be recovered. The current inspector reports indexed data; orphan recovery is a remaining implementation item.

The writer builds each frame in a temporary directory, renames that directory, then atomically checkpoints the manifest. Passes have `recording`, `completed` or `interrupted` state. A process killed during capture leaves a `recording` pass; review treats it as incomplete. Empty passes are invalid. A normal explicit finish closes the pass without claiming adequate regional coverage.

## Coordinates and calibration

- Depth is packed row-major IEEE float32, little-endian, in meters. Row padding is removed. Zero, negative and nonfinite samples are preserved and rejected by projection.
- Optical camera axes are X right, Y down, Z forward. Native sensor buffers are unmirrored. UI rotation/mirroring does not modify evidence.
- Intrinsics include their reference image dimensions; projection scales focal lengths and principal point to depth dimensions.
- A pose is a right-handed rigid 4×4 row-major matrix, with translation in meters, mapping optical camera coordinates into the source world. ARKit's camera basis is converted explicitly.
- Rear world poses track the device against the environment. They are **not** head-relative poses. Front poses are unknown in this harness. The inspector does not fuse frames.
- TrueDepth lens lookup tables, inverse tables, distortion center, extrinsic matrix and pixel size are retained when available. Current pinhole replay does not correct lens distortion and is labeled approximate.
- Source pixel formats and nominal camera rate are stored where known. Exported depth is always converted to float32 meters; image evidence is JPEG. RGB/depth timestamps remain separate, in their source session clock.

The native front capture selects a supported depth format and 15 FPS source stream, sampling evidence at 3 Hz. Rear capture samples AR frames at 3 Hz. The 900-frame/pass cap bounds storage. Raw and smoothed AR depth are not mixed. Current rear data uses `sceneDepth` rather than `smoothedSceneDepth`.

## Integrity, replay and exports

`capture-inspect inspect` checks schema version, frame identity, monotonic image timestamps, expected filenames, containment against symlink/path traversal, sizes, SHA-256, float32 payload length and rigid-pose validity. A successful integrity check does not prove capture quality, subject consent authenticity or correct anatomical reconstruction.

The iOS reviewer loads frames and projects a single frame as a point cloud. It exports a standard ZIP32 archive with stored (uncompressed) entries. The archive is independently tested by extracting it using the system unzip tool and validating the extracted evidence. The export is temporary and removed when sharing is dismissed. Captures are also accessible through the app's Files documents.

Recorded captures are excluded from device backups and use protected local storage. Cloud upload and automated retention are not yet implemented. Delete is available in the reviewer. Do not collect a study dataset with this harness until its consent/retention workflow has been completed.

## Synthetic fixture

The fixture is a 64×48 pinhole depth image at 0.5 m, with an off-center patch at 0.42 m and invalid samples along its left edge. Three frames include known camera translations for projection tests. It is explicitly marked `synthetic_fixture` in the manifest and UI.

This fixture has no face, hair, physical sensor readings or person-specific generation. It validates serialization, checksums, invalid-sample handling, coordinate conventions, replay and export.
