#!/usr/bin/env python3
"""Run HAAR's pinned inference functions on CPU and MPS with identical noise.

Selects unchanged Python definitions from upstream to avoid importing unused
CUDA/training dependencies. This is a local port, not the unmodified CLI.
"""
import argparse
import ast
from functools import partial
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from types import SimpleNamespace
from haar_text_metal import sha256
from haar_worker import REVISION

K_REVISION = 'cc49cf6182284e577e896943f8e29c7c9d1a7f2c'


def verify_repo(repo, revision):
    actual = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != revision:
        raise ValueError('Unexpected upstream revision')
    if subprocess.check_output(['git', '-C', str(repo), 'status', '--porcelain', '--untracked-files=no'], text=True).strip():
        raise ValueError('Tracked upstream source was modified')


def definitions(path, names, namespace):
    tree = ast.parse(Path(path).read_text(), filename=str(path))
    selected = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in names]
    if {node.name for node in selected} != set(names):
        raise ValueError('Missing required upstream definitions')
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(path), 'exec'), namespace)
    return namespace


def runtime(repo):
    import torch
    from tqdm.auto import trange
    repo = Path(repo).resolve()
    verify_repo(repo, REVISION)
    k_repo = repo / 'submodules/k-diffusion'
    verify_repo(k_repo, K_REVISION)
    sys.path.insert(0, str(repo / 'src'))
    from openaimodel import UNetModel
    paths = dict(utils=k_repo / 'k_diffusion/utils.py', sampling=k_repo / 'k_diffusion/sampling.py',
                 layers=repo / 'src/utils/layers.py', factory=repo / 'src/utils/config.py', sampler=repo / 'src/sampler.py')
    utility = definitions(paths['utils'], ['append_dims'], {'torch': torch})
    utils = SimpleNamespace(append_dims=utility['append_dims'])
    sampling = definitions(paths['sampling'], ['append_zero', 'get_sigmas_karras', 'get_ancestral_step', 'to_d', 'default_noise_sampler'], {'torch': torch, 'utils': utils})
    layers = definitions(paths['layers'], ['Denoiser'], {'torch': torch, 'nn': torch.nn, 'utils': utils})
    factory = definitions(paths['factory'], ['make_model', 'make_denoiser_wrapper'], {
        'UNetModel': UNetModel, 'partial': partial, 'layers': SimpleNamespace(Denoiser=layers['Denoiser'])})
    sampler = definitions(paths['sampler'], ['sample_euler_ancestral'], {
        **sampling, 'torch': torch, 'trange': trange})
    return SimpleNamespace(make_model=factory['make_model'], make_denoiser_wrapper=factory['make_denoiser_wrapper'],
        sample=sampler['sample_euler_ancestral'], sigmas=sampling['get_sigmas_karras'],
        sourceHashes={name: sha256(path) for name, path in paths.items()})


def sample_with_shared_noise(rt, model, config, condition, seed, device, steps, cfg_scale):
    import torch
    generator = torch.Generator(device='cpu').manual_seed(seed)
    shape = (1, config['model']['input_channels'], *config['model']['input_size'])
    # Deliberately generate on CPU for identical noise across the two backends.
    # Upstream CLI's initial noise is not seeded by its --seed argument.
    initial = torch.randn(shape, generator=generator).to(device) * config['model']['sigma_max']
    sigmas = rt.sigmas(steps, config['model']['sigma_min'], config['model']['sigma_max'], rho=7., device=device)
    noise_generator = torch.Generator(device='cpu').manual_seed(seed)
    def noise_sampler(sigma, sigma_next):
        return torch.randn(shape, generator=noise_generator).to(device)
    trace = []
    def callback(state):
        denoised = state['denoised']
        if not bool(torch.isfinite(denoised).all()):
            raise ValueError('Nonfinite denoising trajectory')
        trace.append(dict(step=state['i'], sigma=float(state['sigma']), maximumAbsolute=float(denoised.abs().max())))
    start = time.perf_counter()
    with torch.inference_mode():
        result = rt.sample(model, initial, sigmas, extra_args={
            'cross_cond': condition.to(device), 'cross_cond_zero': torch.zeros_like(condition).to(device)},
            cfg_scale=cfg_scale, noise_sampler=noise_sampler, callback=callback, disable=True, seed=None)
    if device == 'mps':
        torch.mps.synchronize()
    elapsed = time.perf_counter() - start
    if not bool(torch.isfinite(result).all()):
        raise ValueError('Nonfinite final texture')
    return result.cpu(), elapsed, trace


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path)
    parser.add_argument('checkpoint', type=Path)
    parser.add_argument('condition', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--steps', type=int, default=50)
    parser.add_argument('--cfg-scale', type=float, default=1.5)
    args = parser.parse_args()
    import torch
    from safetensors.torch import load_file, save_file
    if not 2 <= args.steps <= 100 or not 0 <= args.cfg_scale <= 5:
        raise ValueError('Invalid sampling parameters')
    if os.environ.get('PYTORCH_ENABLE_MPS_FALLBACK') not in (None, '0'):
        raise ValueError('Disable CPU fallback')
    if not torch.backends.mps.is_available():
        raise RuntimeError('Metal unavailable')
    args.output.mkdir(parents=True, exist_ok=False)
    torch.set_num_threads(4)
    rt = runtime(args.repo)
    config_path = args.repo / 'configs/infer.json'
    config = json.loads(config_path.read_text())
    config['dataset']['num_classes'] = 0  # Same default as upstream load_config.
    if config['model']['type'] != 'openai' or config['model']['loss_config'] != 'karras' or config['model']['has_variance']:
        raise ValueError('This port supports only the pinned inference architecture')
    inner = rt.make_model(config).eval()
    inner.load_state_dict(load_file(str(args.checkpoint)), strict=True, assign=True)
    model = rt.make_denoiser_wrapper(config)(inner).eval()
    condition = load_file(str(args.condition))['cross_cond']
    if condition.shape != (1, 1, 768) or condition.dtype != torch.float32 or not bool(torch.isfinite(condition).all()):
        raise ValueError('Invalid conditioning tensor')
    print('Running complete CPU trajectory', flush=True)
    cpu, cpu_time, cpu_trace = sample_with_shared_noise(rt, model, config, condition, args.seed, 'cpu', args.steps, args.cfg_scale)
    print('Running complete Metal trajectory', flush=True)
    model.to('mps')
    metal, metal_time, metal_trace = sample_with_shared_noise(rt, model, config, condition, args.seed, 'mps', args.steps, args.cfg_scale)
    difference = (cpu - metal).abs()
    save_file({'texture': metal.contiguous()}, str(args.output / 'texture.safetensors'))
    save_file({'texture': cpu.contiguous()}, str(args.output / 'texture-cpu.safetensors'))
    report = dict(method='haar_pretrained_50_step_cpu_mps_v1', modelRevision=REVISION, kDiffusionRevision=K_REVISION,
        sourceHashes=rt.sourceHashes, configSHA256=sha256(config_path), checkpointSHA256=sha256(args.checkpoint),
        conditionSHA256=sha256(args.condition), seed=args.seed, steps=args.steps, cfgScale=args.cfg_scale,
        cpuSeconds=cpu_time, mpsSeconds=metal_time, cpuTrace=cpu_trace, mpsTrace=metal_trace,
        maximumAbsoluteDifference=float(difference.max()), meanAbsoluteDifference=float(difference.mean()),
        relativeL2Difference=float(torch.linalg.vector_norm(cpu-metal) / torch.linalg.vector_norm(cpu).clamp_min(1e-12)),
        allCloseAt1e4Absolute1e3Relative=bool(torch.allclose(cpu, metal, atol=1e-4, rtol=1e-3)), allFinite=True,
        cpuFallbackEnabled=False, latentTextureGenerated=True, strandsGenerated=False, personalized=False,
        textureSHA256=sha256(args.output / 'texture.safetensors'),
        notes=['Uses unchanged selected upstream Python definitions; unused training imports omitted.',
               'Initial and ancestral noise generated on CPU to compare identical trajectories.',
               'Generic text prompt only. Scalp decoding and personalized design are not verified here.'])
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ('cpuTrace','mpsTrace')}, indent=2))


if __name__ == '__main__':
    main()
