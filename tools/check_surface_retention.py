#!/usr/bin/env python3
"""Compare reconstruction variants against the same observed depth samples.

This measures proximity to output vertices, not true triangle distance, anatomical
coverage or accuracy. Outputs and plots contain participant geometry: keep private.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


def points(surface):
    result = np.array([[v['position'][k] for k in 'xyz'] for v in surface['vertices']], dtype=float)
    if result.ndim != 2 or result.shape[1] != 3 or not np.all(np.isfinite(result)):
        raise ValueError('Invalid surface positions')
    return result


def bounded_nearest(queries, target, radius):
    """Exact nearest vertex within radius; infinity denotes none in radius."""
    cells = {}
    for key, point in zip(np.floor(target / radius).astype(int), target):
        cells.setdefault(tuple(key), []).append(point)
    cells = {k: np.array(v) for k, v in cells.items()}
    offsets = list(itertools.product((-1, 0, 1), repeat=3))
    result = np.full(len(queries), np.inf)
    for i, (query, key) in enumerate(zip(queries, np.floor(queries / radius).astype(int))):
        nearby = [cells[k] for offset in offsets
                  if (k := tuple(key + offset)) in cells]
        if nearby:
            delta = np.concatenate(nearby) - query
            minimum = float(np.sqrt(np.min(np.sum(delta * delta, axis=1))))
            if minimum <= radius:
                result[i] = minimum
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('variants', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    reference_bytes = args.reference.read_bytes()
    reference = json.loads(reference_bytes)
    assert len(reference['frames']) == 1 and not reference['completeHead']
    assert not reference['includesInferredAnatomy']
    query = points(reference)
    ref_frame = reference['frames'][0]
    pixel_ids = [v['observations'][0]['depthPixelIndex'] for v in reference['vertices']]
    assert all(len(v['observations']) == 1 and v['observations'][0]['frameIndex'] == 0
               for v in reference['vertices'])
    # Native image dimensions are read from the exact reference frame's mask.
    variants = sorted(args.variants.glob('*/surface.json'))
    assert variants, 'No variant surfaces'
    reports, panels = [], []
    for path in variants:
        raw = path.read_bytes(); surface = json.loads(raw)
        assert surface['method'] in ('masked_projective_tsdf_marching_tetrahedra_v2', 'masked_denoised_projective_tsdf_v1')
        assert surface['coordinateConvention'] == reference['coordinateConvention']
        first = surface['frames'][0]
        assert first['frameSHA256'] == ref_frame['frameSHA256']
        assert first['referenceFromCamera'] == ref_frame['referenceFromCamera']
        check = json.loads(path.with_name('verification.json').read_text())
        assert check['surfaceFileSHA256'] == hashlib.sha256(raw).hexdigest()
        assert check['allVerticesReprojectWithinDeclaredSupport']
        target = points(surface)
        distances = bounded_nearest(query, target, .008)
        # Independently check deterministic samples against all output vertices.
        sample_indices = np.linspace(0, len(query)-1, min(101, len(query)), dtype=int)
        for i in sample_indices:
            exact = np.sqrt(np.min(np.sum((target-query[i])**2, axis=1)))
            assert (np.isinf(distances[i]) and exact > .008) or abs(distances[i]-exact) < 1e-12
        counts = {str(mm): int((distances <= mm/1000).sum()) for mm in (2, 4, 8)}
        request = surface['request']
        report = {'variant': path.parent.name, 'surfaceSHA256': hashlib.sha256(raw).hexdigest(),
                  'frames': len(surface['frames']), 'minimumNearSurfaceViews': request['minimumNearSurfaceViews'],
                  'depthDenoising': request.get('depthDenoising'), 'voxelMeters': request['voxelMeters'], 'truncationMeters': request['truncationMeters'],
                  'maximumSignedDistanceSpreadMeters': request['maximumSignedDistanceSpreadMeters'],
                  'vertices': len(target), 'triangles': len(surface['triangles']), 'topology': surface['topology'],
                  'referenceSamples': len(query), 'referenceSamplesWithinVertexDistanceMM': counts,
                  'referenceSamplesBeyond8MM': int(np.isinf(distances).sum()),
                  'bruteForceComparisons': len(sample_indices), 'independentSupportCheck': True,
                  'fusionCounts': surface['counts']}
        reports.append(report)
        mask = request['surfaceRequest']['frames'][0]['mask']
        width, height = mask['size']['width'], mask['size']['height']
        pixels = np.zeros((height, width, 3), dtype=np.uint8)
        palette = [(220, 63, 60), (239, 173, 55), (48, 153, 212), (89, 196, 138)]
        categories = np.select([distances <= .002, distances <= .004, distances <= .008], [3, 2, 1], default=0)
        for pixel_id, category in zip(pixel_ids, categories):
            y, x = divmod(pixel_id, width)
            pixels[y:min(y+2,height), x:min(x+2,width)] = palette[category]
        plot = Image.fromarray(pixels).transpose(Image.Transpose.ROTATE_270)
        panel = Image.new('RGB', (520, 750), '#181818')
        panel.paste(plot, ((520-plot.width)//2, 60))
        draw = ImageDraw.Draw(panel)
        draw.text((12, 12), path.parent.name, fill='white')
        draw.text((12, 32), f"{counts['4']}/{len(query)} reference samples within 4 mm", fill='white')
        draw.text((12, 710), 'Green <=2; blue <=4; amber <=8; red >8 mm', fill='white')
        panels.append(panel)
        print(json.dumps({k:v for k,v in report.items() if k not in ('fusionCounts', 'topology')}), flush=True)
    canvas = Image.new('RGB', (520*len(panels), 750), '#181818')
    for i, panel in enumerate(panels): canvas.paste(panel, (520*i,0))
    args.output.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output/'reference-retention.png')
    (args.output/'reference-retention.json').write_text(json.dumps({
        'method': 'bounded_nearest_output_vertex_v1',
        'referenceSHA256': hashlib.sha256(reference_bytes).hexdigest(), 'variants': reports,
        'notes': ['All variants use the same measured reference samples; no regional anatomical labels are inferred.',
                  'Distances are to output vertices, not triangle interiors. Sampling, masks and field extraction affect this metric.',
                  'The reference is a fitting input, not independent ground truth. This is not a physical accuracy or whole-face coverage claim.',
                  'Frame count, minimum support, voxel spacing and depth limits are recorded per variant; compare request files for masks and registrations.']}, indent=2)+'\n')


if __name__ == '__main__':
    main()
