# Procedural generation comparison baseline

`ProceduralHairBaseline` implements the procedural comparison route in M0.6. It produces canonical editable guides from a personal input contract and explicitly supplied scalp roots. It is not the AI hairstyle generator, an automatic root estimator or a physical hair simulator.

The request contains a UUID, scalp bindings with anatomical regions, and a preferred strand length in meters. Each target is clamped to the compiled region's allowed range. Haircut validation subsequently enforces supported current-length observations when growth is disallowed.

For each root, the baseline projects the nearest medium/high-quality flow observation from the same region onto the local scalp tangent plane. Observations farther than 5 cm are not used. A deterministic canonical-axis tangent is the fallback. The decision record identifies the selected observation or fallback.

Regional texture changes the wave amplitude/frequency of a simple curve. Straight, mixed and unknown texture use the unmodulated comparison curve; mixed texture is not reconstructed. Wavy/curly/coily values select increasingly frequent waves, not a physically calibrated curl model. A seed-derived phase varies guides reproducibly. The resulting 97-point curve is normalized to the target arc length and attached at the supplied root.

The output uses a diagnostic neutral material, carries the request and its hash, preserves the source profile/brief identity, and explicitly identifies generation origin as `procedural_baseline`. No natural color measurement is claimed. Maximum output is 2,048 guides. Duplicate binding records fail; spatially duplicate roots represented through different triangles are not yet detected.

Optional supplied anatomy invokes the existing face/ear capsule clearance check and rejects intersections before output. Scalp interior, self-collision, continuous regional transitions, hairline enforcement, styling feasibility and aesthetics remain unverified. Sparse guides alone are not a complete hairstyle.

```sh
tools/dev.sh swift run capture-inspect hair-baseline INPUT.json REQUEST.json RESULT.json
# Optional final argument: ANATOMY.json
```

`RESULT.json` contains `haircut`, validation, per-guide decisions and limitations. The haircut can enter the existing validator, editor and immutable repository without a different representation. The synthetic native studio is not yet connected to this command.

Tests hold intent/seed/length fixed while changing flow/texture, verify regional shape changes, repeatability, exact root binding, arc length and edit replay, and reject a supplied anatomical intersection. `tools/check_baseline.py` exercises generation followed by the existing CLI editor/repository. These checks use synthetic data; they do not satisfy the plan's AI personalization or real-person generation gate.
