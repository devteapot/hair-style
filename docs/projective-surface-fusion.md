# Camera-aware surface fusion experiment

Evaluated 2026-09-11. This offline experiment produces a depth-supported partial face surface, but it is visibly more fragmented than the previous local tangent-field reconstruction. Neither surface is accepted for haircut fitting. The app's review asset has not been replaced.

## Implementation

`CalibratedDepthCamera` reconstructs native depth rays and projects points back into the same sensor coordinates. For raw TrueDepth it inverts the supplied inverse radial lookup mapping with bounded bisection. It rejects noninvertible calibration, mirrored frames and excessive synchronization skew. This verifies mathematical consistency with the supplied calibration, not physical camera accuracy. The existing pinhole-only `ProjectiveDepthAgreement` implementation is unchanged.

`ProjectiveSurfaceFusion` reopens authenticated capture payloads, replays landmark registrations and consumes explicit masks. It builds a sparse signed-distance field using original camera poses and nearest native depth samples. Masked or invalid pixels provide no evidence; samples sufficiently behind a visible surface are treated as occluded. Visible free-space disagreement is checked before distance truncation so clamping cannot conceal a contradictory frame.

Extraction requires supported values at all eight cube corners. Shared marching-tetrahedra edges and consistent winding produce a mesh without closing unknown regions. Every extracted vertex is projected back into the source frames; triangles touching vertices that fail support or raw depth-spread checks are removed. Normals are recomputed from retained triangles. This validates vertices, not every point inside a triangle or anatomical correctness.

The bounded experiment uses five nearby front frames, their existing registrations and the separately inferred semantic face masks. Parameters are 2 mm voxels, a 6 mm truncation band, at least two supporting frames and at most 8 mm raw signed-distance spread. Nearby frames remain correlated; these are not independent measurements or clinical tolerances.

## Results and validation

- Release execution: 2.63 seconds, about 256 MiB peak child resident memory on the local Mac.
- Retained mesh: 20,017 vertices and 36,090 triangles; 4,096 boundary edges, zero nonmanifold edges and zero inconsistent winding edges.
- Independent NumPy verification uses Newton inversion rather than the Swift bisection implementation. All retained vertices satisfy the configured support checks; no triangles touch unsupported vertices.
- The post-extraction check removed 366 triangles. Its prefilter counters are distinct from the independent final-output counters.
- 101 core tests pass, including calibrated projection, masked holes, conflicting depth, far free-space contradictions, invalid requests and payload tampering. The unsigned generic iPhone SDK build passes. No camera session or device installation was performed for this experiment.

The fixed-camera visual comparison shows significant gaps around the nose, mouth and chin and a fragmented boundary. Topological validity and depth consistency do not establish complete coverage, self-intersection freedom, measured accuracy or styling suitability. The next reconstruction investigation should distinguish registration error, sensor noise and missing support before changing acceptance thresholds. Do not relax checks merely to obtain a closed-looking face.

## Reproduction and evidence

The capture-backed command is:

```sh
.build/release/capture-inspect projective-fuse CAPTURE_ROOT REQUEST.json OUTPUT.json
.research/metal-env/bin/python tools/check_projective_fusion.py CAPTURE_ROOT OUTPUT.json REPORT.json
```

Build Swift executables through `tools/dev.sh`. The request embeds the masked `SurfaceRequest` and fusion parameters. Local participant artifacts are under ignored `outputs/projective-face-fusion-v2/`; its `comparison.png` uses identical transforms, cameras, scale and lighting for both methods. The earlier `outputs/projective-face-fusion/` directory contains a superseded draft that failed independent support checks and must not be used as final validation.

[Sanitized verification](evidence/projective-fusion-2026-09-11.json) records aggregate results, source hashes and explicit limitations. Raw images, masks, frame identities and participant geometry remain in ignored local outputs.

## Frame-count ablation

A subsequent controlled replay held voxel size, truncation, masks and available registrations fixed, using subsets of the five frames. Every variant passed the independent output-vertex support check. The same 16,066 measured samples from the reference frame were compared with each output's nearest vertex using a bounded spatial search. For each variant, 101 deterministic queries were also compared against brute-force distances to all output vertices (505 checks total).

| Frames / minimum support | Output vertices | Reference samples within 2 mm | Within 4 mm | Beyond 8 mm |
|---|---:|---:|---:|---:|
| One / one | 25,288 | 15,292 | 15,619 | 225 |
| Two / two | 21,869 | 14,496 | 15,149 | 477 |
| Three / two | 23,753 | 14,967 | 15,511 | 268 |
| Five / one | 21,226 | 14,023 | 15,379 | 126 |
| Five / two | 20,017 | 13,753 | 15,053 | 435 |

The single-frame case follows its own fitting samples most closely, as expected; adding views does not monotonically improve this metric. The inspected retention map places larger differences around boundaries and lower-face areas, but this experiment does not distinguish registration error from depth noise, mask disagreement or extraction behavior. Nearest-vertex proximity is not triangle coverage: a sample near the edge of a hole may still pass. Missing input samples do not enter the denominator. These results cannot be used to declare facial completeness or to choose a single-frame reconstruction as an accepted personal head.

The user was asked for two separate front passes around 40 cm, with neutral held poses, to compare against the earlier approximately 21 cm reference and measure repeatability. The existing capture build uses unfiltered front depth, a 15 FPS camera and a 3 Hz save rate; no recording parameters were changed. The requested distance is experimental, not a validated optimum.

[Sanitized ablation evidence](evidence/projective-ablation-2026-09-11.json) contains all aggregate counts and hashes. Private requests, outputs, verifier logs and the retention map remain under `outputs/projective-ablation/`. No thresholds were relaxed and no app asset was replaced.


## Second repeat capture: local fusion and voxel spacing

Frames 8 (reference), 6 and 10 of the second repeat front pass were reconstructed with their explicit semantic masks. The reverse 10→8 correspondence was recomputed through original captured depth and independently replayed; no matrix from a failed registration was used. An inferred scalp candidate supplied a new reference-specific anatomical display transform only; it is not an accepted scalp or an app asset replacement.

Both existing extraction methods were run. The tangent field produces 41,354 vertices / 79,960 triangles; the 2 mm projective field produces 25,849 vertices / 46,098 triangles. The inspected front/profile comparison still shows noisy surfaces and missing regions. Relative to the earlier capture, the lower face looks more complete, but different captures and masks prevent attributing that difference to distance alone.

A spacing ablation holds masks, registrations, 6 mm truncation, two-frame support and 8 mm raw signed-distance spread fixed:

| Voxel spacing | Vertices | Triangles | Reference samples within 4 mm of an output vertex | Reference samples beyond 8 mm |
|---|---:|---:|---:|---:|
| 1.5 mm | 51,611 | 95,818 | 8,735 / 8,979 | 85 |
| 2 mm | 25,849 | 46,098 | 8,498 / 8,979 | 229 |
| 3 mm | 8,651 | 13,732 | 7,807 / 8,979 | 658 |

All three outputs pass the independent original-depth support check for every retained vertex, with no nonmanifold or inconsistent-winding edges. Each nearest-vertex comparison also checks 101 deterministic queries against brute force. As expected, a finer output vertex set can itself improve nearest-vertex distances; this metric is not anatomical coverage. The inspected fixed-camera 2 mm / 1.5 mm render additionally shows a smaller nose gap, but residual holes and surface noise remain. No depth-acceptance limits were loosened.

The next experiment should address noisy observations or pose consistency while retaining the original samples and explicit processing provenance. A closed-looking mesh alone will not establish accuracy. The app model remains unchanged; no new device capture, installation or SDK build was needed for this offline replay.

[Sanitized fusion evidence](evidence/repeat-front-fusion-2026-09-11.json) contains support checks, counts, hashes and limitations. Participant geometry, requests and both comparison images remain under ignored `outputs/repeat-front-fusion/`.
