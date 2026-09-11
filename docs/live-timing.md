# Live preview timing instrumentation

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
