# Reconstructed-model depth consistency and capture lens metadata

The USDZ can now be exported into its imported mesh coordinates and checked against original depth samples using returned Object Capture camera poses. This tests whether the visually recognizable model is also consistent with its input measurements; it does not establish physical accuracy.

## Tools

```sh
tools/dev.sh swift tools/export_model_mesh.swift MODEL.usdz MESH.json
python3 tools/check_model_mesh_export.py
python3 tools/check_model_depth.py CAPTURE_BUNDLE RECONSTRUCTION_DIR MESH.json NEW_REPORT.json
python3 tools/check_triangle_rays.py
python3 tools/diagnose_model_scale.py DEPTH_REPORT.json NEW_SCALE_REPORT.json
python3 tools/check_scale_diagnostic.py
```

Depth comparison requires NumPy. The mesh exporter preserves node transforms and binds output to the source file hash. The ray checker uses two-sided nearest triangle intersection and reports every sampled masked pixel, including model misses. It applies the explicit model-from-AR-camera pose hypothesis with optical-axis conversion `diag(1,-1,-1)`; no registration or scale is fitted during this check. Default rays use captured intrinsics; `--intrinsics vendor` instead tests returned pinhole intrinsics. Vendor distortion is exported but not applied by this diagnostic, which limits that comparison.

Analytic checks cover a known plane, misses, reversed winding, nearest of two surfaces and rigid-transform invariance. The mesh exporter is checked against a transformed asymmetric box. Scale diagnostics fit the median of per-frame ratios on even sample IDs and evaluate odd sample IDs without refitting. All samples participated in reconstruction, so these are unused-by-scale-fitting frames, not independent ground truth.

## First preview result

Across 68 reconstructed views, stride-four sampling selected 29,024 native depth pixels. The model missed 4,326 rays. The 24,698 intersections have pooled median absolute depth disagreement of approximately 34.1 mm and p95 of 59.7 mm. A frame-balanced scale hypothesis of 0.91668 reduces the unused-frame median to 5.83 mm, but p95 remains 24.30 mm and the maximum 88.23 mm. A scale can compensate for coordinate or camera-model errors, so the model and camera poses were **not modified**.

## Camera-model investigation

The worker now also exports requested reconstruction bounds, estimated camera intrinsics and available lens-distortion tables on macOS 26+. A repeat without additional hints returned a focal length of about 1,548 pixels, versus approximately 1,356–1,367 pixels in the recorded ARKit intrinsics. This is a substantial mismatch. On that same repeat model, pooled depth medians were 27.11 mm with captured pinhole intrinsics and 25.72 mm with vendor pinhole intrinsics; respective p95 values were 52.22 and 45.80 mm. Neither interpretation establishes a calibrated model. Fits also differed between runs with the same sensor inputs, so a single successful export is insufficient evidence of repeatability. The returned bounds and the imported mesh bounds are retained separately; the estimated-coordinate relationship is not assumed proven.

Inspection found that our capture JPEG encoder retained RGB pixels but discarded ARKit's EXIF lens metadata. `CaptureImageMetadata` now preserves captured focal length, 35 mm equivalent focal length and lens make/model in the JPEG. The rear capture passes `ARFrame.exifData` into the encoder. Missing values remain missing; unrelated fields are not copied, and the encoded orientation stays sensor-native. Two new tests verify JPEG round-trip preservation and missing/invalid/nested metadata handling. The iPhone build passes, but a new physical capture is still needed to verify the live EXIF path.

An opt-in worker experiment (`--infer-focal-hint`) supplies a labelled 35 mm equivalent hint derived from the recorded pinhole diagonal field of view. This modifies only sample metadata for that run, not source captures. It is not presented as captured EXIF. The trial returned approximately 1,529 px focal length and still skipped 15 frames. Captured-intrinsics depth comparison remained poor (pooled median about 35.6 mm, p95 63.9 mm). This trial does not resolve the problem or justify replacing the installed preview.

The installed model therefore remains an unvalidated visual preview. Next work must constrain or validate the reconstruction camera model and its coordinate relationship before front TrueDepth integration or scalp fitting. No sensor accuracy, complete head, or haircut-generation gate is satisfied by these diagnostics.

Private reports are in ignored `outputs/object-capture-rear/`, `outputs/object-capture-calibration/` and `outputs/object-capture-focal-hint/`.

Primary references: [Apple's returned poses](https://developer.apple.com/documentation/realitykit/photogrammetrysession/poses), [pose intrinsics](https://developer.apple.com/documentation/realitykit/photogrammetrysession/pose), [EXIF metadata consumed by reconstruction](https://developer.apple.com/documentation/realitykit/photogrammetrysample/metadata).
