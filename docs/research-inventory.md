# Generation and reconstruction research inventory

Updated: 2026-09-10. Official repositories and pretrained assets are in ignored `.research/` paths. The HAAR Metal port now produces template-bound research guides. No subject images were downloaded/uploaded and no third-party install script was executed.

## HAAR

- Official repository: [Vanessik/HAAR](https://github.com/Vanessik/HAAR).
- Inspected revision: `766a29a9112d84e0b5d512f9b6d7de4f27d3e857`.
- Role: candidate text-conditioned guide/strand generation. Its image workflow derives a description before generation; this does not itself guarantee matching personal anatomy.
- The repository describes Linux and an NVIDIA A100 40 GB as its tested environment. Its environment pins Python 3.9, PyTorch 1.13 and CUDA-related dependencies. `infer.py` contains a direct `.cuda()` call even though an earlier device selection mentions CPU.
- Weights/data are referenced by `scripts/download.sh` from Google Drive folders. The needed EMA weights, decoder, scalp and UV assets have now been fetched with sizes/hashes recorded in the Metal evidence.
- `LICENSE.txt` states CC BY-NC 4.0; the README describes scientific research use. Dependencies and weights require a separate complete inventory before distribution.
- Status: the unchanged official CUDA CLI has not been reproduced. A separately evaluated CPU/MPS port now completes the README's example description through 763 ordered template guides, with CPU/Metal agreement. See [the port and its differences](haar-metal-port.md). Person-conditioned design remains unimplemented.

Sources: [README at inspected revision](https://github.com/Vanessik/HAAR/blob/766a29a9112d84e0b5d512f9b6d7de4f27d3e857/README.md), [license](https://github.com/Vanessik/HAAR/blob/766a29a9112d84e0b5d512f9b6d7de4f27d3e857/LICENSE.txt), [inference entry point](https://github.com/Vanessik/HAAR/blob/766a29a9112d84e0b5d512f9b6d7de4f27d3e857/infer.py).

## Gaussian Haircut

- Official repository: [eth-ait/GaussianHaircut](https://github.com/eth-ait/GaussianHaircut).
- Inspected revision: `c18714ddfb799029f7cd8f53984dfdd978e87ee8`.
- Role: candidate reconstruction of existing strands/appearance from monocular video. New haircut design and person-conditioned constraints remain separate work.
- The README specifies CUDA 11.8 and Blender 3.6. The installer creates multiple environments and installs compiled GPU dependencies. Runtime and GPU-memory requirements on our captures are unmeasured.
- `LICENSE.md` states CC BY-NC-SA 4.0. The README additionally references underlying 3D Gaussian Splatting terms. The dependency/license inventory is incomplete.
- Status: source inspected; official example **not reproduced**. No input video or CUDA worker has been established for this project.

Sources: [README at inspected revision](https://github.com/eth-ait/GaussianHaircut/blob/c18714ddfb799029f7cd8f53984dfdd978e87ee8/README.md), [license](https://github.com/eth-ait/GaussianHaircut/blob/c18714ddfb799029f7cd8f53984dfdd978e87ee8/LICENSE.md), [installer](https://github.com/eth-ait/GaussianHaircut/blob/c18714ddfb799029f7cd8f53984dfdd978e87ee8/install.sh).

## Newer candidates checked

### HairGPT

The [official project page](https://haiminluo.github.io/hairgpt/) describes text/image-conditioned autoregressive generation of regional strand tokens and editing. This is a relevant alternative to diffusion-based guides. On 2026-09-10 its Code and Data links returned to the project page rather than exposing a downloadable implementation. No runnable release, weights, runtime requirements or distribution terms were verified. Keep it as a research candidate, not the implementation dependency.

### Large reconstruction and multimodal models

The [August 2026 paper](https://arxiv.org/html/2608.13679v1) describes image-to-hair-surface reconstruction, multimodal direction/region guidance, orientation diffusion and strand tracing. This supports evaluating an image-to-strand route. It does not demonstrate that a generated cut respects a particular person's measured hairline, available length or growth pattern; those remain our conditioning and validation responsibilities. The inspected paper did not establish a downloadable implementation or weights. Its reported results are not reproduced locally.

## Selection decision

Retain HAAR as the first source-available reproduction candidate, Gaussian Haircut as an existing-hair reconstruction experiment, and the newer methods as alternatives pending usable releases. Do not make image generation or Gaussian rendering the authoritative haircut representation. All candidates must export ordered, scalp-bound guides into the same personal haircut contract before either preview consumes them.

The CUDA worker remains unavailable. Local Apple Silicon portability is now demonstrated for the connected pretrained template-generation route, including explicit CPU mesh setup and verified MPS neural stages.

## Next evaluations

1. Extend the verified Metal template-generation route to person-conditioned design, resolving template correspondence, geometry constraints and observed hair inputs.
2. Resolve distribution terms for the intended preview, including all model assets and transitive dependencies.
3. Reproduce an official example with pinned inputs, model checksums, hardware, runtime and exported guides.
4. Compare direct generation and image-to-strand output on the same personal head using the implementation plan's constraints and personalization experiment.
5. Recheck release availability for HairGPT and the newer multimodal strand-generation paper before selecting either as a runnable dependency.

The HAAR output is now connected to [native model review](native-model-review.md) through a guarded inferred-scalp mapping. This verifies review/edit integration, not the required person-conditioned generation milestone.

The separate [HAAR worker](haar-worker.md) records the original CUDA reproduction attempt. That preflight remains distinct from the successful Metal port; it does not establish an available remote GPU.
## Spatial capture follow-up

User-requested later experiment: assess iPhone spatial capture as a supplementary stereo source. Apple documents in-app spatial video capture on iPhone 15 Pro in [WWDC24: Build compelling spatial photo and video experiences](https://developer.apple.com/videos/play/wwdc2024/10166/). Before choosing it for metric reconstruction, verify decoded dual-view access, synchronization, camera calibration/baseline, stabilization/cropping effects, compatibility with depth capture, and measured close-range reconstruction quality. No spatial capture is currently implemented or included in the existing RGB/depth bundles. This investigation should complement the current LiDAR/TrueDepth work, not imply that a spatial playback file is already a calibrated head scan.

## Apple Object Capture reconstruction

The native Mac PhotogrammetrySession route now runs locally on the recorded rear RGB/depth capture and emits a textured USDZ plus estimated camera poses. This is a reconstruction route, not a hair-generation model. See [the implementation and physical findings](object-capture-reconstruction.md). Scale, front-detail registration and measured/inferred geometry provenance remain unvalidated.

## CUDA versus Metal clarification

CUDA was proposed for running the published HAAR pretrained inference example (text conditioning → latent hair texture → ordered strands), not for iPhone capture, editing, rendering, or training a new model. CUDA is a constraint of that inspected implementation, not a demonstrated requirement of this product. The configured dev-box SSH check timed out; the user confirmed it is unavailable for now. No remote GPU run or participant upload occurred.

A Mac/Metal port remains a candidate. Source inspection finds hardcoded `.cuda()` allocations in inference and dataset setup, plus PyTorch3D mesh loading/normal calculation and training-side nearest-neighbor imports. Porting must separate inference-only operations, replace or move unsupported mesh operations to CPU, verify numerical behavior, and measure memory/runtime with actual weights. We have not established that Metal lacks sufficient compute or that changing a device string would suffice. PyTorch exposes Apple GPU acceleration through its [MPS backend](https://docs.pytorch.org/docs/2.14/notes/mps.html).

The ordered-output adapter (`tools/inspect_haar_output.py`) checks the pinned run and PLY hashes, preserves the decoder's 100-point root-to-tip guide order, and emits research strands with unresolved units and no personal-haircut acceptance. Synthetic binary/ASCII, corruption, point order and integrity checks pass. It now also accepts the verified Metal port manifest, preserves its implementation label, and has converted the real generated guides.

Metal follow-up: the full pretrained text → diffusion → template-guide route now runs on this Mac. The 50-step diffusion stage took 8.223 seconds on MPS, and all neural stages passed CPU/MPS numerical comparisons with fallback disabled. See [verification and remaining personal-design work](haar-metal-port.md). This supersedes earlier stage-only findings; it does not complete M0's comparison/license gates or M2's personalization requirement.

## Face parsing follow-up

[Local SegFormer face parsing](face-segmentation.md) is evaluated for observed skin/ear masks at pinned revision `758b82e15a0178c9db39c1ff666a8b56e3a550c8`. Its 338.6 MB safetensors checkpoint runs on Metal and CPU with identical labels in the comparison trial. The author specifies research/educational use; it is not a commercially cleared product dependency. Eight existing frames and five-frame reconstruction replay are recorded separately from semantic accuracy and head acceptance.
