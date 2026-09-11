# Regeneration with inferred root offsets

The canonical attachment format already supports normal offsets, and the native
preparation flow retains selected root bindings. However, the local decoder
optimizer and conditioned-curve exporter previously rejected every nonzero
offset. A candidate with the inferred scalp corrections therefore could not
complete this regeneration path.

Both stages now use `tools/scalp_attachments.py`: barycentric triangle position
plus the recorded offset along the normalized triangle normal. It follows the
Swift attachment contract, including weight, index, degeneracy and 0–10 mm offset
validation. Swift preparation preflight and final canonical import remain
authoritative. The optimizer converts the replayed roots to float32 for Metal;
the exporter independently replays them in float64. Reports include the helper's
hash and nonzero-offset count. No offset is relabeled as a measured hair root.

## Verification

Three unit tests cover nonzero/zero offsets, winding, rigid coordinate changes and
invalid bindings. On all 763 actual selected bindings, Python root replay matches
the canonical candidate to 2.78 × 10⁻¹⁷ m per component. Re-exporting the earlier
zero-offset run gives exactly unchanged guide records and materials.

A new local preparation envelope snapshots the selected attachments, including
the six inferred corrections, and passes canonical preflight. The complete local
Metal conditioning run finishes preparation, full-field optimization, regional
repair, canonical export and mesh compilation. Every binding survives unchanged;
optimization and regional tensor roots remain bit-identical, and exported roots
match the selected candidate to 6.94 × 10⁻¹⁸ m per component. This reconditions an
existing model sample, not a new text-to-hairstyle sample or validated style choice.

The six offset guides clear the supplied face. The regenerated decoder curves
lose earlier direction adjustments on six other guides (579, 606, 607, 630, 631,
655), leaving 68 segment conflicts. The pipeline correctly reports those conflicts
and does not mark the export accepted.

A separate bounded canonical direction-fitting pass clears those remaining
conflicts with 5–20° root-fixed rotations. Independent replay confirms unchanged
roots, preserved pairwise curve distances (maximum error 3.21 × 10⁻¹⁷ m), all
regional length bounds and at most 16.892 mm movement from the original mapped
decode, within the existing 20 mm limit. The other 757 guide records are unchanged.
The fitted candidate has zero root and segment conflicts against the supplied
face. A self-contained native review package replays successfully with the new
source import and this declared fitted revision.

The final research hash is
`e16eb5d071be4e543e8274ec0da62152939df67ec7107b2cec361fc8364e9700`.
Private artifacts are in `outputs/normal-offset-regeneration-preparation/`,
`outputs/normal-offset-regeneration/` and `outputs/zero-offset-export-regression/`.
The review package is `fitted-model-review.json`. No phone install, selected app
revision change, network model service or raw-capture upload was performed.

## Remaining integration

The native result contract now accepts an optional `directionFit` record. It
retains the original sample bytes and declared per-guide rotations, binds the
conditioned import by canonical hash, and replays those edits exactly. Verification
rejects changed attachments, undeclared edits, rotation of unaffected guides,
angles beyond 20 degrees, and cumulative movement beyond 20 mm from the original
mapped sample. It recomputes canonical validation, mesh and supplied-anatomy
clearance. Existing results without a fit retain their original import path.

`capture-inspect conditioning-fit-verify` successfully replays the six recorded
rotations on this private regenerated candidate. Two synthetic tests exercise
replay and tampering rejection, including cumulative movement from the original
sample. All 169 core tests and the unsigned iOS device build pass. This verifies
the fit verifier and build compatibility. The subsequent complete saved-result
handoff is documented in the integration report below.

The worker now runs the bounded post-export search automatically and retains both
the original export and the fitted artifacts. Clear exports skip it; root
conflicts or oversized searches remain unsupported; unresolved searches retain
the original result. A proposed passing fit must replay before compilation and
selection. Verification failures fail the job rather than publish an unchecked
fit. See [integrated fitting](integrated-direction-fitting.md) for the complete
saved-result handoff and transport regression evidence. Both ears, inferred scalp
accuracy, actual growth locations, physical fit and aesthetic suitability remain
unverified; acceptance remains false.
