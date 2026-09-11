# Landmark registration

`HairCore.RigidRegistration` estimates a proper rigid transform between two named coordinate frames from explicit landmark correspondences in meters. It is an initial M1 building block, not an automated front/rear head reconstruction pipeline.

The implementation uses the rotation component of [Horn's quaternion solution](https://people.csail.mit.edu/bkph/papers/Absolute_Orientation_Scanned.pdf), with centroid translation and **no scale estimation**. A bounded deterministic RANSAC search rejects inconsistent correspondences, followed by consensus refinement. Collinear, narrowly distributed, nonfinite or duplicated samples are rejected.

## Input

Use [the asymmetric fixture](../fixtures/registration/asymmetric.json) as an example of the versioned JSON format. Supply distinct `sourceFrameID` and `targetFrameID`, evidence provenance, 4–200 fitting pairs, and 3–200 validation pairs. Each pair contains an ID and source/target `{x,y,z}` coordinates in meters.

Validation points must be separate from fitting points. They never influence hypothesis selection or refinement. The canonical encoded input is hashed into the report. Default gates are 5 mm fitting-inlier distance, at least 60% consensus (minimum four), held-out median ≤4 mm and nearest-rank p95 ≤10 mm. Fewer than 20 validation samples makes that p95 the maximum error; it is not a population estimate.

The tool cannot establish anatomical correspondence, skin visibility, subject identity, or statistical independence from input JSON. Callers must provide appropriately masked/identified landmarks. A passing report validates only the supplied geometric samples, not scan accuracy or complete head quality.

## Usage

```sh
tools/dev.sh swift run capture-inspect register \
  fixtures/registration/asymmetric.json outputs/registration.json
python3 tools/check_registration.py
tools/dev.sh swift test
```

The report includes `targetFromSource` as a row-major 4×4 matrix, inliers, outliers, all fitting/validation residuals, thresholds, provenance and acceptance status. The transform maps source points to target points. Distances are meters throughout the file.

Exit 0 means the supplied geometry passed the gates. Exit 2 means a fitted transform failed independent validation; its report is written for diagnosis and **must not be used for fusion**. Exit 1 indicates invalid input or inability to find a consistent rigid fit. No nonrigid warp or scale adjustment hides a disagreement.

## Verification and remaining work

### Registering actual capture frames

```sh
tools/dev.sh swift run capture-inspect register-captures \
  /path/to/source-bundle /path/to/target-bundle selection.json report.json
```

`selection.json` has `schemaVersion: 1`, `sourceFrameID` and `targetFrameID` from the respective manifests, plus `fitPairs` and `validationPairs`. Each pair has `id`, `source: {x,y}` and `target: {x,y}` in **native, unmirrored image pixels**, before any UI rotation. This selection is currently supplied as JSON; automatic landmark extraction and a native point-selection interface remain to be implemented.

The adapter verifies bundle integrity, requires completed geometry passes, samples nearest-pixel depth at each selected image ray, rejects invalid/out-of-range depth and insufficient AR confidence, then builds the metric registration input. It binds the result to hashes of both source frame records and the selection. A mixed synthetic/sensor pair is always reported as synthetic evidence.

For unrectified TrueDepth points, the adapter uses the inverse radial lookup table and distortion center in intrinsic-reference dimensions. This point-mapping direction follows the reference implementation in Apple's `AVCameraCalibrationData.h`: image resampling and individual point mapping use opposite lookup directions. Missing correction data causes rejection, not silent pinhole projection. See [Apple lens calibration](https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata/lensdistortionlookuptable) and [inverse lens calibration](https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata/inverselensdistortionlookuptable).

Depth quantization, nearest-neighbor sampling and correlated sensor noise remain error sources. The adapter does not label the chosen pixels as skin, infer a hidden scalp, rectify whole images, or establish correct anatomical correspondence.

### Tests

Unit tests cover identity, rotations including 180 degrees, translation, outliers, noisy data, deterministic larger sampling, rejected scale mismatch, duplicate/degenerate data and validation failure. CLI fixtures use an independently computed `Rz × Ry × Rx` rotation and translation, plus an outlier. A second fixture changes only a held-out point: it must fail while retaining exactly the same fitted transform.

Additional tests cover lookup direction, a distortion center different from the principal point, radial interpolation, coordinate-resolution scaling, low-confidence/invalid depth rejection, and registration from actual bundle files generated by the synthetic fixture tool. The CLI verification script exercises both direct 3D input and the capture adapter.

These fixtures are synthetic, and their near-zero numerical error is not a sensor accuracy claim. Automatic head-relative pose estimation, landmark extraction/selection UI, full-image rectification, skin masking, surface-overlap refinement, fusion, scalp completion and real repeatability experiments remain unimplemented.
