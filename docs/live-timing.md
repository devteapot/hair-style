# Live preview timing instrumentation

The report now also includes optional `rendererCallbacks` from SceneKit's
`didRenderScene` callback. Each camera run owns a separate locked recorder;
stopping detaches its delegate and ignores any later callbacks. The renderer
trace is bound to the same haircut hash as the display-link report. Older
display-link-only exports still decode without this optional field.

Renderer telemetry records callback intervals and normalized thermal states,
with a default limit of 36,000 retained intervals. Callback count, thermal
counts, long-interval count, and observation duration continue across overflow;
median and p95 fields explicitly describe retained samples. The mean callback
rate is an event rate, not achieved display FPS. GPU completion, presentation,
and sustained-performance verification remain false.

The simulator-only `--render-timing-test` path renders a synthetic inspection
scene without requesting camera access. Its report carries the explicit
`synthetic_inspection` context; normal live runs use `live_camera`. This avoids
mistaking synthetic callback evidence for physical camera performance.

Validation: 153 core tests pass, including invalid timestamps, bounded retention,
complete overflow counters, and old/new export round trips. The unsigned iPhone
build passes. A native simulator UI test recorded 180 callbacks over 2.983
seconds and prepared the actual JSON export. Independent inspection confirms
179 positive intervals, matching haircut identities, correct event/count
arithmetic, zero camera frames, and explicit unverified performance status.
Local artifacts are under `outputs/native-render-timing/`. A five-minute
physical run, GPU/presentation measurements, thermal behavior, and the minimum
device performance gate remain unverified. No phone install or camera activation
was performed for this change.

The native live preview records a bounded display-link trace from camera start to stop. After stopping, choose **Prepare timing export**, then **Share timing report**. Preparing the JSON file is local and does not transmit anything. Exports use protected temporary files; a subsequent export or camera run removes the previous export file held by that screen. Shared copies are outside the app's control. The report is not a persisted capture artifact and is not restored after relaunch.

The report binds to the exact haircut hash and records:

- Monotonic elapsed time and intervals between display-link callbacks.
- Whether a new AR camera frame arrived since the prior callback.
- Overlay state, or null before calibration.
- System thermal state.
- Nearest-rank median/p95 callback interval, count above 40 ms, camera-arrival count, total duration and omitted telemetry sample count.

It excludes images, face landmarks, transforms and participant identifiers. The asset hash is still a link to the reviewed artifact and should be handled as session-related metadata.

The recorder retains at most 36,000 intervals. Later samples increment an omission counter while duration continues; statistics cover retained intervals only. Invalid/nonmonotonic timestamps are ignored. The first callback establishes the clock origin and produces no interval. The display link runs on the main actor; callback delivery includes scheduling effects. Telemetry allocation itself may add overhead and needs measurement on hardware.

**These are not GPU completion times, actual rendered frame counts or measured dropped render frames.** The report cannot alone establish the plan's sustained FPS, memory, stationary jitter or drift targets. It deliberately leaves `sustainedPerformanceVerified` false. Separate renderer/GPU instrumentation, device identification, OS/build details, aligned reference landmarks and a documented five-minute scenario are still required. Multiple-face tracking capacity and the chosen mesh size must be reported with device results.

Validation: all 116 core tests and the unsigned iPhone SDK build pass. Tests verify interval statistics, camera-arrival counts, bounded storage, long-interval counts, invalid timestamp rejection and explicit unverified status. No physical timing run or export interaction was executed; the phone camera remains off.
