# HAAR research worker

`tools/haar_worker.py` prepares an evidence record and optionally invokes the pinned official inference program. It does not download dependencies, install packages, provision compute, convert a generic result into a personal haircut, or approve research assets for distribution.

Use Python from a prepared Linux/CUDA HAAR environment:

```sh
python tools/haar_worker.py /path/to/HAAR /new/output/directory
python tools/haar_worker.py /path/to/HAAR /another/new/output/directory \
  --run --seed 42 --prompt 'short wavy hair with a side part'
```

The default configuration is `configs/infer.json`. Override with `--config` and `--checkpoint`, using explicit paths. The output directory must not exist. Reports include the source revision, submodule revisions, local asset hashes, interpreter/platform, available CUDA hardware, prompt, seed and exact invocation. Missing assets or dependencies prevent inference and return exit code 2. Preflight readiness means an attempt is possible, not that every transitive dependency has been proven compatible.

The runner sets Python, NumPy and Torch RNGs before upstream model/dataset creation and disables cuDNN benchmarking. Upstream only seeds its sampler after constructing initial noise. This wrapper fixes that gap without editing research source. Bitwise determinism across CUDA versions and devices is not promised and needs repeated real runs.

Inference stdout/stderr go to `inference.log`. `run.json` is written before execution, so an interrupted process does not appear successful. A zero exit plus a nonempty expected PLY records `inferenceCompleted`; it does **not** establish valid strand geometry. The output hash allows subsequent validation to refer to the exact artifact. Upstream emits 100 consecutive points per guide, in its own scalp coordinates. Import must validate order, finite coordinates, units, source scalp registration, personal root bindings and the haircut constraints before the app can use it.

Weights loaded by upstream use Python/Torch serialization; only separately verified research assets should enter this environment. Some upstream loaders may fetch model dependencies on an actual inference attempt; network isolation and a fully populated model cache remain worker-deployment work.

## Local evidence

On 2026-09-10, the preflight found the pinned checkout but rejected execution because model/scalp assets, submodules and Python dependencies were missing. No inference ran. The fail-closed and output-preservation checks are recorded in [worker evidence](evidence/haar-worker-2026-09-10.json).

Next: prepare an existing compatible worker, verify asset sources/hashes, reproduce and inspect an official guide output, then implement personal conditioning and conversion. A text-only HAAR sample does not satisfy personalized generation.

## Durable Metal adapter

The original CUDA preflight above is retained as historical evidence. The prepared Mac now also runs pretrained generation through the durable local job store using `backend/haar_generation.py`; see [the Metal job route](../backend/README.md#local-metal-research-generation). A real seed-43 run completed with 763 ordered template guides and duplicate-request reuse. This remains a research template output, not a personal haircut.
