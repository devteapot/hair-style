"""Image-space hair evidence. Does not infer scalp, roots or intrinsic color."""
import numpy as np


def observe_hair(rgb, labels, posterior, threshold=0.8, interior_radius=2):
    rgb, labels, posterior = np.asarray(rgb), np.asarray(labels), np.asarray(posterior)
    if rgb.dtype != np.uint8 or rgb.ndim != 3 or rgb.shape[2] != 3:
        raise ValueError('RGB must be an H x W x 3 uint8 array')
    if labels.shape != rgb.shape[:2] or posterior.shape != labels.shape:
        raise ValueError('Mask dimensions must match native RGB')
    if not np.isfinite(posterior).all() or np.any((posterior < 0) | (posterior > 1)):
        raise ValueError('Invalid posterior')
    if not 0.5 <= threshold <= 0.99 or not isinstance(interior_radius, int) or not 0 <= interior_radius <= 16:
        raise ValueError('Invalid threshold or erosion radius')
    mask = (labels == 13) & (posterior >= threshold)
    # Exclude boundary mixtures from appearance summaries, without expanding hair.
    r = interior_radius
    padded = np.pad(mask, r, constant_values=False)
    interior = mask.copy()
    for dy in range(2*r+1):
        for dx in range(2*r+1):
            interior &= padded[dy:dy+mask.shape[0], dx:dx+mask.shape[1]]
    yy, xx = np.nonzero(mask)
    bounds = None if not len(xx) else dict(x=int(xx.min()), y=int(yy.min()),
        width=int(xx.max()-xx.min()+1), height=int(yy.max()-yy.min()+1))
    colors = rgb[interior]
    color = None
    if len(colors) >= 100:
        color = {'space': 'recorded_rgb_uint8', 'sampleCount': int(len(colors)),
                 'percentile10': np.percentile(colors, 10, axis=0).tolist(),
                 'median': np.median(colors, axis=0).tolist(),
                 'percentile90': np.percentile(colors, 90, axis=0).tolist(),
                 'intrinsicColorCalibrated': False}
    return mask, interior, {'hairPixels': int(mask.sum()), 'interiorPixels': int(interior.sum()),
        'imageFraction': float(mask.mean()), 'boundsPixels': bounds,
        'recordedColor': color, 'interiorRadiusPixels': r,
        'status': 'needs_review' if len(colors) >= 100 else 'insufficient_support',
        'rootDirection': None, 'strandDensity': None, 'scalpShape': None,
        'metricVolume': None, 'semanticAccuracyValidated': False}
