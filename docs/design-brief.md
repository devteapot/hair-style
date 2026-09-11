# Design brief compilation

## Shared prepared-brief handoff

`PreparedDesignBrief` is the versioned contract shared by native preferences and processing tools. Preparation validates the source, compiles the request and retains the source envelope guard. Consumption requires the exact source hash and an identical compiler replay. Altered compiled constraints, another source or an unsupported version are rejected. Earlier native-only documents without a version remain readable as v1 only after replay. The app offers **Export saved brief**, explicitly exporting the saved document rather than unsaved controls.

```sh
capture-inspect brief-prepare SOURCE.json REQUEST.json PREPARED.json
capture-inspect brief-consume SOURCE.json PREPARED.json GENERATION_INPUT.json
```

Actual native-saved fixture preferences were consumed through the CLI, retaining guided mode and the edited 11 mm fringe minimum. All 131 core tests and the iPhone SDK build pass, including altered-output rejection and legacy replay. The generated input is ready for personal conditioning/preflight; it is not an accepted haircut and no generation endpoint automatically consumes it yet. Private replay: `outputs/native-brief-handoff/report.json`.

The native save/relaunch regression also passes after adopting the shared contract and verifies that the export action is available (`Test-PersonalizedHair-2026.09.11_03-35-18-+0200.xcresult`). No external share destination was selected or sent data.

Local personal-conditioning tools now consume this handoff directly with `--prepared-brief`; see [prepared conditioning input](personal-latent-constraint.md#required-attachment-preflight-for-new-runs). They validate it before attachment checks/model loading. Native/backend automatic submission remains unfinished.

## Explicit styling preferences

Guided requests can include optional `stylingPreferences`: `maximumDailyMinutes` (integer 0–180), `allowsHeatTools`, `allowsStylingProducts`, and `preserveNaturalTexture`. At least one field must be answered if the object is present. Nil fields remain unanswered; allowing a tool does not assert that a design requires it. Autonomous requests reject explicit preferences and continue without a questionnaire.

Preferences are retained in the canonical brief and its hash, and are revalidated on input replay. They are distinct from observed hair properties and `stylingAssumptions`. Explicit daily-time and texture choices replace the corresponding default labels; otherwise those defaults remain explicitly defaults. Compilation adds `requested_styling_constraints_unverified`, and haircut explanations retain/display the declared choices without claiming they are satisfied. Native preference preparation is described below; model/ranking enforcement remains unfinished. Existing briefs without these optional fields retain their legacy representation.

## Native preference preparation

The guide/model review now links to **Preferences for a new design**. Automatic mode requires no answers. Optional guided choices include daily time, heat tools, styling products, preserving natural texture and allowing growth. Unspecified choices retain nil values rather than becoming false answers. Saving compiles a new brief from the source scalp and hair profile and retains its envelope guard; it does not mutate the displayed haircut or its revision. Existing candidate-specific length design is not reused as a new proposal: the new brief requires generation and personal conditioning.

The protected, backup-excluded saved document contains the request, compiled result and source-input hash. It lives under the owning review's storage directory, so review deletion removes it. Restoration recompiles and compares the result before populating controls, and source changes select a different saved document. This is preference preparation; no generation endpoint consumes these documents yet. Model/ranking enforcement and candidate fulfillment remain unfinished.

The iPhone SDK build passes. A simulator test saves automatic mode without answers, saves guided mode with a time limit, relaunches, restores the controls and verifies the displayed haircut hash is unchanged. The first test attempts targeted the switch's containing row; after selecting the actual child switch, the complete flow passes (`Test-PersonalizedHair-2026.09.11_03-07-59-+0200.xcresult`). This does not verify generation or physical-device preference interaction.

## Native regional lengths

Guided mode now offers optional ranges for fringe, top, crown, anatomical left/right and nape. Each region displays its reliable recorded available length or explicitly uncertain status. Enabling a range supplies editable 10–100 mm starting values, labeled as preferences rather than measurements/recommendations. Minimum and maximum use 1 mm increments within the core's 1–1500 mm representational bounds. An inverted range is called out inline and rejected on compilation. A minimum above reliable available length still requires explicit growth permission; failures leave the previous saved brief intact.

Ranges are included in the same source-bound persisted request, restored through compiler replay, and omitted from automatic-mode requests. The simulator test enables a fringe range, changes its minimum to 11 mm, saves and relaunches, then verifies that value and an unchanged displayed haircut hash. The test and iPhone SDK build pass (`Test-PersonalizedHair-2026.09.11_03-31-30-+0200.xcresult`). This does not verify that a generated candidate fulfills the preferences; generation consumption remains unfinished.

All 129 core tests and the iPhone SDK build pass. Coverage includes unanswered fields, zero-minute/no-heat/no-product choices, round-trip persistence, brief-hash changes, autonomous rejection and invalid preference values. This is contract/compilation verification, not evidence that a generated cut meets maintenance requirements.

`DesignBriefCompiler` converts a versioned request plus scalp and length profile into a hash-bound `HairDesignInput`. It is the typed constraint layer for autonomous and guided generation. No LLM or haircut generator is invoked yet.

Autonomous requests contain a mode, identity and seed without mandatory preferences. Guided requests may supply regional length intervals and explicitly permit growth. Explicit preferences in autonomous mode are rejected so provenance cannot silently change.

The compiler validates profile/session identity, geometry, evidence and request ranges. For observed or user-supplied lengths of medium/high evidence quality, disallowed growth intersects the target interval with recorded available length. A minimum above that length fails rather than silently changing the requested minimum. The result retains both the requested interval and effective interval. Inferred, low-quality and missing lengths do not impose a falsely measured cap; their regions remain uncertain.

Unspecified ranges start at the contract's broad 1 mm–1.5 m representational bounds and are capped by supported evidence when growth is disallowed. These are not recommended hairstyle lengths. A later generator must choose useful lengths and demonstrate personalization. Regions below the minimum supported guide length currently fail compilation; shaved/bald region support remains work.

The result records policy defaults to preserve natural color/texture, avoid assumed extensions/chemical treatment and target low-to-moderate styling. These are neither observed preferences nor claims that styling is required. They are separate from `stylingAssumptions`, which remains empty until a candidate requires specific styling. The current guide validator therefore does not mark every default brief as requiring styling.

The CLI writes a compiled result containing `input`, region decisions, request hash, defaults and unresolved work:

```sh
tools/dev.sh swift run capture-inspect hair-brief SCALP.json PROFILE.json REQUEST.json RESULT.json
```

Example autonomous request:

```json
{
  "schemaVersion": 1,
  "id": "8F479BDE-375B-42B8-A4AB-1F357108DB76",
  "mode": "autonomous",
  "seed": 42,
  "lengthRanges": []
}
```

`allowGrowth` is optional and defaults to false. A guided `lengthRanges` entry uses `region`, `minimumMeters` and `maximumMeters`. Duplicate regions, unsupported schemas, invalid bounds and profile/session mismatches fail before output. The same request and source data produce identical compiled hashes.

Validation covers deterministic compilation, supported evidence versus uncertainty, guided interval intersection, explicit growth and input rejection. `tools/check_brief.py` exercises the CLI with a synthetic profile. Physical length estimation, full hairline/flow/texture conditioning, UI preferences, LLM integration and generated-personal-cut validation remain unfinished.
