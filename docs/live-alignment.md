# Live calibration and tracking gate

`LiveHairAlignment` fits a rigid canonical-head-to-AR-face-local transform using the existing robust landmark registration solver. The request names the exact scalp hash, tracking session UUID, face anchor UUID and landmark evidence hash. Sources must use `personal_canonical` coordinates; targets use `ar_face_local`, both in meters. No scale fitting or expression deformation is applied.

At least four fitting and three distinct held-out validation landmarks are required. The existing 4 mm median / 10 mm p95 validation thresholds are provisional engineering targets, not achieved physical accuracy. Failed validation prevents calibration output. A tracker recomputes the calibration before accepting a decoded record, so modifying an accepted flag or transform does not bypass the fit.

For rendering, `worldFromCanonical = worldFromFace × faceFromCanonical`. Tests use a rotation and translation to check composition order. Geometry remains rigid under the head transform; face expression blend shapes are not inputs to the hair transform.

`LiveHairTracker` provides four states: acquiring, visible, tracking lost and recalibration required. It requires three consecutive valid tracked samples before presenting a transform. Untracked/invalid poses hide the transform. A presentation call hides stale geometry after 200 ms without a valid current sample; callers must invoke it on every display frame, including when AR callbacks stop. Late samples are ignored. A new anchor/session, interruption, or abrupt continuous pose jump exceeding 25 cm or 60 degrees requires a new calibration. These thresholds need device evaluation.

The tracker returns no world transform when hidden. It does not itself animate a fade, identify people or run a camera. An anchor ID is session continuity, not biometric identity. Reacquisition after an ordinary tracking gap requires three fresh samples; recalibration-required is latched until a new tracker is constructed from fresh calibration.

```sh
tools/dev.sh swift run capture-inspect live-calibrate SCALP.json REQUEST.json RESULT.json
```

Remaining work: actual ARKit sample adapter, neutral-face landmark acquisition/correspondence, native calibration and live screens, lifecycle/permission wiring, fade animation, occlusion, temporal filtering and real-person pose/latency/drift tests. Synthetic calibration tests do not prove live try-on.
