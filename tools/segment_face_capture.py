#!/usr/bin/env python3
"""Local research parsing -> face surface mask or image-space hair evidence.

Uses pinned SegFormer weights; no camera evidence is sent to a service. Outputs
are model-inferred masks, not measured labels or accepted head/hair geometry.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

os.environ['PYTORCH_ENABLE_MPS_FALLBACK'] = '0'

import numpy as np
from PIL import Image
import torch
from transformers import SegformerImageProcessor, SegformerForSemanticSegmentation

REVISION = '758b82e15a0178c9db39c1ff666a8b56e3a550c8'
MODEL_SHA256 = 'c2bec795a8c243db71bd95be538fd62559003566466c71237e45c99b920f4b62'
REPOSITORY = 'jonathandinu/face-parsing'
INCLUDED_LABELS = [1, 2, 4, 5, 6, 7, 8, 9, 11, 12]
ROTATIONS = {'none': 0, 'clockwise90': -1, 'clockwise180': 2, 'clockwise270': 1}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def runs(mask):
    flat = mask.reshape(-1)
    padded = np.r_[False, flat, False].astype(np.int8)
    changes = np.diff(padded)
    starts = np.flatnonzero(changes == 1)
    ends = np.flatnonzero(changes == -1)
    return [{'start': int(a), 'count': int(b-a)} for a, b in zip(starts, ends)]


def verify_payload(bundle, record):
    path = (bundle / record['path']).resolve()
    path.relative_to(bundle)
    data = path.read_bytes()
    if len(data) != record['byteCount'] or digest(data) != record['sha256']:
        raise ValueError('Capture payload integrity failed')
    return path, data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('frame_index', type=int)
    parser.add_argument('output', type=Path)
    parser.add_argument('--rotation', choices=ROTATIONS, required=True)
    parser.add_argument('--model', type=Path, default=Path('.research/face-parsing'))
    parser.add_argument('--device', choices=['cpu', 'mps'], default='mps')
    parser.add_argument('--compare-cpu', action='store_true')
    parser.add_argument('--confidence', type=float, default=0.8)
    parser.add_argument('--target', choices=['face', 'hair'], default='face')
    parser.add_argument('--capture-condition', choices=['tied', 'untied', 'unknown'])
    args = parser.parse_args()
    if not 0.5 <= args.confidence <= 0.99:
        raise ValueError('Use an explicit confidence threshold between 0.5 and 0.99')
    bundle = args.bundle.resolve()
    cli = Path(__file__).resolve().parents[1] / '.build/debug/capture-inspect'
    subprocess.run([str(cli), 'inspect', str(bundle)], check=True, capture_output=True)
    manifest_data = (bundle/'manifest.json').read_bytes()
    manifest = json.loads(manifest_data)
    from hair_image_observations import capture_condition
    hair_condition, hair_condition_source = capture_condition(manifest, args.capture_condition)
    if not 0 <= args.frame_index < len(manifest['frames']):
        raise ValueError('Frame index out of bounds')
    frame = manifest['frames'][args.frame_index]
    metadata = frame['metadata']
    if metadata['mirrored'] or metadata['pixelOrientation'] != 'sensor_native':
        raise ValueError('Requires native unmirrored input')
    if args.target == 'face' and abs(metadata['imageTimestamp'] - metadata['depthTimestamp']) > .01:
        raise ValueError('Image/depth timestamps exceed the existing 10 ms gate')
    if args.target == 'face' and metadata['depthRectification'] not in ('not_applied', 'arkit_aligned_scene_depth'):
        raise ValueError('Unsupported image/depth alignment')
    image_path, image_data = verify_payload(bundle, frame['image'])
    _, depth_data = verify_payload(bundle, frame['depth'])
    h, w = metadata['depthSize']['height'], metadata['depthSize']['width']
    depth = np.frombuffer(depth_data, dtype='<f4').reshape(h, w)
    download = json.loads((args.model/'download-manifest.json').read_text())
    if download['repository'] != REPOSITORY or download['revision'] != REVISION or download['files']['model.safetensors']['sha256'] != MODEL_SHA256:
        raise ValueError('Pinned model identity mismatch')
    for name, record in download['files'].items():
        path = (args.model/name).resolve()
        path.relative_to(args.model.resolve())
        data = path.read_bytes()
        if digest(data) != record['sha256'] or len(data) != record['byteCount']:
            raise ValueError('Local model file changed: '+name)
    os.environ['HF_HUB_OFFLINE'] = '1'
    os.environ['PYTORCH_ENABLE_MPS_FALLBACK'] = '0'
    processor = SegformerImageProcessor.from_pretrained(args.model, local_files_only=True)
    model = SegformerForSemanticSegmentation.from_pretrained(args.model, local_files_only=True, use_safetensors=True).eval()
    expected_labels = {1: 'skin', 2: 'nose', 3: 'eye_g', 13: 'hair', 14: 'hat', 17: 'neck', 18: 'cloth'}
    if any(model.config.id2label.get(k) != v for k, v in expected_labels.items()):
        raise ValueError('Unexpected label mapping')
    image = Image.open(image_path).convert('RGB')
    if image.size != (metadata['imageSize']['width'], metadata['imageSize']['height']):
        raise ValueError('Image dimensions disagree with metadata')
    native = np.asarray(image)
    upright = Image.fromarray(np.rot90(native, ROTATIONS[args.rotation]).copy())
    inputs = processor(images=upright, return_tensors='pt')
    timings = {}

    def infer(device):
        model.to(device)
        pixel_values = inputs['pixel_values'].to(device)
        if device == 'mps': torch.mps.synchronize()
        start = time.perf_counter()
        with torch.inference_mode():
            logits = model(pixel_values=pixel_values).logits
            logits = torch.nn.functional.interpolate(logits, size=(upright.height, upright.width), mode='bilinear', align_corners=False)
            probabilities = logits.softmax(dim=1)
            labels = probabilities.argmax(dim=1)
            # Skin/nose/lips are all retained. Their mutual class boundaries
            # must not become holes merely because no single class exceeds .8.
            probs = probabilities[:, [13] if args.target == 'hair' else INCLUDED_LABELS].sum(dim=1)
            if device == 'mps': torch.mps.synchronize()
        timings[device] = time.perf_counter()-start
        return labels[0].cpu().numpy().astype(np.uint8), probs[0].cpu().numpy().astype(np.float32)

    if args.device == 'mps' and not torch.backends.mps.is_available():
        raise ValueError('MPS unavailable; choose CPU explicitly')
    labels, confidence = infer(args.device)
    agreement = None
    if args.compare_cpu and args.device == 'mps':
        cpu_labels, cpu_confidence = infer('cpu')
        agreement = {'identicalLabelFraction': float(np.mean(cpu_labels == labels)),
                     'differentLabelPixels': int(np.count_nonzero(cpu_labels != labels)),
                     'maximumConfidenceDifference': float(np.max(np.abs(cpu_confidence-confidence)))}
    # Invert the explicit quarter-turn before mapping to aligned depth pixels.
    labels = np.rot90(labels, -ROTATIONS[args.rotation]).copy()
    confidence = np.rot90(confidence, -ROTATIONS[args.rotation]).copy()
    if args.target == 'hair':
        # Retain full RGB resolution; this artifact does not register or fuse depth.
        from hair_image_observations import observe_hair, texture_orientation
        mask, interior, observation = observe_hair(native, labels, confidence, args.confidence)
        orientation, orientation_report = texture_orientation(native, mask)
        args.output.mkdir(parents=True, exist_ok=False)
        labels_data, confidence_data = labels.tobytes(), confidence.astype('<f4').tobytes()
        (args.output/'labels.u8').write_bytes(labels_data)
        (args.output/'hair-posterior.f32').write_bytes(confidence_data)
        mask_data = mask.astype(np.uint8).tobytes()
        (args.output/'hair-mask.u8').write_bytes(mask_data)
        interior_data = interior.astype(np.uint8).tobytes()
        (args.output/'hair-interior.u8').write_bytes(interior_data)
        orientation_data = orientation.astype('<f4').tobytes()
        (args.output/'texture-axis.f32').write_bytes(orientation_data)
        report = {'schemaVersion': 1, 'method': 'local_segformer_hair_image_v1',
                  'captureID': manifest['id'], 'frameID': metadata['id'], 'frameIndex': args.frame_index,
                  'sourceManifestSHA256': digest(manifest_data), 'imageSHA256': digest(image_data),
                  'depthSHA256': digest(depth_data), 'model': download,
                  'imageSize': metadata['imageSize'], 'coordinateConvention': 'native_image_x_right_y_down_pixels',
                  'rotationToUpright': args.rotation, 'confidenceThreshold': args.confidence,
                  'confidenceMode': 'hair_class_posterior', 'device': args.device,
                  'timingsSeconds': timings, 'cpuAgreement': agreement,
                  'captureCondition': hair_condition,
                  'captureConditionSource': hair_condition_source,
                  'labelsSHA256': digest(labels_data), 'posteriorSHA256': digest(confidence_data),
                  'maskSHA256': digest(mask_data), 'interiorMaskSHA256': digest(interior_data),
                  'textureAxisSHA256': digest(orientation_data), 'textureOrientation': orientation_report,
                  'observation': observation, 'acceptedForNaturalHairBaseline': False,
                  'registeredToHead': False, 'commercialUseCleared': False,
                  'notes': ['Research/educational model only per author card.',
                      'Model posterior is not calibrated accuracy. Review segmentation before use.',
                      'Recorded color includes lighting and camera processing; it is not intrinsic hair color.',
                      'No metric hair volume, scalp completion, root direction or follicle density is inferred.',
                      'Tied and unknown-condition captures cannot establish the natural-hair silhouette.']}
        (args.output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        fig, axes = plt.subplots(1, 3, figsize=(12, 5))
        for ax, data, title in zip(axes, [native, mask, interior],
                ['Recorded RGB', 'Inferred hair; review required', 'Interior for recorded color']):
            ax.imshow(np.rot90(data, ROTATIONS[args.rotation])); ax.set_title(title); ax.axis('off')
        fig.tight_layout(); fig.savefig(args.output/'diagnostic.png', dpi=140); plt.close(fig)
        from matplotlib.collections import LineCollection
        fig, ax = plt.subplots(figsize=(10, 8))
        ax.imshow(native)
        yy, xx = np.mgrid[12:native.shape[0]:24, 12:native.shape[1]:24]
        values = orientation[yy, xx]
        valid = values[..., 2] > 0
        centers = np.stack([xx[valid], yy[valid]], axis=-1)
        theta = .5*np.arctan2(values[..., 1][valid], values[..., 0][valid])
        delta = 8*np.stack([np.cos(theta), np.sin(theta)], axis=-1)
        ax.add_collection(LineCollection(np.stack([centers-delta, centers+delta], axis=1),
                                        colors='cyan', linewidths=.6))
        ax.set_title('Native image texture axes; undirected, unvalidated'); ax.axis('off')
        fig.tight_layout(); fig.savefig(args.output/'texture-axis-diagnostic.png', dpi=140); plt.close(fig)
        print(json.dumps(observation, indent=2))
        return
    if labels.shape != depth.shape:
        # Nearest image pixel at each depth pixel center. No label interpolation.
        yy = np.minimum(((np.arange(h)+.5)*labels.shape[0]/h).astype(int), labels.shape[0]-1)
        xx = np.minimum(((np.arange(w)+.5)*labels.shape[1]/w).astype(int), labels.shape[1]-1)
        labels, confidence = labels[np.ix_(yy, xx)], confidence[np.ix_(yy, xx)]
    semantic = confidence >= args.confidence
    valid = np.isfinite(depth) & (depth >= .05) & (depth <= 2)
    if np.count_nonzero(semantic & valid) < 100:
        raise ValueError('Too few supported face pixels')
    median = float(np.median(depth[semantic & valid]))
    band = np.abs(depth-median) < .08
    mask = semantic & valid & band
    if frame.get('confidence'):
        _, raw = verify_payload(bundle, frame['confidence'])
        levels = np.frombuffer(raw, dtype=np.uint8).reshape(h, w)
        mask &= (levels >= 1) & (levels <= 2)
    args.output.mkdir(parents=True, exist_ok=False)
    labels_data, confidence_data = labels.tobytes(), confidence.astype('<f4').tobytes()
    (args.output/'labels.u8').write_bytes(labels_data)
    (args.output/'confidence.f32').write_bytes(confidence_data)
    model_sha = download['files']['model.safetensors']['sha256']
    request = {'schemaVersion': 1, 'samplingStride': 2, 'minimumConfidence': 1, 'maximumEdgeMeters': .01,
               'fusionRadiusMeters': .0015, 'frames': [{'captureID': manifest['id'], 'frameID': metadata['id'],
               'mask': {'size': metadata['depthSize'], 'provenance': 'model_inferred',
                        'method': f'SegFormer {REPOSITORY}@{REVISION}; weights SHA256 {model_sha}; labels {INCLUDED_LABELS}; summed allowed-class posterior >= {args.confidence}; native rotation {args.rotation}; +/-80mm face depth band; unvalidated semantic mask; no dilation or hole filling',
                        'includedRuns': runs(mask)}}]}
    (args.output/'request.json').write_text(json.dumps(request, indent=2)+'\n')
    report = {'schemaVersion': 1, 'method': 'local_segformer_face_mask_v2', 'model': download,
              'frameIndex': args.frame_index, 'frameID': metadata['id'], 'captureID': manifest['id'],
              'sourceManifestSHA256': digest(manifest_data), 'imageSHA256': digest(image_data), 'depthSHA256': digest(depth_data),
              'rotationToUpright': args.rotation, 'confidenceThreshold': args.confidence, 'confidenceMode': 'sum_posterior_over_included_labels', 'device': args.device,
              'timingsSeconds': timings, 'cpuAgreement': agreement, 'labelCounts': {model.config.id2label[i]: int(np.count_nonzero(labels == i)) for i in range(19)},
              'depthSize': metadata['depthSize'], 'includedLabelIDs': INCLUDED_LABELS, 'semanticPixels': int(semantic.sum()),
              'invalidDepthInSemanticPixels': int((semantic & ~valid).sum()), 'bandExcludedPixels': int((semantic & valid & ~band).sum()),
              'includedPixels': int(mask.sum()), 'medianFaceDepthMeters': median, 'labelsSHA256': digest(labels_data),
              'confidenceSHA256': digest(confidence_data), 'surfaceRequestFileSHA256': digest((args.output/'request.json').read_bytes()),
              'acceptedForHeadFitting': False, 'semanticAccuracyValidated': False, 'commercialUseCleared': False,
              'torchVersion': torch.__version__, 'notes': ['Research/educational model only per author card.',
                  'Summed allowed-class confidence is not calibrated accuracy. Labels and depth band need visual review.',
                  'The mask does not create depth or fill missing anatomy. It does not validate registration or metric accuracy.']}
    (args.output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    subprocess.run([str(cli), 'surface', str(bundle.parent), str(args.output/'request.json'), str(args.output/'surface.json'), str(args.output/'surface.ply')], check=True)
    # Private diagnostic plot: RGB, inferred classes, and retained measured depth.
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 3, figsize=(12, 5))
    axes[0].imshow(upright); axes[0].set_title('Recorded RGB')
    axes[1].imshow(np.rot90(labels, ROTATIONS[args.rotation]), vmin=0, vmax=18, cmap='tab20'); axes[1].set_title('Inferred classes; unvalidated')
    shown = np.where(mask, depth*1000, np.nan)
    im = axes[2].imshow(np.rot90(shown, ROTATIONS[args.rotation]), vmin=(median-.08)*1000, vmax=(median+.08)*1000, cmap='viridis')
    axes[2].set_title('Retained depth (mm); holes remain')
    fig.colorbar(im, ax=axes[2], shrink=.65)
    for ax in axes: ax.axis('off')
    fig.tight_layout(); fig.savefig(args.output/'diagnostic.png', dpi=140); plt.close(fig)
    print(json.dumps({k: report[k] for k in ['includedPixels', 'semanticPixels', 'timingsSeconds', 'cpuAgreement']}, indent=2))


if __name__ == '__main__':
    main()
