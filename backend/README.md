# Local job persistence

`job_store.py` provides SQLite transactions for the planned worker/API integration. It is a local persistence component, not a deployed service or an authentication system. All owner arguments must come from a trusted authentication layer; never accept a client's owner string as proof of ownership. `claim`, `checkpoint`, `finish` and purge inspection are privileged worker operations.

The store implements:

- Atomic idempotent submission keyed by session and request key. Reusing a key with different canonical JSON fails. Requests are bounded to 64 KiB and nonfinite JSON is rejected.
- Atomic claiming with an opaque attempt token. A second claimant cannot obtain the same queued job. Reopening the store preserves a running job; it is not automatically requeued or billed again.
- Checkpoint references and explicit stages. These are hashes of artifacts, not arbitrary fetch URLs or commands. The worker must validate and persist the actual artifacts before recording them.
- Results retained under their own job ID. Only the latest requested job can replace the session's selected result. Failed newer work preserves a previously selected result; an older result cannot overwrite a newer selection.
- Immediate publication suppression on cancellation. Running work becomes `cancel_requested`; a late worker completion acknowledges `cancelled` and returns false without publishing its output. This does not kill a model process. The worker must check cancellation, stop computation and discard unpublished artifacts.
- Session tombstones that revoke metadata reads/submission and invalidate active attempts. Existing output/checkpoint references are placed in a durable, session-scoped purge queue before sensitive request/output fields are cleared. A late output is rejected. The worker must delete that late artifact itself. A manual local session purger is described below; backup expiry and scheduled purge execution remain unfinished.

`finish(..., output_hash=...)` records a successful worker result, not an accepted hairstyle. Geometry, feasibility and identity checks belong to the worker's validation stages. Those checks must succeed before an integration marks the job successful. This module does not run HAAR or call another model.

Run the tests locally:

```sh
.research/metal-env/bin/python -m unittest backend.test_job_store -v
```

Three integration tests pass using real SQLite files and separate concurrent connections. They exercise duplicate requests, reopening after claim, stale attempt rejection, out-of-order completions, preservation after failure, owner-scoped access, cancellation, deletion during an attempt and durable purge intents after reopen. No participant evidence or network service is used.

Remaining work includes a versioned migration scheme before existing databases are upgraded, a typed request schema for each real worker, authenticated HTTP/API integration, leases and heartbeat diagnostics, explicit recovery/checkpoint policy, provider usage accounting, bounded retry budgets, content validation, resumable transfers, storage purge execution and native progress/resume UI. Expired worker attempts now use the bounded lease-recovery policy below; retries can repeat compute already spent by an interrupted attempt. The native application does not yet consume this store, and M4/M5 acceptance remains incomplete.

## Local compiler worker

`compile_worker.py` now consumes one queued `compile_hair` request and invokes the existing Swift validator and mesh compiler. This is a real processing adapter for existing canonical haircuts, not a generation worker. Requests have exactly `schemaVersion: 1`, `kind: "compile_hair"`, `inputSHA256` and `haircutSHA256`. Input bytes must already exist at `ARTIFACTS/SESSION/objects/HASH.json`; staging/ownership enforcement for uploads is still pending. Each input is bounded to 100 MB, hash-checked and copied into an attempt-local directory before invoking the fixed trusted inspector executable. Requests cannot select executable names, filesystem paths or external URLs.

```sh
.research/metal-env/bin/python -m backend.compile_worker DATABASE ARTIFACTS \
  --inspector .build/debug/capture-inspect
```

The worker validates canonical source binding and guide constraints, then compiles three-sided tubes at actual material radius (scale 1). It records validation and mesh data together in a hash-bound `result.json`. Intermediate copies are removed before publication. Successful processing still records `personalStyleVerified: false`; existing validation limitations remain intact. A cancelled/deleted attempt cannot publish and its attempt directory is removed. Cancellation is checked between subprocess stages and at publication, not during a running subprocess; each subprocess has a 120-second timeout. Unknown process outcomes are not retried automatically.

A local run compiled the real 763-guide research haircut, verified matching validation/mesh revision hashes, reused its idempotency key without rerunning, reopened the database and rechecked the result's byte hash. This uses the existing unaccepted inferred scalp/fit and does not improve personal styling validity. Participant-derived artifacts remain in ignored local outputs. No uploads occurred.

Six backend tests now pass, including three invoking the real Swift compiler on synthetic fixtures. They check successful output/hash binding, duplicate suppression, corrupted-input rejection, and session deletion injected after compilation but before publication. The latter verifies that the actual compiled result is removed. It does not simulate process termination at every write/transaction boundary. Inputs and prior checkpoints still require the future asset index/purger; a successful metadata tombstone is not proof that all stored files were erased. Successful result lookup by hash also needs an authenticated serving adapter.

## Local artifact access and deletion

`ArtifactStore` supplies owner-checked JSON staging and result reads for this local adapter. Staging authorizes the live session inside the same SQLite transaction as file publication; deleted sessions cannot receive more uploads through this entry point. Results require an authorized successful job, exactly one matching output, a byte-size limit and a matching SHA-256 digest. Corrupt/missing/ambiguous data is rejected rather than served. These are callable backend primitives, not externally exposed HTTP routes or authentication.

`purge_deleted_sessions()` removes each tombstoned session's complete local artifact directory, including input objects that were never referenced by a completed checkpoint. It clears that session's individual purge intents only after directory removal succeeds. Tombstones persist and are swept again on every call, so late residue left by an interrupted trusted worker can be removed on a later sweep. Other sessions retain their own namespace even when content hashes are identical. The configured storage root and worker processes are trusted; symbolic session directories are rejected.

Seven backend tests pass. The real compiler tests now stage through this component, read an authorized result, reject another owner, reject corrupted bytes, revoke access after deletion and verify that the whole session directory is absent after purge. A separate test preserves another owner's identical object and simulates/removes late residue on a repeated sweep. These use synthetic data; participant research outputs were not deleted.

No scheduler, purge deadline, secure erasure, backup expiry or shared/cloud object-store lifecycle is established. Long reads and filesystem operations currently hold a SQLite write transaction, which favors simple serialization over concurrent service throughput. A deployed API needs bounded transfers, authorization credentials, streaming, leases/recovery, storage accounting and scheduled maintenance before consumer use. An already returned byte buffer cannot be recalled by later deletion; no response-stream revocation is implemented.

## Loopback development API

`local_api.py` binds only `127.0.0.1`. It provides guest credentials backed by high-entropy bearer tokens; SQLite stores token hashes, and ownership is resolved from credentials rather than request-supplied owner IDs. Responses disable caching, and default access logging is disabled. Credentials are returned once at guest creation and must be stored securely by a future client. There is no recovery or credential-revocation flow yet.

```sh
.research/metal-env/bin/python -m backend.local_api DATABASE ARTIFACTS --port 8765
```

Development routes:

| Method | Path | Behavior |
|---|---|---|
| POST | `/v1/guests` | Create guest, return bearer token |
| POST | `/v1/sessions` | Create owned session |
| PUT | `/v1/sessions/{id}/objects` | Stage a bounded JSON artifact, return byte hash |
| POST | `/v1/sessions/{id}/jobs` | Submit request with `Idempotency-Key` |
| GET | `/v1/jobs/{id}` | Read owned state without worker token/raw request |
| GET | `/v1/jobs/{id}/result` | Read hash-verified owned output |
| POST | `/v1/jobs/{id}/cancel` | Request cancellation |
| DELETE | `/v1/sessions/{id}` | Revoke access, then attempt local purge |

All routes except guest creation require `Authorization: Bearer …`. Nonexistent and other-owner jobs both return 404; missing/invalid credentials return 401. Most request bodies are limited to 64 KiB; staged objects allow up to 100 MB. Chunked requests are rejected, socket operations have a 10-second timeout, and responses are JSON. Deletion returns access-revoked state even if filesystem cleanup requires a later sweep; it does not promise successful physical erasure. Workers run separately through the trusted CLI. This development subset is not yet the complete product API or resumable upload protocol.

Eight backend tests pass. The HTTP integration test uses a real loopback socket, two guest credentials, staged synthetic canonical artifacts, the real Swift compiler, idempotent submission, owner-isolated result reads, deletion and post-deletion denial. It also reopens SQLite to verify credential persistence without plaintext token storage. The test server shuts down afterward; no permanent service was started and no participant data was transmitted.

Do not expose this standard-library development server publicly. TLS, deployment hardening, quotas/rate limiting, bounded concurrency, credential lifecycle, request versioning/migrations, production error codes and native Keychain/API integration remain unfinished. Tokens travel over plain HTTP on loopback for this local test only. Public/remote backend provisioning is not performed by this implementation.

## Resumable upload protocol

The loopback API also supports sequential chunk uploads of JSON artifacts:

1. `POST /v1/sessions/{id}/uploads` with `{ "sha256": "…", "size": N }` returns an upload ID and committed offset. Repeating the same declaration reuses the upload; a conflicting size fails.
2. `GET /v1/uploads/{id}` reads the persisted offset/status.
3. `PUT /v1/uploads/{id}` sends at most 1 MiB with `Upload-Offset` set to the byte offset. The server requires sequential writes. Retrying previously committed bytes succeeds only if those bytes match exactly; gaps, conflicting retries and overruns fail.
4. `POST /v1/uploads/{id}/complete` verifies total size, full SHA-256 and JSON-object structure before placing the artifact in the worker's object namespace. Finalization is idempotent.
5. `POST /v1/uploads/{id}/reset` discards an unfinished partial and resets its offset for a corrected transfer. A finalized object cannot be reset.

Uploads are capped at 100 MB. Owner checks apply to every operation and deleted sessions cannot continue uploading. Chunk data is flushed/fsynced before its SQLite offset is committed. A tail left before an interrupted database commit is truncated on the next sequential write. Finalization can recover from a rename completed before the SQL flag was committed by verifying the destination object. This is not an exhaustive power-loss durability proof; directory fsync and filesystem-specific crash testing remain outstanding.

Ten backend tests pass. New tests reopen the store midway, retry chunks, reject conflicting bytes, recover an uncommitted tail and pre-commit rename, reject bad final hashes and reset/retry them. The real HTTP/Swift-compiler test now uploads its canonical input in two chunks, retries the first chunk as if its response had been lost, resumes at the reported offset, rejects premature completion and compiles the verified result. This tests protocol primitives, not a physically interrupted iPhone transfer. Native resumable upload state and background-transfer integration remain unfinished, as do abandoned-upload expiry, quotas and production hosting.

## Session request recovery

`POST /v1/sessions` accepts an owner-scoped `Idempotency-Key`. Matching retries return the same active session; a key belonging to a tombstoned session returns 404. Existing databases acquire the nullable creation-key column and unique owner/key index transactionally, preserving legacy sessions. Clients omitting a key retain fresh-session behavior. The native lab persists its UUID key before networking. Repeated owner-authorized DELETE requests acknowledge deletion and repeat the purge sweep without restoring access; another owner still receives 404.

Validation: all 12 backend tests pass, including concurrent creation through separate connections, migration of a legacy database, and HTTP retries. The Swift HTTP probe recreates the client, recovers the same session and job, replays the compiled mesh, retries deletion and rejects resurrection; exactly one compiler invocation was observed. This does not cover guest-creation response loss, native process termination at every persistence boundary, or abandoned-session expiry.

## Local Metal research generation

The worker accepts `generate_haar_template` only when the operator explicitly supplies `--haar-workspace /trusted/workspace`. The request has exactly `schemaVersion: 1`, `kind`, a nonempty description of at most 400 characters and integer seed 0…2147483647. It cannot specify executable or asset paths. Prepared assets and scripts are resolved under the trusted workspace. The existing compile route remains available in the same worker.

This runs the pretrained text, 50-step CPU/MPS comparison, template decoding, connected-stage verifier and ordered-guide adapter. Hugging Face/Transformers offline settings are enabled and local tokenizer files are required; this is not an OS network sandbox. Each subprocess has a 300-second timeout. Active cancellation uses the process supervisor described below. Worker lease recovery is described below.

## Expired worker recovery

Claims now have a 600-second lease and persisted attempt count. Successful checkpoints renew the lease; expired attempts cannot checkpoint or publish, even before recovery runs. Every worker invocation recovers expired active jobs before claiming queued work. Recovery clears the old fencing token and checkpoint and retries from original inputs, with at most three total claims; exhaustion produces `budget_exhausted`. This is a full retry, not resumption from intermediate tensors. Cancellation requests become cancelled after lease expiry and are never retried. Deleted sessions cannot be recovered. Existing running records receive an initial lease based on their recorded update time during schema migration.

Lease duration exceeds the current 300-second model-stage and 120-second compiler timeouts. The one-shot command requires a subsequent invocation; the foreground watcher below supplies recurring idle iterations. No OS-managed service or mid-stage heartbeat is installed. Recovery does not prove the old process has stopped, but its token can no longer publish and each attempt writes to a distinct directory. Orphan cleanup runs on subsequent worker invocations as described below; session deletion removes the whole namespace. Local wall-clock stability and production process supervision remain operational requirements.

All 19 backend tests pass. New coverage includes an actual subprocess that claims and exits abruptly without cleanup, followed by database reopen, expiry recovery and replacement publication. Controlled-clock tests cover live renewal, stale renewal/publication rejection, the three-attempt cap and cancellation without retry. This does not simulate a killed Metal stage or establish production availability.

## Abandoned attempt files

Publication now records its winning attempt token transactionally. Result retrieval for new successes reads only that attempt and verifies its content hash, so a revoked attempt cannot create an ambiguous result by writing identical bytes later. Legacy successes without a publication token retain the earlier hash-discovery path.

Every worker invocation performs abandoned-attempt cleanup after lease recovery. Cleanup serializes with claim/publication, retains live and published attempt directories, and removes other valid attempt directories under known active sessions. Symlinked or malformed paths are rejected and reported. Successful legacy jobs are left intact because their winning directory is unknown. A revoked process may recreate residue, so maintenance must repeat. The foreground watcher below supplies recurring idle sweeps while it remains running; no deletion deadline or OS-managed availability is claimed.

All 20 backend tests pass, including live-attempt preservation, expired-directory removal, late-residue removal, published-byte retrieval despite a duplicate stale result, and conservative legacy retention. Session deletion also clears publication metadata. Cleanup does not delete source objects or alter the retained successful result.

## Active stage cancellation

Compiler and local Metal stages use a shared POSIX process-group supervisor. It checks database ownership of the attempt, running state, active session and unexpired lease before launch and every 100 ms while the process runs. Cancellation, expiry, deletion or timeout sends TERM to the stage group, waits up to two seconds for its leader, then sends KILL to terminate remaining descendants and reaps the leader. Normal return is checked again before the adapter proceeds; existing publication fencing remains in force.

This bounds polling latency under a responsive local database, not worst-case cancellation latency under an overloaded system. A hard-killed supervisor cannot run cleanup; lease recovery still handles its metadata while external process supervision remains needed. No Windows process-tree support or measured live Metal cancellation latency is claimed.

All 23 backend tests pass. Actual-process coverage includes a cancellation written through a separate database connection, timeout termination, nonzero exit propagation, and a descendant that ignores TERM and stops writing after group KILL. The existing real compiler/API tests continue to pass through the supervisor.

`python3 tools/verify_local_generation_cancel.py NEW_OUTPUT_DIRECTORY` exercises the prepared real HAAR pipeline with a generic prompt. It observes the worker's diffusion child, cancels through the job store, then requires cancelled state, child exit, no result files and no remaining attempt directory. The first run reached the diffusion child after 3.118 seconds and the worker exited 0.042 seconds after cancellation. No participant input was used. This verifies stage-start cancellation; GPU kernel execution at that instant was not measured. Private report: `outputs/supervised-haar-cancellation/report.json`.

## Supervised Swift generation round trip

`python3 tools/verify_swift_generation.py NEW_OUTPUT_DIRECTORY` starts a temporary loopback API, runs the built Swift research probe against the actual local Metal worker, and shuts down its server/client afterward. Prepared model assets and built `processing-probe`/`capture-inspect` binaries are required. The request uses a generic prompt, never a participant capture.

Actual replay passed in 43.556 seconds: 763 guides, one claim/publication, Swift source/seed/download checks, idempotent job reuse after client recreation, and session deletion. This exercises the new supervisor, lease columns and exact-publication retrieval together with the existing model pipeline. It is not a consumer personal-generation flow or an accepted haircut. Report: `outputs/supervised-swift-generation/report.json`.

The returned `generated_research_guides` bundle includes ordered curves, the request, actual stage reports/model hashes and wall time. It explicitly records `personalStyleVerified: false`; template units and personal attachment remain unresolved. This is not the native compiled-hair response schema and cannot be displayed through the compiled-result client. Transient tensors/logs are removed after verification; the hash-bound bundle stays in the session namespace and uses existing owner-scoped retrieval/deletion. No face data is needed or uploaded.

A real local run for “short wavy hair with a side part”, seed 43, completed in 45.03 seconds and emitted 763×100-point guides. The result was reopened/hash-checked; duplicate submission returned the same ID and no second job was claimed. Its reconstructed diagnostic preview was visually inspected. All 15 backend tests pass, including fail-closed disabled/invalid requests and cancellation after claim before model loading. Tests do not establish prompt fidelity, personalized generation, accepted fit, full rendering quality, native generation UI or production readiness. Evidence: `outputs/durable-haar-generation/verification.json`.


## Foreground worker loop

Run the local serial worker explicitly with:

```sh
python3 -m backend.watch_worker /absolute/path/jobs.sqlite /absolute/path/artifacts \
  --inspector /absolute/path/capture-inspect --poll-seconds 1
```

`--haar-workspace` retains the same explicit opt-in for prepared local Metal research generation. No model assets or participant captures are uploaded by starting the watcher. This command is a foreground process; no launch agent, scheduler or permanent service is installed automatically.

Each iteration recovers expired leases, sweeps deleted-session namespaces and abandoned attempts, then claims at most one job. Empty queues wait on an interruptible event (configurable 0.1–60 seconds). New jobs are picked up without another command invocation; deleted namespaces are swept again if stale writers recreate residue. Artifact cleanup errors stop the worker before claiming more work instead of silently continuing. Existing one-shot workers now perform deleted-session cleanup too.

SIGINT/SIGTERM request stop after the current iteration/job drains; idle waits wake promptly. This is not immediate active-job cancellation: the owner cancellation path remains available, and jobs retain existing stage timeouts. An in-progress claim may finish after the signal. During a long job this single serial process does not sweep other jobs; additional maintenance scheduling, bounded retention deadlines, restart policy, process-tree handling after hard kill and production service management remain open. Database/filesystem failures exit visibly for operator attention.

All 26 backend tests pass. An actual watcher subprocess starts idle, observes a still-live lease, waits until expiry, recovers and publishes through the real Swift compiler, picks up a later submission, and repeatedly removes deleted-session residue without restart. It rejects the old attempt's publication and exits with code 0 on idle SIGTERM. Additional tests reject non-finite polling before database creation and verify unsafe cleanup fails before claiming while leaving the symlink target untouched. The temporary worker exits after testing; active-job compiler draining is verified below. Metal drain latency and production availability remain unmeasured.


### Stop while a job is active

All 27 backend tests pass. A gated pass-through inspector holds an actual Swift compilation stage open while the watcher receives SIGINT or SIGTERM. In both cases, releasing the gate lets the real validator/compiler finish, its hash-verified output remains retrievable, and the watcher exits with code 0. The queued successor still has zero claims; a later one-shot invocation compiles it successfully. The process emits exactly one started, one job-finished and one stopped event.

This verifies graceful compiler draining and preservation of queued work for both signals. It does not measure whole-model drain time, force-killed worker cleanup, remote interruption or an external service manager's shutdown deadline. No persistent worker remains running after the tests.

## Durable personal-generation preparation

`compile_worker.py` also accepts `prepare_personal_generation`, implemented in `personal_preparation.py`. The request has exactly `schemaVersion: 1`, `kind`, `inputSHA256`, `preparedBriefSHA256`, `mappingSHA256`, and `anatomySHA256`. These reference existing JSON objects in the requesting session; request data cannot select paths, executables or remote resources. Each input is capped at 25 MB and rehashed before use.

This stage replays `brief-consume` against the source input, then runs the canonical attachment preflight with a 0.05 mm material radius and the supplied anatomy margin (at least 1 mm, at most 20 mm). These bounds match the current research guide radius; a later generator using another radius must check it again. Stale briefs, malformed requests, changed object bytes and invalid anatomy fail before any model execution. The existing active-attempt supervisor and publication token enforce cancellation/lease fencing; transient snapshots are removed.

The `personal_generation_preparation` result contains the source request, exact consumed `generationInputData` as base64, its SHA-256, the complete root preflight, `attachmentsReady`, and explicit `modelExecuted: false` / `personalStyleVerified: false`. A root-conflict report is a completed review result with `attachmentsReady: false`, not a generated haircut. The result preserves missing-region warnings. Model/source correspondence, generated curve clearance, natural hair evidence and physical styling feasibility remain later checks. No neural job is automatically enqueued and no native consumer-generation screen is connected yet.

Actual local participant replay under `outputs/durable-personal-preparation/` returns zero conflicts for the refined mapping and six for the original mapping; both lack the two ear surfaces. Exact prepared bytes and output hashes were verified, duplicate submission reused each job, and no further job was claimed. No model or external service was invoked. Backend tests cover real Swift replay, the review outcome, owner-scoped retrieval, stale briefs, invalid requests/margins, and cancellation before publication.

All 31 backend tests pass after this addition. This is preparation-stage coverage; it does not close the end-to-end personal generation gate.

## Swift verification of personal preparation

`ProcessingClient.submitPersonalPreparation` and `personalPreparationResult` now support the preparation protocol. `PersonalPreparationInputs` binds all four uploaded byte sequences. The result verifier checks the published byte hash and request identities, decodes the exact prepared bytes, replays the saved brief against its original input, and independently recomputes the complete attachment report at the same radius/margin. Changed inputs, fabricated readiness, removed missing-region warnings, and model/style acceptance claims are rejected even when an attacker recomputes the outer result hash.

`python3 tools/verify_swift_preparation.py INPUT_DIRECTORY NEW_OUTPUT_DIRECTORY` runs a temporary loopback API, the real worker and the Swift probe, then shuts them down. The input directory must contain `input.json`, `brief.json`, `mapping.json`, and `anatomy.json`. The helper does not invoke a model or use an external endpoint. The underlying CLI is `processing-probe http://127.0.0.1:PORT OUTPUT.json --preparation INPUT_DIRECTORY`.

Both actual participant cases pass through upload, session/client recreation, idempotent job reuse, download, local replay and deletion. The refined mapping returns zero conflicts in 6.079 seconds; the original mapping returns a review result with six conflicts in 5.665 seconds. Each has exactly one claim/publication and retains both missing-ear warnings. Reports remain local in `outputs/swift-personal-preparation/` and `outputs/swift-personal-preparation-review/`. All 141 core tests and the unsigned iPhone build pass. This establishes the client/preparation protocol, not a native consumer generation screen or a generated design.

## Durable conditioning of a local model sample

With the existing explicit `--haar-workspace` opt-in, the worker now accepts `condition_personal_sample`. Its exact request fields are `schemaVersion: 1`, `kind`, `inputSHA256`, `preparedBriefSHA256`, `mappingSHA256`, `anatomySHA256`, `preparationSHA256`, and `modelSampleSHA256`. The five personal JSON artifacts must exist in the requesting session's object namespace. They are size-limited and hash-checked before use; the pipeline independently replays the full preparation contract before loading the model.

The sample hash identifies a locally provisioned directory at `.research/conditioning-samples/<modelSampleSHA256>/` in the configured workspace. It contains `source.json`, `texture.safetensors`, and `trajectory-report.json`. The source file's SHA-256 must equal the directory/request hash, and the sampler report must bind the exact texture. Requests never contain executable or filesystem paths. Samples are explicitly installed local model artifacts, not user uploads, and this protocol does not create a new sample from preferences.

The existing supervised process runner executes the complete offline conditioning pipeline under the job's attempt token. Cancellation/expiry revokes its process group; publication is fenced by the same token. The final `conditioned_personal_research` response contains the exact model source bytes as base64, canonical input/mapping/haircut, validation, actual-radius mesh, clearance and pipeline report. Preserving raw source bytes is necessary because source correspondence is bound to their file hash. Output is capped at 100 MB, retains review failures and missing anatomy, and always sets personal/style acceptance false. Temporary tensors/logs are removed after assembly; the session-scoped result uses ordinary retrieval and deletion.

An actual participant run completed in 64.236 seconds with one attempt and a 61,393,815-byte response. Native package replay of its returned source/input/mapping succeeds for all 763 guides. The expected 328 segment intersections on 24 guides and two missing ears remain visible. Duplicate submission reused the job, another owner could not retrieve the result, and session deletion removed its artifact files. Evidence is under `outputs/durable-personal-conditioning/`.

A separate cancellation test observed a live optimization-script process, cancelled its job, and verified process exit and removal of attempt artifacts. Worker return followed cancellation by 0.0392 seconds; no result was published. This is process-stage cancellation evidence, not GPU-kernel timing. See `outputs/durable-personal-conditioning-cancel/`.

All 34 backend tests pass, including new opt-in/schema, sample-tampering, foreign-object and cancellation-boundary cases. The new boundary tests stub model execution; the actual Metal run and process-cancellation evidence above are separate. Native request/result integration and fresh brief-driven model sampling remain outstanding. No permanent worker or external service was installed.

## Swift verification of personal conditioning

`PersonalConditioningInputs` binds the four original preparation inputs, the exact published preparation bytes/hash and the selected sample hash. It replays preparation and requires conflict-free supplied-surface attachments plus a matching sample/source mapping before creating a conditioning request. `ProcessingClient` supports submission, verified result retrieval and extraction of conditioning inputs from an existing preparation job. The latter retains original result bytes rather than re-encoding a decoded object with a different hash.

`ProcessingConditioningResult.verify` checks the outer byte hash/request, replays the saved brief, preserves the original mapping geometry and bounds, verifies the conditioned source's sample binding, and independently reruns canonical import, validation, actual-radius mesh compilation and complete supplied-anatomy clearance. Returned artifacts must match those local results. A valid response may still contain face intersections or missing ears; verification preserves that review outcome and never establishes model-computation authenticity, anatomical completeness or styling quality.

All 144 core tests pass. New synthetic contract tests retain missing-ear warnings, preserve a real curve-conflict outcome with clear roots, and reject rehashed mesh changes, mapping-bound changes, altered input/source bytes, fabricated clean clearance and unsupported acceptance claims. The unsigned iPhone build passes.

An actual one-job Swift/API test completed in 73.96 seconds. It uploaded the participant inputs, recreated the client/session, reused the job, downloaded and independently replayed all 763 guides and the 230,426-vertex mesh, retained the 328 intersections and two missing ear regions, then deleted the session and verified artifact removal. Evidence is in `outputs/swift-personal-conditioning/`.

The current `python3 tools/verify_swift_conditioning.py INPUT_DIRECTORY NEW_OUTPUT_DIRECTORY` additionally exercises preparation as a preceding durable job. The input directory retains the five preparation files plus `conditioning-context.json` containing the expected preparation and model-sample hashes. The Swift probe obtains the new preparation's published bytes through the client, uploads them unchanged, and submits conditioning; the helper expects exactly two publications with one attempt each. It starts a temporary loopback API and explicitly enabled local model worker, then shuts the service down. The CLI is `processing-probe http://127.0.0.1:PORT OUTPUT.json --conditioning INPUT_DIRECTORY`. Native screen integration and fresh brief-driven sampling remain open.

The actual two-job chain passes in 82.646 seconds: two publications, one attempt per job, preserved published preparation bytes, idempotent reuse of both jobs/session after client recreation, full Swift geometry/clearance replay and deletion of all session artifacts. The 763-guide result still carries 328 segment intersections and both missing ear regions. Evidence is in `outputs/swift-personal-conditioning-chain/`; the temporary API has shut down.

## Fitted conditioning delivery and offline replay

The conditioning worker now publishes the optional verified direction-fit record
with the selected mesh while retaining the original source import. See
[integrated fitting](../docs/integrated-direction-fitting.md). Both conditioning
and ordinary compilation preserve Swift JSON negative zero during assembly;
numeric equality alone is insufficient to establish canonical mesh identity.
A real compiler regression uses an axis-aligned guide and compares every mesh
scalar encoding with the independently compiled reference.

The existing `verify_swift_conditioning.py` helper now retains the downloaded
result and its verification inputs in the excluded output directory, deletes the
service session, closes the client, and independently replays the cache. Set
`requireDirectionFit: true` in `conditioning-context.json` to require the fitted
branch rather than silently accept an unfitted fallback. An optional
`scalp-review.json` in the input directory also exercises creation of a standalone
review package after service deletion. The output directory must be under the
workspace's ignored `outputs/` tree because these retained files contain personal
geometry. They are separate local copies; service deletion does not erase them.

```sh
caffeinate -i python3 tools/verify_swift_conditioning.py \
  outputs/PRIVATE_INPUT_DIRECTORY outputs/NEW_PRIVATE_OUTPUT_DIRECTORY
```

`caffeinate` prevents idle sleep only while this macOS verification command runs.
It does not extend worker leases or suppress cancellation/deletion.

The fitted two-job Swift run passes in 134.82 seconds with exactly two
publications and one attempt per job. The client preserves the published
preparation bytes, reuses both jobs/session after recreation, verifies all 763
guides and 230,426 mesh vertices, then replays the cached result and produces a
review package after service deletion. Six declared direction corrections are
present; supplied-face root/segment conflicts are zero, both ears remain missing,
and acceptance is false. Evidence is in
`outputs/swift-fitted-conditioning-delivery/`. The temporary service is stopped
and its session artifact directory is empty; separate local caches remain.

An independent loopback check also verifies chunk retries, owner-only access,
byte-exact download and deletion for the fitted result in 111.74 seconds. Its
first attempt expired its lease without publication during a wall-clock versus
monotonic-time discontinuity; the cause of that discontinuity was not established.
That failed attempt is retained in the evidence rather than counted as a success.
A direct diagnostic run and the subsequent queue retry completed. These are
individual development runs, not a reliability or latency benchmark. Evidence is
under `outputs/queued-direction-fit/` and `outputs/queued-direction-fit-retry/`.
All 35 backend tests pass, and the updated native probe builds successfully.
