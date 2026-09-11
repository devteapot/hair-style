#!/usr/bin/env python3
"""Fresh local HAAR sampling from a verified prepared brief; no personal fit claim."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
NAMES = {'fringe':'fringe', 'top':'top', 'crown':'crown',
         'anatomical_left':'left side', 'anatomical_right':'right side', 'nape':'nape'}


def description_for(prepared):
    # Only explicit requests become text. Broad default representational bounds
    # are not a recommended style, and unknown texture/gender are never invented.
    requested = {r['region'] for r in prepared['request']['lengthRanges']}
    limits = {r['region']:r for r in prepared['compiled']['input']['brief']['lengthLimits']}
    parts = []
    for region, name in NAMES.items():
        if region in requested:
            limit = limits[region]
            parts.append(f"{name} {round(limit['minimumMeters']*1000)} to {round(limit['maximumMeters']*1000)} millimeters")
    return 'a hairstyle' + (' with ' + ', '.join(parts) if parts else '')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('preparation',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--preparation-output-sha256',required=True)
    args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False,mode=0o700)
    inputs=out/'inputs';inputs.mkdir(mode=0o700)
    report=dict(schemaVersion=1,method='prepared_brief_fresh_sample_v1',status='running',stages=[],
                acceptedForPersonalHaircut=False,personalStyleVerified=False)
    env=dict(os.environ,HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',HF_DATASETS_OFFLINE='1',PYTORCH_ENABLE_MPS_FALLBACK='0')
    def invoke(name,cmd):
        with (out/(name+'.log')).open('w') as log:
            p=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=300)
        report['stages'].append(dict(name=name,exitCode=p.returncode))
        if p.returncode: raise RuntimeError(name+' failed; inspect retained log')
    try:
        for name in ['source-input.json','prepared-brief.json','mapping.json','anatomy.json','preparation-result.json']:
            path=args.preparation/name
            if path.stat().st_size>100_000_000:raise ValueError('Preparation input exceeds byte limit')
            data=path.read_bytes()
            if len(data)>100_000_000:raise ValueError('Preparation input grew beyond byte limit')
            (inputs/name).write_bytes(data)
        invoke('verify-preparation',[ROOT/'.build/debug/capture-inspect','preparation-consume',inputs/'preparation-result.json',
            args.preparation_output_sha256,inputs/'source-input.json',inputs/'prepared-brief.json',inputs/'mapping.json',inputs/'anatomy.json',out/'prepared-input.json'])
        prepared=json.loads((inputs/'prepared-brief.json').read_text());description=description_for(prepared)
        for prefix in ['From frontal view image depicts ','From back view image depicts ']:
            if len((prefix+description).split())>50:raise ValueError('Prompt would be truncated by the model caption processor')
        report.update(description=description,seed=prepared['request']['seed'],
                      preparationOutputSHA256=args.preparation_output_sha256,
                      preparedBriefFileSHA256=hashlib.sha256((inputs/'prepared-brief.json').read_bytes()).hexdigest(),
                      explicitLengthRegions=len(prepared['request']['lengthRanges']),
                      limitations=['Text conditioning is soft and numeric length compliance is unproven.',
                                   'Text rounds requested applied lengths to millimeters; exact constraints remain in the prepared brief.',
                                   'Styling effort, products, heat tools and natural texture preferences are not encoded by this adapter.',
                                   'Without explicit length requests this is generic fresh sampling, not an autonomous style recommendation.',
                                   'Template guides require new mapping, personal fitting and full validation before use.'])
        (out/'sampling-plan.json').write_text(json.dumps(report,indent=2))
        python=ROOT/'.research/metal-env/bin/python';tools=ROOT/'tools';repo=ROOT/'.research/HAAR';assets=ROOT/'.research/metal-assets'
        invoke('text',[python,tools/'haar_text_metal.py',repo/'submodules/LAVIS',assets/'blip2_pretrained.pth',assets/'bert-tokenizer',out/'text','--description',description])
        invoke('trajectory',[python,tools/'haar_inference_metal.py',repo,assets/'ema-only-range/ema.safetensors',out/'text/condition.safetensors',out/'trajectory','--seed',report['seed']])
        invoke('decode',[python,tools/'haar_decode_metal.py',repo,assets/'scalp',assets/'strand_ckpt.pth',out/'trajectory/texture.safetensors',out/'guides'])
        invoke('verify-model',[python,tools/'verify_haar_metal_run.py',out/'text',out/'trajectory',out/'guides'])
        invoke('export-source',[python,tools/'inspect_haar_output.py',out/'guides/run.json',out/'guides/research-strands.json'])
        report.update(status='fresh_template_sample_requires_personal_fit',sourceSHA256=hashlib.sha256((out/'guides/research-strands.json').read_bytes()).hexdigest())
    except Exception as error:
        report.update(status='failed',failure=str(error));raise
    finally:
        (out/'report.json').write_text(json.dumps(report,indent=2))


if __name__=='__main__':main()
