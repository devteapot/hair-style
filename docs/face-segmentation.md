# Local face parsing and observed forehead coverage

Date: 2026-09-10. Offline M1 masking experiment; no accepted complete head or native segmentation integration.

## Problem and change

The original face patch uses a convex hull of facial landmarks. That hull excludes visible forehead skin above the eyebrows even when the capture contains valid depth there. Raising sampling density cannot recover pixels outside that mask.

`tools/segment_face_capture.py` now runs a pinned SegFormer face parser locally, reverses the explicit image quarter-turn, and produces an explicit `model_inferred` mask at native depth resolution. The existing capture-backed Swift surface builder then checks source integrity, timestamps, metric projection, valid depth and triangle edges. The raw capture is unchanged.

Retained classes are skin, nose, eyes, brows, ears and lips. Hair, glasses, hats, jewelry, neck and clothing are excluded from the retained class group. The threshold is 0.8 on the **sum of the retained classes' posterior probabilities**, not each class's maximum. A first trial using maximum-class confidence incorrectly cut seams between skin and nose/lips although both are wanted; the grouped posterior fixes that selection error without dilation, hole filling or depth invention. This probability is not calibrated accuracy.

The existing ±80 mm band is centered on the median valid depth inside the inferred face region. Surface sampling stays at stride two, maximum triangle edge 10 mm and minimum sensor confidence one where available. Every output vertex in the single-frame replay has one original pixel observation and exactly that pixel's recorded Z value. Shared positions with the previous surface are bit-for-bit equal.

## Model and reproduction

The author describes [jonathandinu/face-parsing](https://huggingface.co/jonathandinu/face-parsing) as SegFormer fine-tuned on CelebAMask-HQ and restricts it to research and educational use. It is an evaluation dependency, not cleared for commercial distribution. Broader terms, demographic coverage and segmentation quality require review.

Pinned repository revision: `758b82e15a0178c9db39c1ff666a8b56e3a550c8`.

Weights: `model.safetensors`, 338,580,732 bytes, SHA-256 `c2bec795a8c243db71bd95be538fd62559003566466c71237e45c99b920f4b62`. Model, processor, configuration and model-card hashes are recorded in the evidence manifest. The runner checks local assets before inference, requires safetensors, loads known Transformers classes with local files only, and disables MPS fallback. No capture is uploaded. The research environment uses the previously frozen Metal dependencies.

Fetch the four pinned assets once (338.6 MB), or add `--verify-only` to check existing files without network access. The fetcher reads no captures. Then run the local experiment:

```sh
tools/dev.sh swift build
.research/metal-env/bin/python tools/fetch_face_parsing.py
.research/metal-env/bin/python tools/segment_face_capture.py CAPTURE_BUNDLE 20 NEW_OUTPUT_DIRECTORY --rotation clockwise90 --compare-cpu
.research/metal-env/bin/python tools/check_face_segmentation.py CAPTURE_BUNDLE OUTPUT_ROOT --old-root OLD_SINGLE_FRAME_ROOT
```

The script writes label/confidence arrays, hashes, a surface mask request, the observed JSON/PLY surface and a private diagnostic plot. Rotation is supplied explicitly; the capture does not yet retain device-to-upright orientation. Labels are transformed back before depth sampling, rather than rotating the physical coordinates. Lower-resolution aligned depth uses nearest image pixels at depth-pixel centers.

## Recorded results

Eight existing front-capture frames were processed: 18, 19, 20, 21, 22, 30, 55 and 75. These include near-frontal and turned views; they are eight frames from one participant, not eight independent participants or a supported-domain evaluation. All eight passed the independent mask/depth/vertex replay checks. No retained pixel had a hair/hat/glasses/neck/clothing/background argmax in these outputs; this is model self-consistency, not ground-truth segmentation accuracy.

Frame 20:

| Measurement | Result |
|---|---:|
| Previous component-cleaned patch vertices | 10,094 |
| New observed patch vertices / triangles | 16,066 / 31,277 |
| Shared vertices with exactly unchanged positions | 9,926 |
| Newly retained measured vertices | 6,140 |
| Previous vertices excluded by the new mask | 168 |
| Retained native depth pixels | 64,349 |
| CPU versus Metal class-label agreement | 100%; zero different pixels |
| Largest retained-class confidence difference | 0.0000010431 |
| Metal forward pass, final trial | 0.313 seconds |
| CPU forward pass, final trial | 2.807 seconds |

Timings exclude weight loading, integrity inspection, mesh construction and plotting. Seven subsequent frame jobs took 6.64–6.79 seconds end-to-end each on this Mac. These samples do not establish latency percentiles or phone performance.

The new masks replayed the original five-frame registrations for frames 18–22 without changed thresholds or correspondences. Fusion produced 43,268 vertices and 139,070 per-view triangles; overlapping sheets are still unsuitable as a fitting mesh. The existing field extractor produced 37,317 vertices / 71,982 triangles, zero nonmanifold edges, zero inconsistent winding edges and 2,710 boundary edges. Its vertices are interpolated field geometry, not direct additional measurements.

Dense agreement with reference frame 20 keeps the original fixed transforms and every supplied sample:

| Source | Source→20 p95 | 20→source p95 | Largest distance, either direction |
|---|---:|---:|---:|
| 18 | 3.616 mm | 3.562 mm | 12.086 mm |
| 19 | 2.235 mm | 2.154 mm | 11.093 mm |
| 21 | 2.192 mm | 2.164 mm | 7.710 mm |
| 22 | 2.791 mm | 2.779 mm | 10.829 mm |

These nearest-sample distances are not held-out anatomical accuracy, and changed masks change the evaluated point sets.

## Inspection and remaining gates

Private same-scale front/profile comparisons confirm additional forehead coverage. The original and new versions use the same canonical transform, cameras and lighting. The field remesh is smoother but retains holes around eyes, nose, mouth and chin. Small peripheral fragments remain. No stored scalp, haircut or app review was replaced.

The turned frame 55 recovers visible ear/skin while excluding the tied hair, but its nose is clipped by the image border. Frame 75 shows motion blur. Successful segmentation does not make those captures suitable for registration or reconstruction. Neither missing scalp nor hidden ears are inferred by this mask.

Remaining work includes native or worker integration, semantic validation and failure detection, stable local surface estimation, full front/rear registration, repeat scans and a measured rigid fixture. No M1 gate is completed by the mask or edge-topology checks.

Aggregate evidence: [face segmentation verification](evidence/face-segmentation-2026-09-10.json). Participant images, predictions and mesh artifacts stay under ignored `outputs/face-segmentation-v2/`.
