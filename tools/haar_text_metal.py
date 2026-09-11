#!/usr/bin/env python3
"""HAAR's pretrained BLIP2 text conditioning without its unused vision encoder.

Uses the pinned LAVIS Qformer source and checkpoint. It does not generate hair.
Caption preprocessing follows LAVIS BlipCaptionProcessor (BSD-3-Clause).
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import time

LAVIS_REVISION = 'ac8fc98c93c02e2dfb727e24a361c4c309c8dbbc'


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def caption_processor(caption):
    caption = re.sub(r'([.!"()*#:;~])', ' ', caption.lower())
    caption = re.sub(r'\s{2,}', ' ', caption).rstrip('\n').strip(' ')
    return ' '.join(caption.split(' ')[:50])


def load_text_model(repo, checkpoint, tokenizer_path):
    import torch
    from transformers import BertConfig, BertTokenizer
    repo = Path(repo).resolve()
    revision = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != LAVIS_REVISION:
        raise ValueError('Unexpected LAVIS revision')
    source = repo / 'lavis/models/blip2_models/Qformer.py'
    spec = importlib.util.spec_from_file_location('haar_lavis_qformer', source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    tokenizer = BertTokenizer.from_pretrained(str(tokenizer_path), local_files_only=True)
    tokenizer.add_special_tokens({'bos_token': '[DEC]'})
    config = BertConfig.from_pretrained(str(tokenizer_path), local_files_only=True)
    config.encoder_width = 1408  # EVA ViT-G width in upstream pretrain config.
    config.add_cross_attention = True
    config.cross_attention_freq = 2
    config.query_length = 32
    config.vocab_size = len(tokenizer)
    model = module.BertLMHeadModel(config).eval()
    state = torch.load(checkpoint, map_location='cpu', weights_only=True)['model']
    qformer_state = {key[len('Qformer.'):]: value for key, value in state.items() if key.startswith('Qformer.')}
    # Strict loading prevents a partially initialized language model from being
    # reported as a valid reproduction of upstream text conditioning.
    model.load_state_dict(qformer_state, strict=True)
    return model, tokenizer, sha256(source)


def embed_description(model, tokenizer, description, device):
    import torch
    descriptions = [caption_processor(prefix + description) for prefix in (
        'From frontal view image depicts ', 'From back view image depicts ')]
    embeddings = []
    with torch.inference_mode():
        # Upstream processes each description separately, then averages all
        # tokens including CLS/SEP, without a projection or normalization.
        for text in descriptions:
            inputs = tokenizer([text], return_tensors='pt', padding=True).to(device)
            output = model.bert(inputs.input_ids, attention_mask=inputs.attention_mask, return_dict=True)
            embeddings.append(output.last_hidden_state[0])
        result = torch.cat(embeddings, dim=0).mean(0, keepdim=True)[None]
    if result.shape != (1, 1, 768) or not bool(torch.isfinite(result).all()):
        raise ValueError('Invalid text conditioning')
    return result, descriptions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path)
    parser.add_argument('checkpoint', type=Path)
    parser.add_argument('tokenizer', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--description', default='a woman with short straight hairstyle')
    args = parser.parse_args()
    import torch
    import transformers
    from safetensors.torch import save_file
    if os.environ.get('PYTORCH_ENABLE_MPS_FALLBACK') not in (None, '0'):
        raise ValueError('Disable CPU fallback')
    if not torch.backends.mps.is_available():
        raise RuntimeError('Metal unavailable')
    args.output.mkdir(parents=True, exist_ok=False)
    torch.set_num_threads(4)
    model, tokenizer, source_hash = load_text_model(args.repo, args.checkpoint, args.tokenizer)
    start = time.perf_counter()
    cpu, processed = embed_description(model, tokenizer, args.description, 'cpu')
    cpu_time = time.perf_counter() - start
    model.to('mps')
    timings = []
    for _ in range(3):
        torch.mps.synchronize()
        start = time.perf_counter()
        metal, _ = embed_description(model, tokenizer, args.description, 'mps')
        torch.mps.synchronize()
        timings.append(time.perf_counter() - start)
    observed = metal.cpu()
    difference = (cpu - observed).abs()
    agreement = bool(torch.allclose(cpu, observed, atol=1e-4, rtol=1e-3))
    report = dict(method='haar_blip2_text_only_cpu_mps_v1', lavisRevision=LAVIS_REVISION,
        qformerSourceSHA256=source_hash, checkpointSHA256=sha256(args.checkpoint),
        tokenizerFiles={p.name: sha256(p) for p in sorted(args.tokenizer.iterdir()) if p.is_file()},
        torchVersion=torch.__version__, transformersVersion=transformers.__version__,
        description=args.description, processedDescriptions=processed, shape=list(cpu.shape),
        cpuSeconds=cpu_time, mpsSeconds=timings, maximumAbsoluteDifference=float(difference.max()),
        meanAbsoluteDifference=float(difference.mean()), allFinite=bool(torch.isfinite(observed).all()),
        allCloseAt1e4Absolute1e3Relative=agreement, cpuFallbackEnabled=False,
        pretrainedInferenceCompleted=False, strandsGenerated=False,
        notes=['Strictly loaded full Qformer state; unused vision encoder omitted.',
               'Transformers 4.44.2 replaces upstream 4.33.2 for Python 3.12 compatibility.',
               'This verifies text conditioning only, not a complete hairstyle or personal design.'])
    if agreement:
        save_file({'cross_cond': observed.contiguous()}, str(args.output / 'condition.safetensors'))
        report['conditionSHA256'] = sha256(args.output / 'condition.safetensors')
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    if not agreement:
        raise ValueError('Text CPU/Metal numerical agreement failed')


if __name__ == '__main__':
    main()
