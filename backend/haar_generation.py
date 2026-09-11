"""Local research generation adapter. Produces template guides, not a personal haircut."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from .worker_process import run_stage


def generate(store, attempt, work, workspace):
    request = attempt['request']; job = attempt['id']; token = attempt['token']
    if (set(request) != {'schemaVersion', 'kind', 'description', 'seed'}
            or request['schemaVersion'] != 1 or request['kind'] != 'generate_haar_template'
            or not isinstance(request['description'], str)
            or not 1 <= len(request['description'].strip()) <= 400
            or any(ord(c) < 32 for c in request['description'])
            or type(request['seed']) is not int or not 0 <= request['seed'] <= 2**31-1):
        raise ValueError('Invalid research generation request')
    base = Path(workspace).resolve()
    python = base/'.research/metal-env/bin/python'
    repo = base/'.research/HAAR'; assets = base/'.research/metal-assets'
    tools = base/'tools'; work = work.resolve()
    work.mkdir(parents=True, exist_ok=False, mode=0o700)
    environment = dict(os.environ, HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1',
                       HF_DATASETS_OFFLINE='1', PYTORCH_ENABLE_MPS_FALLBACK='0')
    started = time.monotonic()
    checkpoint = hashlib.sha256(json.dumps(request, sort_keys=True).encode()).hexdigest()

    def invoke(script, arguments, stage):
        if not store.checkpoint(job, token, stage, checkpoint):
            store.finish(job, token, failure_code='generation_failed')
            return False
        # Trusted script paths; prompt is passed as one argument, never evaluated by a shell.
        with (work/(script+'.log')).open('wb') as log:
            code = run_stage([str(python), str(tools/script), *map(str, arguments)],
                cwd=base, env=environment, stdout=log, timeout=300,
                active=lambda:store.attempt_active(job,token))
        if code:
            raise RuntimeError('Research generation stage failed')
        return True

    stages = [
        ('haar_text_metal.py', [repo/'submodules/LAVIS', assets/'blip2_pretrained.pth',
            assets/'bert-tokenizer', work/'text', '--description', request['description']], 'generating'),
        ('haar_inference_metal.py', [repo, assets/'ema-only-range/ema.safetensors',
            work/'text/condition.safetensors', work/'trajectory', '--seed', request['seed']], 'generating'),
        ('haar_decode_metal.py', [repo, assets/'scalp', assets/'strand_ckpt.pth',
            work/'trajectory/texture.safetensors', work/'guides'], 'generating'),
        ('verify_haar_metal_run.py', [work/'text', work/'trajectory', work/'guides'], 'validating'),
        ('inspect_haar_output.py', [work/'guides/run.json', work/'guides/research-strands.json'], 'validating')]
    for script, arguments, stage in stages:
        if not invoke(script, arguments, stage):
            return dict(job=job, published=False, cancelled=True)
    guides = json.loads((work/'guides/research-strands.json').read_text())
    if (guides['acceptedForPersonalHaircut'] is not False or guides['strandCount'] < 1
            or type(guides.get('samplingSeed')) is not int or guides['samplingSeed'] != request['seed']):
        raise ValueError('Research output contract mismatch')
    output = dict(schemaVersion=1, kind='generated_research_guides', request=request,
        guides=guides, stageReports={name: json.loads((work/name/'report.json').read_text())
            for name in ('text', 'trajectory', 'guides')},
        wallSeconds=time.monotonic()-started, personalStyleVerified=False)
    encoded = json.dumps(output, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
    digest = hashlib.sha256(encoded).hexdigest()
    (work/'result.tmp').write_bytes(encoded); (work/'result.tmp').replace(work/'result.json')
    # The returned bundle retains actual model/source hashes, numerical checks and ordered guides.
    # Transient tensors/logs are unnecessary for retrieval and do not escape the session namespace.
    for child in work.iterdir():
        if child.name != 'result.json':
            if child.is_dir(): shutil.rmtree(child)
            else: child.unlink()
    published = store.finish(job, token, output_hash=digest)
    return dict(job=job, published=published, outputSHA256=digest if published else None)
