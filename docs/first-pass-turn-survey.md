# First repeat pass: front-to-profile transition

The alternate repeat capture was inspected across the full pass and every frame around its first side turn. Frame 24 is near frontal; frames 25–27 show movement/blur; 28–29 settle into a side view. Six pinned-model face masks were independently replayed, then all five adjacent RGB/depth flow registrations were attempted with unchanged 4 mm median / 10 mm p95 validation gates.

| Pair | Median (mm) | p95 (mm) | Local result |
|---|---:|---:|---|
| 24→25 | 3.14 | 35.05 | Rejected |
| 25→26 | 2.67 | 11.68 | Rejected |
| 26→27 | 1.89 | 5.19 | Pass |
| 27→28 | 1.32 | 4.86 | Pass |
| 28→29 | 1.36 | 4.77 | Pass |

Independent original-depth replay checks all 1,825 retained correspondence residuals, including the failures. The local graph has three components. The profile remains disconnected from the frontal frame; no transform chain or fused head is accepted. Optical-flow correspondences have correlated errors and do not establish anatomical accuracy. No threshold was relaxed to connect the graph.

The result motivates an optional denser front capture experiment. **Record more frames during turns** now requests every distinct synchronized callback from the existing 15 fps TrueDepth configuration, instead of the default 3 Hz saving target. The manifest records the requested rate, and timestamps remain the source for measuring actual delivery. Dense mode bypasses the 1/15 floating-point interval comparison so it does not accidentally skip a callback at that boundary. It retains the existing raw depth format, camera configuration, 900-frame limit and thermal/interruption stops. The option is disabled during recording/preparation and does not affect rear captures.

This attempts to reduce angular separation between saved views. It cannot remove motion blur, improve exposure or guarantee 15 saved frames per second under storage pressure. Approximately five times the storage is expected at equal duration and frame dimensions. Actual throughput, thermal behavior and registration improvement require a new device run; a new optional recording was subsequently requested when the participant offered availability before sleep; its result has not yet been inspected.

The iPhone SDK build verifies the new option compiles. A signed build was subsequently installed on the paired iPhone 15 Pro for a 25–35 second slow front-to-side-turn experiment. Its physical capture behavior remains unverified. Existing core tests were not rerun because no core algorithm changed. The flow survey used a freshly built release inspector, and the runner now accepts an explicit `--cli` path for reproducibility. See [sanitized metrics](evidence/first-pass-turn-survey-2026-09-11.json). Local masks, contact sheets and raw reports remain under ignored `outputs/first-pass-turn-survey/`.
