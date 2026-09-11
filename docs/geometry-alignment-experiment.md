# Geometry-based alignment experiment

`tools/geometry_alignment_experiment.py` implements an offline, rigid point-to-point ICP experiment using NumPy. It accepts two single-view observed surfaces and a matching captured-registration report as a coarse initializer. That initializer may have failed landmark validation; its original failure is retained, and every result explicitly has `acceptedForFusion: false`. The experiment emits no accepted registration or fused surface.

```sh
python3 tools/geometry_alignment_experiment.py SOURCE_SURFACE.json TARGET_SURFACE.json CAPTURED_REGISTRATION.json NEW_OUTPUT_DIRECTORY
python3 tools/check_geometry_alignment.py
```

Use a Python environment with NumPy. No model weights, GPU service or participant upload is involved. The report records NumPy version and exact input-file hashes.

Fitting uses every third source sample, exact nearest-target search, a 20 mm correspondence cutoff and 3 mm robust weights. Weighted rigid SVD fits rotation/translation without scale or deformation. A deterministic source-sample split supplies unused-source diagnostics, but neighboring pixels and target points remain correlated; this is not independent ground truth. All evaluation statistics are untrimmed and bidirectional. Five translation-perturbed initializations probe local stability. Global convergence and observability are not established.

## Checks and physical result

Numerical checks recover a known rigid transform, preserve a proper rotation, match exact nearest search against brute force and reject absent overlap. Native/core sources did not change; the prior 65-test native core result is unchanged, not rerun for this offline experiment.

The real experiment uses rear frame 56 and cleaned front frame 20. The coarse landmark initializer failed its held-out gate. For the unperturbed ICP run, median rear→front sample distance changes from 3.59 to 1.99 mm and p95 from 9.94 to 7.66 mm. However, reverse p95 remains about 19.45 mm, with unmatched areas. Four starts reach the 40-iteration limit; one converges. Final source-centroid positions differ by up to 2.17 mm across starts. The algorithm's fitted rotation changes about nine degrees from the initializer.

Visual overlay inspection shows partial central overlap with substantial residual differences and unequal coverage. Lower one-direction distances do not justify publishing this alignment. The next experiment needs better visibility/overlap handling and a less ambiguous initializer, followed by independent physical calibration and repeat-capture checks. This result is not a personal head or haircut-fitting asset.
