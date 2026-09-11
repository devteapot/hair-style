# Saved capture timing

`capture-inspect capture-timing BUNDLE OUTPUT.json` verifies bundle integrity, then reports saved image timestamp spacing in manifest order. The report binds to the canonical decoded manifest hash and retains every interval, including non-positive intervals as errors. It reports requested rate, observed average `(frameCount - 1) / (last - first)`, nearest-rank median/p95 positive interval, maximum positive interval and gaps exceeding twice the requested spacing. Empty/single-frame captures and non-increasing timestamps do not receive a misleading average rate.

Capture review now displays requested and recorded average rates, longest gap and timestamp-order errors after integrity checking. These describe saved evidence only: they are not the sensor's delivered FPS, writer-drop counts or an image sharpness/coverage score. A slow sustained save rate can have no large gaps and still provide insufficient angular coverage.

## Existing repeat passes

| Pass | Frames | Requested Hz | Observed Hz | Duration (s) | Longest gap (ms) |
|---|---:|---:|---:|---:|---:|
| First | 128 | 3 | 2.999835 | 42.335662 | 333.353 |
| Second | 115 | 3 | 2.999847 | 38.001941 | 333.352 |

Both have strictly increasing timestamps and no gaps over twice the requested interval. All intervals and the average/p95 arithmetic were independently replayed from original manifests. This shows that the examined sparse transition was recorded at the requested cadence; it does not prove denser recording will solve motion blur or registration.

Core tests cover slower-than-requested saving, long gaps, duplicate timestamps and empty captures. All 119 core tests and the unsigned iPhone SDK build pass. The simulator capture-review test passes with the timing panel present, followed by ordinary export, share-sheet dismissal and deletion. This checks UI availability and the existing workflow, not a new camera run. Physical 15 Hz throughput remains unmeasured. Sanitized results are in [the timing evidence](evidence/capture-timing-2026-09-11.json).
