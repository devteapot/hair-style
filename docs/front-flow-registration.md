# Native front-camera flow registration

Implemented and evaluated 2026-09-11. The existing RGB/depth optical-flow path now supports completed front TrueDepth captures as well as rear ARKit captures. The tested frontal matches are consistent, but the first substantial turn still fails. This does not establish profile coverage or accepted head reconstruction.

## Front sensor handling

Flow is estimated in original unmirrored sensor-image pixels. Forward/backward image consistency, explicit masks and original depth constrain candidate pairs. Each selected front-image ray is converted through the inverse lens calibration before rigid fitting. Front frames need synchronized native depth and valid lens calibration; absence of a confidence map is preserved rather than replaced with an invented score.

Rear behavior retains its normal-tracking, aligned-depth and confidence-map requirements. Both paths preserve the existing fitting and held-out thresholds, separate fit/validation selections, evidence hashes and failure reports. Local acceptance never declares full-head acceptance.

## Verification

The core suite has 108 passing tests. A new encoded-image/depth fixture verifies front metric translation with a nonzero inverse lens correction and no confidence raster; a missing-lens fixture is rejected. The existing rear translation and image-flow direction/round-trip tests still pass. The unsigned generic iPhone SDK build passes.

Five actual second-pass trials were retained:

| Source → target frame | Result |
|---|---|
| 18 → 8 | Local registration passes |
| 19 → 18 | Local registration passes |
| 20 → 19 | No consistent rigid alignment |
| 20 → 8 | Refined registration loses support |
| 19 → 8 | Local registration passes |

The three successful transforms remain near frontal. All 1,200 fitting/held-out residuals from these reports were independently replayed from original depth and lens metadata. Frame 19 and 20 masks pass independent mask/vertex checks. The failed attempts produce no accepted registration and were not used for fusion.

Composing 19→18→8 and comparing with the separately matched direct 19→8 transform gives 0.226° rotation difference. Across all 8,893 original frame-19 surface samples, their position differences have median 0.325 mm, nearest-rank p95 0.567 mm and maximum 0.666 mm. Camera-origin displacement is 1.205 mm, which differs from displacement at the face. These are internal consistency measurements on correlated inputs, not physical accuracy or general loop-closure validation.

The next experiment should evaluate bounded dense geometric refinement with a separate held-out check. A failed landmark fit may inform a research initializer, but it cannot be promoted to a fusion transform without fresh validation. Simply accumulating locally matched frontal frames will not establish the missing side views.

[Sanitized evidence](evidence/front-flow-2026-09-11.json) records all trial outcomes, loop statistics, test results and source hashes. Raw masks, images and participant geometry remain under ignored `outputs/front-flow/`. No camera was opened, app asset replaced or device build installed for this offline experiment.
