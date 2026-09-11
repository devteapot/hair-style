# Canonical guides and editable revisions

This implements part of M2.1, M2.4 and M2.5: a typed scalp/length/brief input, attached guide curves, geometry checks, two regional edit operations, and immutable local persistence. The [model-guide importer](model-guide-import.md) now connects pretrained template curves to this contract through an explicit, unreviewed personal scalp mapping. Person-conditioned style generation remains unfinished. The original fixture is a synthetic plane with two curved guides.

## Input contract

`HairDesignInput` contains:

| Object | Required content |
|---|---|
| `ScalpProfile` | UUID/revision and subject session; vertices/triangles; per-triangle observed/inferred/synthetic provenance; source hashes and method |
| `HairLengthProfile` | UUID/revision and same subject session; optional regional available lengths with origin, quality, evidence references and method |
| `HairDesignBrief` | UUID, exact scalp/profile hashes, autonomous/guided mode, regional minimum/maximum curve lengths, growth permission, styling assumptions and seed |

Coordinates are meters in the specified canonical head frame: origin at eye midpoint, +X toward anatomical left, +Y up, +Z anterior. Camera-space observed surfaces cannot be inserted without anatomical alignment and a scalp binding surface. This module validates the declared convention and geometry; it does not calculate that alignment or verify the anatomical origin.

Absent regional lengths remain unknown. A missing value must declare `unknown` origin/quality. Values require provenance and evidence references. Inferred/default/low-quality lengths cannot silently become strong current-hair bounds. Evidence references are recorded assertions; this module does not independently verify a user's report or perform a measurement.

The input is intentionally a subset of the full product profile. Hairline, direction, part, density, texture, ear/face surfaces, regional continuity and physical behavior remain to be implemented. Do not interpret omission as permission to invent those properties.

## Haircut contract and validation

`HaircutRevision` records UUID/revision, exact scalp/profile/brief hashes, generation origin/method/version/seed, materials, guide curves and optional parent/edit. Roots bind to a scalp triangle using three nonnegative barycentric weights summing to one and an explicit normal offset. Curve points run root to tip. Root position must match the binding within 0.01 mm (a numerical consistency tolerance, not capture accuracy). Materials have linear RGB, roughness and strand radius.

Regions are fringe, top, crown, anatomical left, anatomical right and nape. Length is measured along the polyline, rather than as straight root-to-tip distance. Validation rejects nonfinite/degenerate geometry, bad references, detached roots, duplicate IDs, missing regional limits, design length violations and conflicts with recorded current lengths when growth is disallowed.

Permitted growth conflicts produce `requires_growth`. Styling assumptions produce `requires_styling`. Reports always retain `uncertain` because collision/clearance, hairline/flow/texture, continuity and physical/personalization checks are unfinished. `publishableAsValidatedDesign` is always false in this version. Passing these geometry checks does not meet M2's complete validation gate or justify `supported_by_observations`.

Limits bound processing to 100,000 scalp vertices, 200,000 triangles, 20,000 guides, 512 points per guide and one million total guide points. Design length bounds are 1 mm–1.5 m. These are provisional engineering limits.

## Edits

Every `HairEdit` references the exact base hash, a region, an operation and its value:

```json
{
  "baseSHA256": "COPY_THE_HASH_FROM_THE_VALIDATION_REPORT",
  "operation": "shorten_to_length",
  "region": "fringe",
  "value": 0.07
}
```

- `shorten_to_length`: absolute polyline length in meters. Preserve the root and existing curve prefix, interpolating a new tip on the segment containing the target distance. Reject requests that would extend any affected guide.
- `scale_lateral_volume`: factor between 0.5 and 1.5. Relative to each root, preserve the displacement along the scalp normal and scale displacement in the tangent plane. This is a geometric volume control, not a physical styling simulation. Revalidate lengths afterward.

The editor preserves all unaffected regions, material data, input references and generation provenance. No-op edits are rejected. A successful edit keeps the haircut UUID, increments revision, retains the parent's exact hash, records the operation and produces a fresh validation report. `verifyTransition` replays the declared edit and compares the complete resulting artifact; unrelated changes cannot pass merely because their geometry remains valid.

## Local history

`HaircutRepository` saves an input/haircut record at `<root>/<haircut UUID>/<haircut SHA256>.json`. It writes a complete temporary file before installing a new record and refuses to replace conflicting existing data. Re-saving identical bytes is idempotent. iOS records use complete file protection and their directories are excluded from backup.

Loading verifies hashes, input bindings and every parent transition back to the original revision. Altering a parent invalidates a descendant's history. Saving an edit requires its parent to exist and its input to match. The repository currently limits history to 128 revisions and individual records to 100 MB.

Two edits from the same base can both be revision 2 with different hashes. The hash is mandatory when addressing a revision. Loading an earlier hash restores that exact result; the repository has no implicit current-selection pointer. The [native guide studio](guide-studio.md) adds a separate local selection/undo layer and synthetic-fixture deletion. Full product/job selection, deletion policy and cloud ownership remain unfinished. Hashes provide integrity, not authentication or authorization.

## Replay on the Mac

```sh
tools/dev.sh swift run capture-inspect hair-fixture outputs/hair-fixture
tools/dev.sh swift run capture-inspect hair-validate \
  outputs/hair-fixture/input.json outputs/hair-fixture/haircut.json outputs/hair-fixture/report.json
# Write edit.json using the report's haircutSHA256 and the format above.
tools/dev.sh swift run capture-inspect hair-edit \
  outputs/hair-fixture/input.json outputs/hair-fixture/haircut.json \
  outputs/hair-fixture/edit.json outputs/hair-fixture/result.json outputs/hair-history
python3 tools/check_haircut.py
```

The edit result JSON contains `haircut`, `validation` and `changedGuideIDs`. For a second edit, use its `haircut` object as the new base and the validation hash as the edit's base hash, retaining the same repository. Swift callers can directly pass the typed result to the next operation. Model adapters can exchange these Codable contracts through JSON.

Tests verify arc-length trimming, exact-vertex trimming, root and untouched-region preservation, volume changes, failed length constraints, uncertain evidence, stale input hashes, malformed bindings, invalid guide geometry, branch persistence, edit replay and corrupted parent rejection. The CLI independently measures edited curves and checks saved hashes/branches. A generated cut on a real participant, rendered comparisons and physical review remain required.
