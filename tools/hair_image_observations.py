"""Image-space hair evidence. Does not infer scalp, roots or intrinsic color."""
import numpy as np


def observe_hair(rgb, labels, posterior, threshold=0.8, interior_radius=2):
    rgb, labels, posterior = np.asarray(rgb), np.asarray(labels), np.asarray(posterior)
    if rgb.dtype != np.uint8 or rgb.ndim != 3 or rgb.shape[2] != 3 or min(rgb.shape[:2]) < 1:
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


def texture_orientation(rgb, hair_mask, radius=7, minimum_coherence=0.4, minimum_energy=1e-5):
    """Local undirected texture axis using the smaller structure-tensor eigenvector.

    The returned H x W x 3 float32 field is (cos(2 theta), sin(2 theta),
    coherence). Doubled angles preserve the 180-degree ambiguity. Unsupported
    pixels are zero. This describes image texture, not root-to-tip direction.
    """
    rgb, hair_mask = np.asarray(rgb), np.asarray(hair_mask)
    if rgb.dtype != np.uint8 or rgb.ndim != 3 or rgb.shape[2] != 3 or min(rgb.shape[:2]) < 3:
        raise ValueError('Orientation requires RGB with both dimensions at least 3')
    if hair_mask.dtype != np.bool_ or hair_mask.shape != rgb.shape[:2]:
        raise ValueError('Orientation requires an aligned boolean mask')
    if not isinstance(radius, int) or not 1 <= radius <= 32:
        raise ValueError('Invalid orientation window radius')
    if not np.isfinite(minimum_coherence) or not 0 < minimum_coherence <= 1:
        raise ValueError('Invalid coherence threshold')
    if not np.isfinite(minimum_energy) or minimum_energy <= 0:
        raise ValueError('Invalid energy threshold')

    def mean_window(values, r):
        size = 2*r+1
        padded = np.pad(values.astype(np.float64), r, constant_values=0)
        integral = np.pad(padded, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
        return (integral[size:, size:]-integral[:-size, size:]
                -integral[size:, :-size]+integral[:-size, :-size])/(size*size)

    gray = rgb.astype(np.float64).mean(axis=2)/255
    gy, gx = np.gradient(gray)
    # Include a derivative halo: no accepted window may touch nonhair or image edges.
    supported_window = mean_window(hair_mask, radius+1) >= 1-1e-12
    xx, xy, yy = mean_window(gx*gx, radius), mean_window(gx*gy, radius), mean_window(gy*gy, radius)
    energy = np.maximum(xx+yy, 0)
    gap = np.hypot(xx-yy, 2*xy)
    coherence = np.clip(gap/np.maximum(energy, 1e-20), 0, 1)
    supported = supported_window & (energy >= minimum_energy) & (coherence >= minimum_coherence)
    field = np.zeros((*hair_mask.shape, 3), dtype=np.float32)
    # Gradient is normal to texture; negation of the doubled-angle normal gives the tangent.
    field[..., 0][supported] = -(xx-yy)[supported]/gap[supported]
    field[..., 1][supported] = -2*xy[supported]/gap[supported]
    field[..., 2][supported] = coherence[supported]
    return field, {'method': 'image_structure_tensor_box_v1', 'windowRadiusPixels': radius,
        'grayscale': 'mean_recorded_rgb_divided_by_255',
        'minimumCoherence': minimum_coherence, 'minimumEnergy': minimum_energy,
        'supportedPixels': int(supported.sum()), 'hairPixels': int(hair_mask.sum()),
        'axisEncoding': 'cos_2theta_sin_2theta_coherence_interleaved_float32_little_endian',
        'coordinates': 'native_image_x_right_y_down', 'unsupportedEncoding': [0, 0, 0],
        'directed': False, 'rootToTipMeasured': False, 'accuracyValidated': False,
        'notes': ['Coherence measures local image anisotropy, not confidence in strand direction.',
                  'Highlights, clump boundaries and blur can determine this axis.',
                  'No 3D direction or scalp growth direction is inferred.']}
