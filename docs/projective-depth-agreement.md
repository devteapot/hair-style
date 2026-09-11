# Projective depth agreement diagnostic

This check projects every supplied front surface vertex into an aligned rear depth frame using a fixed candidate rigid transform. It reports coverage and signed depth disagreement without fitting the transform or removing samples. It is an offline diagnostic, not a fusion acceptance gate.

`capture-inspect projective-agreement SOURCE_SURFACE.json TARGET_BUNDLE REQUEST.json OUTPUT.json`

The request supplies the target frame, explicit depth-resolution mask, `cameraFromSurface` transform, tolerance (default 5 mm) and minimum confidence. Target payload hashes, timestamps, calibration convention, dimensions and rigid transform are checked. Raw distorted front images are not supported as projection targets. Source JSON and its supplied transform are hashed but are not independently authenticated.

Samples are classified as behind camera, outside image, outside mask, missing depth, low confidence, consistent, behind observed depth or in front of observed depth. All samples remain in the denominator. A positive residual can indicate occlusion, misalignment or sensor error; it is not proof of occlusion. Nearest native depth sampling and model-derived masks also limit interpretation.

## Physical replay, 2026-09-10

The cleaned front frame 20 surface contains 10,094 samples. The target is assisted rear frame 56. Both the coarse landmark initializer and the geometry experiment candidate are inverted from rear-to-front into front-to-rear camera coordinates. Neither transform is approved for fusion.

| State | Initializer | Geometry candidate |
|---|---:|---:|
| Within 5 mm | 3,907 | 5,670 |
| In front of observed depth | 2,276 | 1,510 |
| Behind observed depth | 2,364 | 1,183 |
| Outside rear face mask | 1,535 | 1,721 |
| Low confidence | 12 | 10 |

Other states contain zero samples in this replay. Candidate agreement is 56.2% of all samples; 17.0% fall outside the mask and 26.7% disagree beyond the provisional tolerance. Different coverage explains some mismatch, but substantial disagreement remains inside the observed region. These correlated samples do not establish physical accuracy.

Two regression tests cover all classifications, residual signs, RGB-to-depth intrinsic scaling, transform direction, timing/calibration rejection and coordinate bounds. Full core suite: 67 tests pass. Physical reports and requests stay in ignored `outputs/projective-agreement/`.

Next: assess correspondence and masks against visible anatomy, then test visibility-aware alignment on a measured fixture. Do not remove behind-surface samples solely to improve reported agreement.
