# Image-detail diagnostic

New sensor recordings save optional `quality.imageDetail` on each retained frame.
All three capture paths use the same implementation before JPEG encoding. Frame
review displays detail and contrast; earlier recordings remain readable with this
field absent. The diagnostic does not reject frames or alter sample-rate settings.

Method `center60_srgb128_laplacian4_v1` takes a centered square spanning 60% of the
shorter image dimension, resamples it to 128 × 128 using Core Image's affine
resampling, and renders RGBA8 in sRGB. It computes encoded RGB luma using weights
0.2126, 0.7152, 0.0722, normalized to 0–1. Saved values are mean luma, population
luma standard deviation, and population variance of the four-neighbor Laplacian
over the interior 126 × 126 samples. No image orientation correction is needed for
these scalar statistics. The crop is centered on the image, **not a detected head**.

There is no calibrated blur threshold. Lighting, contrast, noise, texture,
resampling, subject size and background content can change these values. A low
value does not establish poor focus, and a high value does not establish usable
facial detail, coverage or registration. Smooth/dark hair remains valid evidence.
These statistics cannot determine root-to-tip direction, strand density or natural
hair volume. On-device capture overhead and its effect on saved cadence remain
unmeasured; inspect the separate timestamp report during the next device run.

Existing captures can be inspected without modifying their manifests:

```sh
tools/dev.sh swift run capture-inspect image-detail BUNDLE FRAME_INDEX OUTPUT.json
```

This command verifies bundle integrity, binds its report to the frame and image
hash, and refuses an existing output. Its source is `saved_jpeg`; JPEG compression
can change its values relative to the pre-encoding camera-buffer diagnostic.
Do not mix those sources when assessing repeatability. Reports from participant
recordings stay in ignored local output directories.

Validation on 2026-09-11: all 163 Swift tests pass and the unsigned iOS build passes.
Tests cover softened versus sharp synthetic edges, rotation, flat content, actual
Core Image crop/color conversion with a nonzero image origin, legacy decoding,
round-trip persistence, and invalid evidence rejection. An existing participant
rear frame was processed successfully by the offline command; this is execution
evidence, not a focus or reconstruction-accuracy result. No physical phone build
was installed or camera activated for this change.
