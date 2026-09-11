#!/usr/bin/env python3
"""Run local prepared personal conditioning through canonical export and mesh review.

Consumes an existing verified model sample. Does not resample from preferences,
accept physical fit, or publish to a device/service. All stages run offline.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from fit_conditioned_export import fit_export

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('preparation', 'texture', 'source', 'trajectory_report', 'output'):
        parser.add_argument(name, type=Path)
    parser.add_argument('--preparation-output-sha256', required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False, mode=0o700)
    snapshots = out / 'inputs'
    snapshots.mkdir(mode=0o700)
    inspector = ROOT / '.build/debug/capture-inspect'
    environment = dict(os.environ, HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1',
                       HF_DATASETS_OFFLINE='1', PYTORCH_ENABLE_MPS_FALLBACK='0')
    started = time.monotonic()
    report = dict(method='prepared_personal_conditioning_pipeline_v1',
                  preparationOutputSHA256=args.preparation_output_sha256,
                  scriptSHA256=digest(Path(__file__)),
                  directionFitScriptSHA256=digest(ROOT/'tools/fit_conditioned_export.py'),
                  canonicalJSONScriptSHA256=digest(ROOT/'tools/canonical_json.py'),
                  stages=[], status='running', acceptedForPersonalHaircut=False)

    def snapshot(source, name, limit):
        if source.stat().st_size > limit:
            raise ValueError('Pipeline input exceeds its byte budget')
        data = source.read_bytes()
        if len(data) > limit:
            raise ValueError('Pipeline input exceeds its byte budget')
        (snapshots / name).write_bytes(data)

    def invoke(name, command, timeout=300):
        stage = dict(name=name, status='running')
        report['stages'].append(stage)
        write(out / 'report.json', report)
        stage_start = time.monotonic()
        with (out / (name + '.log')).open('wb') as log:
            result = subprocess.run(list(map(str, command)), cwd=ROOT, env=environment,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        stage.update(exitCode=result.returncode, seconds=time.monotonic()-stage_start,
                     status='completed' if result.returncode == 0 else 'failed')
        if result.returncode:
            raise RuntimeError(name + ' failed; inspect its retained log')
        write(out / 'report.json', report)

    try:
        for name in ('source-input.json', 'prepared-brief.json', 'mapping.json', 'anatomy.json',
                     'preparation-result.json'):
            snapshot(args.preparation / name, name,
                     100_000_000 if name == 'preparation-result.json' else 25_000_000)
        # Reject stale/review-required preparation before touching model artifacts.
        invoke('preparation', [inspector, 'preparation-consume', snapshots/'preparation-result.json',
            args.preparation_output_sha256, snapshots/'source-input.json', snapshots/'prepared-brief.json',
            snapshots/'mapping.json', snapshots/'anatomy.json', out/'prepared-input.json'], 120)
        for source, name, limit in ((args.texture, 'texture.safetensors', 100_000_000),
                (args.source, 'source.json', 25_000_000), (args.trajectory_report, 'trajectory-report.json', 5_000_000)):
            snapshot(source, name, limit)
        common = ['--length-constraints', '--anatomy', snapshots/'anatomy.json', '--material-radius-meters', '.00005',
                  '--prepared-brief', snapshots/'prepared-brief.json',
                  '--preparation-result', snapshots/'preparation-result.json',
                  '--preparation-output-sha256', args.preparation_output_sha256]
        invoke('optimization', [sys.executable, ROOT/'tools/probe_personal_latent_constraint.py',
            snapshots/'texture.safetensors', snapshots/'source.json', snapshots/'source-input.json',
            snapshots/'mapping.json', out/'optimization', '--all-guides', *common])
        invoke('regional', [sys.executable, ROOT/'tools/probe_regional_latent_candidates.py',
            out/'optimization', snapshots/'source-input.json', snapshots/'mapping.json', out/'regional', *common])
        invoke('export', [sys.executable, ROOT/'tools/export_conditioned_guides.py',
            out/'optimization', out/'regional', snapshots/'source.json', out/'export',
            '--trajectory-report', snapshots/'trajectory-report.json'])
        invoke('mesh', [inspector, 'hair-mesh', out/'export/input.json', out/'export/haircut.json',
                        out/'mesh.json', '3', '1'], 120)
        review = json.loads((out/'export/review-report.json').read_bytes())
        mesh = json.loads((out/'mesh.json').read_bytes())
        if (mesh['haircutSHA256'] != review['haircutSHA256'] or mesh['radiusScale'] != 1
                or review['acceptedForPersonalHaircut'] is not False):
            raise ValueError('Compiled asset does not match the reviewed research revision')
        direction_fit = fit_export(out, inspector, invoke)
        selected_mesh = out/'direction-fit/mesh.json' if direction_fit['status'] == 'verified' else out/'mesh.json'
        selected = json.loads(selected_mesh.read_bytes())
        report.update(status='research_review_required', review=review,
                      meshFileSHA256=digest(out/'mesh.json'), meshVertexCount=len(mesh['vertices']),
                      inputFileSHA256={p.name: digest(p) for p in snapshots.iterdir()},
                      lengthConstraintsEnabled=True,
                      directionFit=direction_fit, selectedHaircutSHA256=selected['haircutSHA256'],
                      selectedMeshFileSHA256=digest(selected_mesh),
                      limitations=['Uses an existing model sample; this is personal conditioning, not new brief-driven sampling.',
                                   'Unresolved intersections and missing anatomy are retained for review.',
                                   'Style coherence, natural-hair feasibility and physical fit remain unverified.'])
    except Exception as error:
        report.update(status='failed', failure=str(error))
        raise
    finally:
        report['seconds'] = time.monotonic()-started
        write(out/'report.json', report)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
