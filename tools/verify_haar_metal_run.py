#!/usr/bin/env python3
"""Verify artifact links across the text → diffusion → template-guide port."""
import argparse
import json
from pathlib import Path
import numpy as np
from safetensors.torch import load_file
from haar_text_metal import sha256
from haar_worker import REVISION
from inspect_haar_output import read_points


def verify(text_dir, trajectory_dir, guides_dir):
    reports = {name: json.loads((directory / 'report.json').read_text()) for name, directory in (
        ('text', text_dir), ('trajectory', trajectory_dir), ('guides', guides_dir))}
    text, trajectory, guides = (reports[key] for key in ('text', 'trajectory', 'guides'))
    if type(trajectory.get('seed')) is not int or not 0 <= trajectory['seed'] < 2**32:
        raise ValueError('Invalid recorded sampling seed')
    if text['method'] != 'haar_blip2_text_only_cpu_mps_v1' or trajectory['method'] != 'haar_pretrained_50_step_cpu_mps_v1' or guides['method'] != 'haar_template_strand_decode_cpu_mps_v1':
        raise ValueError('Unexpected port implementation')
    if trajectory['modelRevision'] != REVISION or guides['modelRevision'] != REVISION:
        raise ValueError('Unexpected HAAR revision')
    for report in reports.values():
        if report['cpuFallbackEnabled'] or not report['allFinite']:
            raise ValueError('Invalid Metal stage')
    if not text['allCloseAt1e4Absolute1e3Relative'] or not trajectory['allCloseAt1e4Absolute1e3Relative'] or not guides['allCloseAt1e5Absolute1e3Relative']:
        raise ValueError('CPU/Metal comparison did not pass')
    if trajectory['personalized'] or guides['acceptedForPersonalHaircut']:
        raise ValueError('Research output must remain unaccepted for personal use')
    if sha256(text_dir / 'condition.safetensors') != text['conditionSHA256'] or trajectory['conditionSHA256'] != text['conditionSHA256']:
        raise ValueError('Text/trajectory artifact mismatch')
    if sha256(trajectory_dir / 'texture.safetensors') != trajectory['textureSHA256'] or guides['textureSHA256'] != trajectory['textureSHA256']:
        raise ValueError('Trajectory/decoder artifact mismatch')
    if sha256(guides_dir / 'strands.safetensors') != guides['strandsSHA256'] or sha256(guides_dir / 'guides.ply') != guides['plySHA256']:
        raise ValueError('Strand serialization mismatch')
    tensors = load_file(str(guides_dir / 'strands.safetensors'))
    strands, roots = tensors['strands'].numpy(), tensors['roots'].numpy()
    count = guides['strandCount']
    if strands.shape != (count, 100, 3) or roots.shape != (count, 1, 3) or not np.isfinite(strands).all():
        raise ValueError('Invalid guide tensor dimensions')
    if not np.array_equal(strands[:, :1], roots):
        raise ValueError('Guide roots do not match template attachments')
    path = (guides_dir / 'guides.ply').resolve()
    recovered = np.asarray(read_points(path.read_bytes()), dtype=np.float32)
    if not np.array_equal(recovered, strands.reshape(-1, 3)):
        raise ValueError('PLY reordered or altered guide vertices')
    if np.any(np.linalg.norm(np.diff(strands, axis=1), axis=-1).sum(axis=1) <= 1e-9):
        raise ValueError('Degenerate guide')
    return dict(model='HAAR', revision=REVISION, implementation='metal_inference_port_v1',
        inferenceCompleted=True, exitCode=0, errors=[], description=text['description'], samplingSeed=trajectory['seed'],
        stageReportSHA256={name: sha256(directory / 'report.json') for name, directory in (
            ('text', text_dir), ('trajectory', trajectory_dir), ('guides', guides_dir))},
        output=dict(path=str(path), bytes=path.stat().st_size, sha256=guides['plySHA256']),
        strandCount=count, pointsPerStrand=100, rootOrderVerified=True,
        personalized=False, acceptedForPersonalHaircut=False,
        notes=['Verified connected text, texture, strand and PLY artifacts with CPU/MPS stage agreement.',
               'This is a local port using pretrained weights, not the unchanged upstream CUDA CLI.',
               'Template attachment and ordered geometry are verified; personal fitting, physical feasibility and production quality are not.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('text', type=Path)
    parser.add_argument('trajectory', type=Path)
    parser.add_argument('guides', type=Path)
    args = parser.parse_args()
    report = verify(args.text, args.trajectory, args.guides)
    with (args.guides / 'run.json').open('x') as stream:
        json.dump(report, stream, indent=2)
        stream.write('\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
