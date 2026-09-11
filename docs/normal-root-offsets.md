# Inferred normal offsets and face clearance

The current face and inferred scalp disagree locally at the six remaining
conflicting roots. The nearest observed surface lies 1.06–1.92 mm from those
roots. Its root-side separating direction has a dot product of −0.919 to −0.993
with the inferred scalp's outward normal. This supports a local scalp/face mismatch
hypothesis; it does not determine the true skull surface or measured hairline.

The previous attachment searches projected candidates back onto the inferred
scalp with zero normal offset. Larger root-side bending trials do not resolve this:
18 candidates at a 45° segment cap still collide, while all 18 at 90° fail the
inferred-envelope bound. A close-up of the distance-optimized curve confirms a
surface crossing near its root. Repeated unsigned-distance minimization cannot be
treated as proof that a curve stays on the root's side of an open surface.

`tools/probe_normal_root_offsets.py INPUT MAPPING SOURCE HAIRCUT ANATOMY OUTPUT`
tests explicit **inferred attachment offsets**, from 0.25 to 4 mm in 0.25 mm steps
along each bound scalp triangle's normal. This adds a degree of freedom absent
from the surface-only searches; it is not a measured scalp correction. The existing
contract permits nonzero offsets, but the experiment retains the smaller 4 mm
additional root-movement limit. It preserves each curve through rigid translation
and records the offset in its canonical root binding. The source-correction limit,
20 mm cumulative curve-movement limit, inferred envelope and anatomical margins
remain unchanged. New close root coincidences are rejected, including after
combining independently selected candidates.

## Actual result

All 96 candidates were checked against the supplied anatomy. The smallest clear
sample for each guide uses these additional offsets:

| Guide | Inferred offset |
|---|---:|
| 632 | 2.75 mm |
| 633 | 2.50 mm |
| 656 | 3.25 mm |
| 657 | 2.25 mm |
| 678 | 2.75 mm |
| 679 | 2.50 mm |

Full canonical replay of the combined 763-guide research candidate reports **zero
root violations and zero segment conflicts against the supplied face**, compared
with 68 segment conflicts before this change. The other 757 guide records are
identical. Independent checks confirm:

- Maximum additional root movement: 3.25 mm.
- Pairwise within-curve distance discrepancy: at most 1.74 × 10⁻¹⁷ m.
- All regional length bounds retained.
- Maximum movement from the original decoded mapping: 16.892 mm, below 20 mm.
- Attachment replay error: at most 3.11 × 10⁻¹⁷ m; final root-neighbor bounds pass.

Three unit tests verify translation/shape preservation, binding provenance,
coordinate-change equivariance and invalid-input rejection. The self-contained
native review package also replays successfully through `model-review-check`,
including its source import, scalp/face correspondence, canonical haircut and mesh.
Front/profile/rear renders of both compiled revisions were inspected. They remain
sparse guide diagnostics with 8× enlarged radii; they do not demonstrate realistic
hair appearance or density.

Local artifacts are under ignored `outputs/normal-root-offsets/`; candidate hash
`5e29cc5b7d56e2e46634a5ad11a7bb57bd036047d5b2b478bec9db966ec8a19c`.
The package is `model-review.json`, with its inferred-offset explanation retained.
No phone installation or selected native-studio revision was changed.

## Remaining limitations

Both ears are still missing from supplied anatomy. The observed face and inferred
head shape, actual growth locations, hairline, neighboring growth flow and physical
fit remain unverified. Offsets can bridge a mismatch in the head estimate; a
collision-free result does not validate that estimate. Acceptance remains false.
The next integration should expose this correction as inferred and preserve the
source evidence while improving the scalp/face fit, rather than silently describing
these roots as measured attachments.
