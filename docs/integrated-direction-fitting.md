# Integrated post-conditioning direction fitting

The local generation pipeline now follows canonical export with a bounded
root-fixed rotation search when 1–128 guides conflict with supplied anatomy and
their attachments already clear it. The search uses the existing diagonal-axis
candidates and ±20 degree bound. It cannot change attachments, repair missing
anatomy, or establish hairstyle feasibility.

Original export files remain intact. Separate `direction-fit` artifacts contain
the proposal, exact fitted haircut, declared rotation record, original sample
bytes, replay verification, and compiled mesh. The final pipeline report names
both the original and selected revisions. The worker assembles the fitted result
only when these identities and the selected mesh file hash agree. Native loading
reimports the conditioned source, replays the declared rotations, checks the
20 mm cumulative movement bound from the original model sample, and recomputes
the validation, mesh, and supplied-anatomy clearance.

Clear exports skip the search. Unsupported or unresolved searches retain the
original research result and its conflicts. A claimed passing proposal that fails
independent verification fails the job; previous saved results remain available.
Neither branch claims physical acceptance or verified style.

## Transport regression

The complete handoff exposed a signed-zero bug that standalone verification did
not catch. Swift encoded one mesh normal component as `-0`; Python's default JSON
integer parser converted it to positive `0`. The reconstructed canonical mesh
then failed exact hash replay. `tools/canonical_json.py` preserves this spelling
as negative floating-point zero while keeping all other integers exact, including
large seeds. Both proposal reading and worker assembly use it. This fixes the
transport without relaxing geometry or mesh verification.

Tests cover signed zero and large integers, skip/unsupported cases, unresolved
searches, rejection before compilation when verification fails, original versus
selected identity, and worker cancellation. Physical-device and visual styling
evaluation remain separate gates.

## Local integration evidence

The final offline Metal run completed all eight stages in 99.82 seconds on the
development Mac. This is one local sample, not a latency percentile or phone
performance measurement. Worker result assembly produced a 72,886,231-byte
research result. `conditioning-review-package` successfully verified that complete
result and produced its self-contained native review package.

Six guides received declared rotations; the other 757 records were unchanged.
All attachment bindings and root positions were preserved. Supplied-face checks
reported zero root and segment conflicts, with both ears still missing. Maximum
cumulative movement from the original mapped sample was 16.892 mm. The selected
canonical revision hash is
`9965c3f7b9307fb3bfe76b809048b9bf154d875b2a220a6bdc8751a2191d86b2`.

Rehashed result copies with a changed rotation or a 1 mm mesh-vertex change were
rejected by the complete native handoff. Validation also passed 169 Swift tests,
35 backend tests, four focused Python helper tests, and an unsigned iOS device
build. No phone installation or new camera session was performed.

Private artifacts are under `outputs/integrated-direction-fit-final/`; the
transport failure, repaired replay and tampering evidence are retained under
`outputs/integrated-direction-fit/`. Neither is committed. This run exercised the
actual pipeline, worker assembly and native saved-result replay locally; it does
not establish remote queue delivery, device UI runtime, physical accuracy, or
styling quality. Acceptance remains false, and broader milestone gates remain
open.
