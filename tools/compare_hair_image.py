#!/usr/bin/env python3
"""Compare projected guide segments with local hair evidence; no automatic acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np


def compare_guides(guides, metadata, camera_from_hair, mask, axes):
    size = metadata['imageSize']; h, w = size['height'], size['width']
    if metadata['mirrored'] or metadata['pixelOrientation'] != 'sensor_native':
        raise ValueError('Requires native unmirrored images')
    if metadata['depthRectification'] not in ('arkit_aligned_scene_depth', 'synthetic_pinhole'):
        raise ValueError('Unrectified front-camera projection is not implemented here')
    if mask.dtype != np.bool_ or mask.shape != (h, w) or axes.shape != (h, w, 3):
        raise ValueError('Image evidence dimensions disagree')
    if not np.isfinite(axes).all() or np.any((axes[..., 2] < 0) | (axes[..., 2] > 1)):
        raise ValueError('Invalid texture field')
    supported = axes[..., 2] > 0
    if np.any(supported & ~mask) or not np.allclose(np.linalg.norm(axes[supported, :2], axis=1), 1, atol=1e-5):
        raise ValueError('Texture axes must be unit axes within hair support')
    m = np.asarray(camera_from_hair, dtype=float).reshape(4, 4)
    if not np.isfinite(m).all() or not np.allclose(m[3], [0, 0, 0, 1], atol=1e-8):
        raise ValueError('Invalid camera transform')
    if not np.allclose(m[:3, :3].T@m[:3, :3], np.eye(3), atol=1e-6) or abs(np.linalg.det(m[:3, :3])-1) > 1e-6:
        raise ValueError('Camera transform must be rigid, in optical coordinates and meters')
    k = metadata['intrinsics']; ref = k['referenceSize']
    focal = np.array([k['fx']*w/ref['width'], k['fy']*h/ref['height']])
    center = np.array([k['cx']*w/ref['width'], k['cy']*h/ref['height']])
    if not np.isfinite(focal).all() or np.any(focal <= 0) or not np.isfinite(center).all():
        raise ValueError('Invalid intrinsics')
    counts = dict(segments=0, behindOrCrossingCamera=0, degenerateProjection=0,
                  projectedSamples=0, outsideImageSamples=0, hairSamples=0, orientationSamples=0)
    errors = []
    for guide in guides:
        points = np.asarray(guide, dtype=float)
        if points.ndim != 2 or points.shape[1] != 3 or len(points) < 2 or not np.isfinite(points).all():
            raise ValueError('Invalid guide')
        camera = points@m[:3, :3].T+m[:3, 3]
        for a, b in zip(camera[:-1], camera[1:]):
            counts['segments'] += 1
            if min(a[2], b[2]) <= 1e-6:
                counts['behindOrCrossingCamera'] += 1
                continue
            uv = np.array([a[:2]/a[2], b[:2]/b[2]])*focal+center
            delta = uv[1]-uv[0]; length = np.linalg.norm(delta)
            if not np.isfinite(length) or length > 8192:
                raise ValueError('Projected segment exceeds diagnostic sampling budget')
            if length < 1e-6:
                counts['degenerateProjection'] += 1
                continue
            n = max(1, int(np.ceil(length/2)))
            counts['projectedSamples'] += n
            if counts['projectedSamples'] > 2_000_000:
                raise ValueError('Projected sample budget exceeded')
            uv_samples = uv[0]+((np.arange(n)+.5)/n)[:, None]*delta
            inside = (uv_samples[:, 0] >= 0) & (uv_samples[:, 0] < w) & (uv_samples[:, 1] >= 0) & (uv_samples[:, 1] < h)
            counts['outsideImageSamples'] += int((~inside).sum())
            xy = np.floor(uv_samples[inside]+.5).astype(int)
            xy[:, 0] = np.minimum(xy[:, 0], w-1); xy[:, 1] = np.minimum(xy[:, 1], h-1)
            hair = mask[xy[:, 1], xy[:, 0]]
            counts['hairSamples'] += int(hair.sum())
            evidence = axes[xy[:, 1], xy[:, 0]]
            valid = hair & (evidence[:, 2] > 0)
            theta = np.arctan2(delta[1], delta[0])
            predicted = np.array([np.cos(2*theta), np.sin(2*theta)])
            dot = np.clip(evidence[valid, :2]@predicted, -1, 1)
            errors.extend(np.degrees(.5*np.arccos(dot)).tolist())
            counts['orientationSamples'] += int(valid.sum())
    in_image = counts['projectedSamples']-counts['outsideImageSamples']
    return {'method': 'projected_guide_image_agreement_v1', **counts,
        'hairAgreementOfInImageSamples': counts['hairSamples']/in_image if in_image else None,
        'orientationMedianDegrees': float(np.median(errors)) if errors else None,
        'orientationP95Degrees': float(np.percentile(errors, 95)) if errors else None,
        'occlusionTested': False, 'registrationValidated': False, 'acceptedForFitting': False,
        'notes': ['Sparse guide samples are not a full hair silhouette, density estimate or reconstruction score.',
                  'Image axes are undirected. Orientation disagreement ranges from 0 to 90 degrees.',
                  'No head/hair occlusion is tested; hidden guides may be compared with visible texture.',
                  'Segment samples are spaced at at most two pixels; subdivision changes sample weighting.',
                  'Behind-camera and crossing-camera segments are excluded and counted.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['bundle', 'evidence', 'haircut', 'alignment', 'output']:
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    def sha(data): return hashlib.sha256(data).hexdigest()
    manifest_data = (args.bundle/'manifest.json').read_bytes(); manifest = json.loads(manifest_data)
    report_data = (args.evidence/'report.json').read_bytes(); evidence = json.loads(report_data)
    haircut_data = args.haircut.read_bytes(); haircut = json.loads(haircut_data)
    alignment_data = args.alignment.read_bytes(); alignment = json.loads(alignment_data)
    if evidence['sourceManifestSHA256'] != sha(manifest_data) or evidence['captureID'] != manifest['id']:
        raise ValueError('Evidence belongs to a different capture revision')
    if alignment['haircutFileSHA256'] != sha(haircut_data) or alignment['evidenceReportSHA256'] != sha(report_data):
        raise ValueError('Alignment belongs to different inputs')
    frame = next(f for f in manifest['frames'] if f['metadata']['id'] == evidence['frameID'])
    if frame['image']['sha256'] != evidence['imageSHA256'] or frame['metadata']['imageSize'] != evidence['imageSize']:
        raise ValueError('Evidence image identity mismatch')
    h, w = evidence['imageSize']['height'], evidence['imageSize']['width']
    def raster(name, key, dtype, shape):
        data = (args.evidence/name).read_bytes()
        if sha(data) != evidence[key]: raise ValueError('Changed image evidence: '+name)
        return np.frombuffer(data, dtype=dtype).reshape(shape)
    mask = raster('hair-mask.u8', 'maskSHA256', np.uint8, (h, w))
    if np.any(mask > 1): raise ValueError('Invalid binary hair mask')
    axes = raster('texture-axis.f32', 'textureAxisSHA256', '<f4', (h, w, 3))
    guides = [[[p[k] for k in 'xyz'] for p in g['points']] for g in haircut['guides']]
    result = compare_guides(guides, frame['metadata'], alignment['cameraFromHairRowMajor'], mask.astype(bool), axes)
    result.update(haircutFileSHA256=sha(haircut_data), evidenceReportSHA256=sha(report_data),
                  alignmentFileSHA256=sha(alignment_data), captureCondition=evidence['captureCondition'])
    with args.output.open('x') as out: json.dump(result, out, indent=2); out.write('\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__': main()
