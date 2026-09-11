# HAAR on Apple Metal: pretrained template generation

The local port now completes pretrained text conditioning, 50-step diffusion and ordered strand decoding on this Apple Silicon Mac using PyTorch MPS, with CPU scalp setup and no MPS fallback. It generated 763 guides from the README's example description, `a woman with short straight hairstyle`. This establishes a working template-generation route. It does not establish person-conditioned design, physical feasibility or an iPhone inference runtime.

## Reproducible environment

The isolated `.research/metal-env` uses Python 3.12 and PyTorch 2.14.0. Installed versions are recorded in `tools/requirements-metal-probe.txt`. HAAR remains at `766a29a9112d84e0b5d512f9b6d7de4f27d3e857`; tracked upstream source was not modified for these probes.

The original SamsungLabs NeuralHaircut submodule URL failed. The [author's repository](https://github.com/Vanessik/NeuralHaircut) contains the exact required commit `1dbdd07797458e6e0000bd3a02f3092d419d1756`, which was checked out using a local submodule URL override. k-diffusion is checked out at its recorded `cc49cf6182284e577e896943f8e29c7c9d1a7f2c` commit. This resolves source availability without substituting a different decoder revision.

## Diffusion-network probe

`tools/probe_haar_metal.py REPO NEW_REPORT.json` constructs the full configured 859,866,624-parameter UNet. It uses seeded random weights and activates otherwise zero output/residual weight matrices to make numerical comparison meaningful. Inputs are 1×64×32×32 with 1×1×768 conditioning, float32.

The CPU forward took 0.250 seconds. Metal forwards took 3.067 seconds initially and 0.079/0.082 seconds after warm-up. Maximum CPU/Metal output difference was 1.70e-6; all outputs were finite. Current MPS tensor allocation was 3.47 GB and driver allocation 4.60 GB after the probe; these are not peak-memory measurements. No trained diffusion checkpoint was used, and these timings are not complete generation latency.

## Pretrained decoder probe

`tools/probe_haar_decoder_metal.py DECODER_REPO CHECKPOINT NEW_REPORT.json` strictly loads the actual decoder weights with `weights_only=True`. The 69,415,611-byte strand-prior checkpoint has SHA-256 `5ef4f673c5992068211ec3fd7738269c987f7e581d40bfcc25d22502d8ade93c` and comes from the public folder linked by the upstream download script.

For 1,024 seeded random 64-dimensional latents, the decoder produces 99 offsets per guide; prepending the root and cumulatively summing gives 100-point local curves. CPU execution took 0.194 seconds; Metal took 0.539 seconds initially and 0.080/0.079 seconds warm. Maximum offset difference was 3.40e-8 and cumulative-curve difference 1.22e-6. All values were finite. Random latent vectors are not a sampled hairstyle, and local curve units/placement remain unresolved.

## Trained generation result

The trained HAAR diffusion archive reports 13,759,277,712 bytes. `tools/extract_haar_ema.py` successfully extracted only its 686 inference EMA tensors (3,439,466,496 tensor bytes), using bounded HTTP ranges and a restricted metadata parser. Every selected ZIP entry passed its original CRC. The resulting safetensors file has SHA-256 `cfeb09abb6febc7af2af563772ce32a937b45e45e96292d88d507ccea627a2e2`. The whole archive SHA-256 was not verified by this selective route. Mocked range-access and synthetic checkpoint tests pass.

`tools/probe_haar_metal.py --checkpoint` strictly loaded these weights and passed the trained forward comparison (maximum absolute difference 1.96e-5). The subsequent connected run used actual BLIP2 text conditioning and actual pretrained weights throughout:

| Stage | CPU | Metal | Result |
|---|---:|---:|---|
| BLIP2 text branch | 0.047 s | 0.797 s first; 0.019–0.021 s warm | Maximum difference 2.86e-6 |
| Full 50-step diffusion, CFG 1.5 | 23.399 s | 8.223 s | Maximum texture difference 3.10e-5; relative L2 difference 5.23e-7 |
| Scalp-bound guide decoding | 0.146 s | 0.782 s first | Maximum coordinate difference 7.71e-7 |

Scalp setup took 6.825 s on CPU. These are stage timings from one example, excluding downloads/model loading; they are not end-to-end product latency or peak-memory measurements. All stage outputs are finite and pass the recorded CPU/MPS tolerances. There are 763 guides with 100 points each. Root positions exactly match the sampled template origins; lengths range from 0.0417 to 0.1901 in unresolved template units.

![Three views of the generated diagnostic guide curves](evidence/haar-metal-template-guides-2026-09-10.png)

The diagnostic renderer intentionally draws guides through the head, so hidden curves remain inspectable. It is not an occlusion-correct or photorealistic preview. The sparse generated guide arrangement is visible in three views; visual inspection does not establish haircut quality or prompt fidelity across a domain.

## Port differences and reproducibility

- Pinned LAVIS Qformer (`ac8fc98c93c02e2dfb727e24a361c4c309c8dbbc`) loads strictly from the official 746,998,955-byte BLIP2 checkpoint. Its SHA-256 is `f31f96e4a97ce9ac7a140ea1961b8a871822ae1cd0a23f0f1122fbefd70db9f0`; the source MD5 also matched. The unused vision encoder is omitted. Transformers 4.44.2 replaces upstream 4.33.2 for Python 3.12 compatibility.
- Caption preprocessing matches the pinned LAVIS processor; the two front/back descriptions are independently encoded, concatenated and token-averaged exactly as in HAAR. It uses hidden states, not the projected normalized BLIP feature.
- The port selects unchanged model-factory, preconditioner, noise-schedule, Euler sampler, scalp-basis and decoder Python definitions from the pinned sources, omitting unused training imports. Source hashes are recorded. The original CUDA CLI has not been run.
- Initial and ancestral noise are generated with CPU seed 42 and shared across CPU/MPS for numerical comparison. The upstream CLI seeds ancestral noise but creates its initial noise earlier. This run is reproducible under the declared port, not claimed to match an unseeded upstream sample.
- The OBJ adapter preserves vertex/face order and computes face normals from winding. UV mapping, the 1,000-subsample root mask, and template placement use the unchanged upstream methods on CPU with root seed 42. No participant geometry enters this run.

With the recorded assets and pinned checkouts present, run with `.research/metal-env/bin/python`:

```sh
tools/haar_text_metal.py .research/HAAR/submodules/LAVIS .research/metal-assets/blip2_pretrained.pth .research/metal-assets/bert-tokenizer outputs/NEW-text
tools/haar_inference_metal.py .research/HAAR .research/metal-assets/ema-only-range/ema.safetensors outputs/NEW-text/condition.safetensors outputs/NEW-trajectory
tools/haar_decode_metal.py .research/HAAR .research/metal-assets/scalp .research/metal-assets/strand_ckpt.pth outputs/NEW-trajectory/texture.safetensors outputs/NEW-guides
tools/verify_haar_metal_run.py outputs/NEW-text outputs/NEW-trajectory outputs/NEW-guides
tools/inspect_haar_output.py outputs/NEW-guides/run.json outputs/NEW-guides/research-strands.json
```

All output destinations must be new. The connected verifier checks stage hashes, numerical-result flags, exact root positions and exact PLY/tensor ordering. The existing adapter emitted 763 ordered research guides and preserves `implementation: metal_inference_port_v1`, unresolved units and `acceptedForPersonalHaircut: false`. Tests rejected a changed conditioning link and corrupted PLY. Caption equivalence, sampler guidance semantics, face winding and serialization tests pass in `tools/check_haar_metal_port.py`.

## Remaining work

A subsequent [mapping experiment](model-guide-import.md) now imports these curves onto the existing inferred personal scalp and exercises two edits. Correspondence and scale are still unreviewed. Condition generation on actual geometry and observed hair properties, resolve scalp clearance, and validate physical feasibility. Compare prompts/seeds and the image-to-strand route rather than relying on this single example. Research dependency/distribution terms still require a complete review before selecting a production model; generating custom output does not remove those dependencies.

The GPU host is unavailable according to the user. No remote GPU was used and no participant data was uploaded. Initial stage results remain in [the earlier verification record](evidence/haar-metal-probes-2026-09-10.json); the connected trained run is in [the current evidence](evidence/haar-metal-generation-2026-09-10.json). The iPhone app and its installed data are unchanged by this research work.
