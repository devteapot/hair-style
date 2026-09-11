# Fresh sampling from a prepared brief

`tools/create_prepared_model_sample.py PREPARATION_DIRECTORY NEW_OUTPUT --preparation-output-sha256 HASH` snapshots bounded local inputs, invokes Swift preparation replay, builds a deterministic text-conditioning description, and runs the existing pinned text, diffusion, decoder, cross-stage verification and ordered-source exporter. Use `.research/metal-env/bin/python`. No downloads, service publication or phone changes occur.

Only explicitly requested regional lengths appear in the description. Values come from the **applied** compiled limits, after availability constraints, and are rounded to millimeters for text. Exact limits remain in the retained brief. All six regions fit within the model's 50-word preprocessing budget including its view prefix; oversized text is rejected before model execution. Request order does not change region order. Unknown texture, gender and preferences are not invented. Product/heat/styling-time preferences are retained in the original brief but are not encoded by this adapter.

The model's response to numerical descriptions is unproven: this is soft conditioning, not geometric enforcement. Without explicit length requests the text is simply `a hairstyle`, explicitly recorded as generic sampling rather than an autonomous recommendation. The new template needs its own source mapping, personal conditioning and geometry checks. It is not inserted into the old sample's catalog or represented as already fitted.

The corrected complete run is retained in ignored `outputs/prepared-fresh-sample-v2/`. All six stages pass, producing 763 ordered guides with seed 42 and source SHA-256 `2406e05a41d6004ced8716f686697d77d660ba531a70a3fa961fb5fc041e3f5d`. Cross-stage verification checks text/texture/strand hashes, CPU/MPS agreement, root order and PLY serialization. This actual prepared brief has no explicit ranges, so no learned preference compliance or personalized output is established. No visual quality assessment has been performed on this new sample.

Three prompt-adapter tests pass: unknown/default handling, clipped applied limits, and all-region truncation/order bounds. An actual wrong preparation hash fails at `verify-preparation` with no text/model directory (`outputs/prepared-fresh-sample-rejected/`). The first complete model run reached verification but exposed an omitted source-export step; it is retained as failed in `outputs/prepared-fresh-sample/`, and the corrected command was rerun in a new directory successfully.

This is a foreground research runner. Durable job integration, cancellation of its full process tree, fresh-sample mapping, explicit-preference model comparisons, native generation selection and personal/style validation remain open. The existing durable conditioning flow continues using its provisioned original sample.


## Controlled numeric length response

`tools/compare_prepared_length_sampling.py PREPARATION NEW_OUTPUT` creates local experimental preparation envelopes for two guided requests, independently replays them through Swift, then runs fresh sampling for each. The person input, source mapping, anatomy, and sampling seed 42 are held fixed; only the fringe range changes (40–60 mm versus 100–140 mm). These are test preferences, not participant-selected preferences. Both preparations pass 763 root checks with two missing ear regions, and both full model runs pass their stage verification.

`tools/analyze_prepared_length_sampling.py OUTPUT` compares decoded guides before any trimming, projection or personal fitting, using the same retained provisional affine scale. Template roots are identical between samples. Results in `outputs/prepared-length-comparison/comparison.json`:

| Requested fringe | Provisional median | In range / 146 | Below / above |
|---|---:|---:|---:|
| 40–60 mm | 47.53 mm | 126 | 14 / 6 |
| 100–140 mm | 48.27 mm | 0 | 146 / 0 |

Only 57 paired guides become longer; median paired change is −0.684 mm. The marginal medians and paired median are different statistics. The inspected `length-response.png` plots both distributions against requested ranges. These values are under a provisional mapping, not calibrated physical hair measurements. One paired seed does not characterize general model behavior, but it directly contradicts using this numeric text adapter as a reliable length-control mechanism for this case.

Next integration must enforce exact regional lengths in geometry conditioning and reject unmet constraints. Text may still supply a style prior, but neither numeric prompt compliance nor complete personal design is established. The experiment does not replace the source hairstyle, modify attachment limits, or publish candidates into the app.


## Explicit length constraints in decoder fitting

`probe_personal_latent_constraint.py --length-constraints` adds regional arc-length violations to the decoder latent objective. Guides activate when either length or the existing inferred-envelope check fails; other latents stay fixed. The existing ±0.25 latent trust region, 200 iterations, fixed roots and pretrained decoder weights remain unchanged. CPU/MPS gradients are compared before optimization. Reports retain initial/final lengths and exact per-guide bounds. This option is experimental. It is now enabled in both stages of the existing worker pipeline, which still consumes its provisioned model sample; fresh sampling is not yet integrated into native submission.

The regional donor-interpolation search has the same explicit option and rejects a mismatch with the preceding optimization's mode. With it enabled, both donor/candidate selection and completion checks retain length bounds as well as the envelope and 20 mm candidate movement bound. The actual mismatched-mode test rejects without producing candidate tensors.

Experiments use the fresh short/long samples from the controlled comparison, with source hashes rebound to those actual samples and unchanged scalp attachments. The short optimization reduces length failures from 20 to one and clears envelope failures. Regional interpolation resolves guide 738 using a 0.25 blend with same-region donor 753. The independently replayed final tensors have zero length failures, exactly unchanged roots and maximum point movement 16.892 mm.

A complete rerun through verified local preparation snapshots and canonical export succeeds under `outputs/fresh-length-constraints/short-verified*` and `short-export/`. Canonical revision `b02a7109ee8478d568b83ae6ad16a50d93ad436616a74e50f0f81bfc459a632b` contains 763 guides. Independent double-precision arc lengths from its exported JSON place all 146 fringe guides between **40.026 and 59.671 mm**, within the requested 40–60 mm. Whole-curve face clearance still reports **134 segments on 12 guides**, with no root conflicts and two missing ears. It remains unaccepted research geometry. No native candidate was replaced.

The long optimization reduces length failures only from 146 to 144; maximum unmet length is 53.735 mm. It keeps roots fixed but moves points up to 38.333 mm, exceeding the existing 20 mm candidate bound. No long result is accepted or exported as compliant. Both runs pass the CPU/MPS gradient comparison. Independent float64 tensor checks are implemented in `tools/verify_latent_lengths.py` and retained beside the outputs. This establishes a constrained short-length candidate, not a general solution for arbitrary lengths, natural style coherence or physical feasibility. Face-clearance optimization and full fresh-sample/native integration remain necessary.


## Worker integration and fixed-root clearance follow-up

`run_prepared_personal_generation.py` now passes `--length-constraints` to both optimization and regional interpolation and records that mode in its final report. An actual complete run on the provisioned original sample finishes in 65.72 seconds (`outputs/length-aware-pipeline/`), with the mode verified in both stages and zero final length failures. This autonomous brief has broad bounds; its existing 24-guide/328-segment face conflicts remain. All 34 backend tests pass. This exercises the actual runner called by the worker, not a new native UI or fresh-sampling submission flow.

Separately, the fresh 40–60 mm candidate was checked with the existing 104-orientation fixed-root search. It clears guides 579 and 606; ten guides retain 126 conflicting segments. Maximum additional point movement is 2.248 mm, all roots are exactly unchanged, and maximum pairwise within-guide distance discrepancy is 2.61e−17 m. All fringe lengths remain within the requested range. Independent full canonical/anatomy replay matches the proposal report exactly. The source, proposal, extracted haircut and independent checks remain in `outputs/fresh-length-rotation/`. Unaffected guide records are unchanged, and no rotation result is accepted for personal use. Further root/head fitting and possibly new decoder shape constraints remain required.


## Bounded attachment follow-up on the fresh short candidate

A current read-only phone inventory still lists nine captures; no new dense front pass was available for reconstruction. The remaining short-candidate curve conflicts include first-segment failures on guides 607, 657 and 679.

The existing joint attachment/direction probe clears guide 607 at the second shortlisted attachment: 3.993 mm root displacement, 11.663 mm maximum point displacement, and 4.327 mm source-root correction. All 762 other guide records remain unchanged. Independent pairwise curve-distance error is below 2.09e−17 m and all fringe lengths remain 40–60 mm. Full replay leaves 113 segments on nine guides (`outputs/fresh-length-joint-607/`). This is an inferred attachment proposal, not a measured hairline correction.

`tools/probe_remaining_joint_conflicts.py` applies the same per-guide bounds sequentially, preserving failed guides and retaining each report. The batch under `outputs/fresh-length-joint-remaining/` has completed; final combined checks are recorded below. `tools/verify_joint_batch_geometry.py` checks root/curve/length invariants and cumulative movement from the original decoded sample, which may exceed a single-stage movement limit even when each stage passes separately.


The nine-target batch completed in 919.48 seconds. Guides 630, 631 and 655 clear at their third shortlisted root, supplementing the earlier guide 607 correction. Guides 632, 633, 656, 657, 678 and 679 exhaust all 16 shortlisted roots without a valid correction and remain unchanged. The final full clearance replay matches the retained report exactly: **68 segment intersections on six guides**, no root violations and two missing ear regions. This finite-search failure does not establish that no alternative curve or attachment can fit.

Independent geometry checks find six changed guide records versus the canonical short export (including the two earlier fixed-root rotations) and 757 unchanged records. Maximum root movement is 3.99996 mm. Pairwise curve-distance error is below 4.34e−17 m and all regional lengths remain within their exact limits. Maximum point movement is 15.127 mm from canonical export and 16.892 mm from the original fresh decoded sample, so the combined result remains within 20 mm as well as each stage's separate bound. These checks are in `independent-check.json`; they do not validate neighbor continuity, growth directions or physical hairline placement.

A self-contained research review package also replays successfully, retaining the original fresh conditioned source and the declared fitted revision `eb216018693b91a699aa247d3472dfb922c7ef3c07b0746ef2fb057e16f15a41`. It contains 763 guides and 8,979 observed face vertices. The package remains unaccepted and was not installed or promoted into a native studio. No new capture or phone camera session was triggered. Further decoder shape constraints and better head evidence remain necessary.
