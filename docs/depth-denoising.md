# Optional bounded depth denoising

Implemented and evaluated 2026-09-11. Local filtering slightly smooths the second repeat capture's experimental face surface but does not resolve the main nose and boundary gaps. It remains off by default and is not installed as a replacement app model.

## Processing contract

`ProjectiveFusionRequest.depthDenoising` optionally supplies `DepthDenoisingSettings`. The default experiment uses a radius of two native depth pixels, spatial sigma 1.5 pixels, range sigma 2 mm, maximum neighbor difference 4 mm, maximum sample adjustment 1 mm, and at least five usable samples including the center. Settings have bounded validation ranges.

`MaskedDepthDenoising` computes a single bilateral pass from the original buffer, never recursively from already filtered values. Invalid and excluded center pixels remain unchanged. Excluded neighbors do not contribute; neighbors beyond the depth-difference limit do not contribute. Insufficient neighborhoods preserve their original center value. Float rounding is constrained to keep the serialized sample inside the requested movement limit. Original capture files, masks, source landmarks and registration transforms are not rewritten.

The filtered buffer influences only the integrated scalar distance values. Candidate seeds, visibility classification, near-surface support, raw signed-distance disagreement and final output-vertex validation continue to use original depth. A changed integration value therefore cannot make an unsupported grid node pass or hide a raw free-space contradiction. The output method is `masked_denoised_projective_tsdf_v1`, and its hashed request records the settings. Geometry remains interpolated/inferred processing output, not direct sensor observations.

## Verification

The core suite has 106 passing tests. New tests cover a known noisy plane, preserved invalid/excluded samples, a depth step and isolated sample, Float adjustment bounds, malformed settings, unchanged capture-backed planar holes, and an original-depth contradiction that filtering must not hide. The unsigned generic iPhone SDK build passes. No UI, camera session or physical rendering behavior changed.

Two physical runs use exactly the same second-pass frames, masks, registrations and 1.5 mm voxel grid. Raw integration reproduces the prior vertices and triangles exactly. Filtered integration modifies 107,712 pixel values across the three frames, clamps 942 proposals at the configured limit, and leaves 311 centers unchanged for insufficient neighbors. Rejected-neighbor counts are repeated neighborhood sample evaluations, not distinct pixels.

Raw integration yields 51,611 vertices / 95,818 triangles; filtering yields 49,849 vertices / 92,542 triangles. Both retain the same 57,985 supported grid nodes. Both independently pass all final vertex support checks against the original depth, with no nonmanifold or inconsistent-winding edges. These checks establish internal consistency, not physical accuracy or complete coverage.

The fixed-camera comparison was inspected: fine roughness is reduced modestly while the major gaps remain. Nearest-output-vertex retention was measured with the same reference samples and brute-force spot checks; that diagnostic depends on output sampling and cannot establish anatomical quality. Further progress requires investigating pose consistency, observation coverage or a separately validated completion method, rather than relying on smoothing alone.

## Artifacts

[Sanitized evidence](evidence/depth-denoising-2026-09-11.json) records settings, counts, runtimes, support checks and source hashes. Participant-derived requests, meshes and images remain under ignored `outputs/depth-denoising/`. The existing `projective-fuse` command consumes the optional settings; omitting them retains raw integration. The app's existing review package remains unchanged.
