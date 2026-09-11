# Seeded surface-component cleanup

`SurfaceFrameRequest.componentSelection` optionally retains the triangle-connected component containing an explicit native depth-pixel seed before multi-view fusion. This addresses small detached patches observed in the first physical front scan. It does not classify skin or background, close holes, move retained points, or replace semantic masking.

Example request fragment:

```json
"componentSelection": {
  "seedDepthPixelIndex": 123456,
  "maximumRemovedFraction": 0.05
}
```

The example index is illustrative; choose a retained depth sample in the intended region. A missing seed fails. A seed in the wrong small component fails the removal budget rather than silently selecting the largest component. The default budget is 5% of connected depth samples and the implementation permits at most 10%. Omit the option to keep the previous behavior.

Each frame records component sizes, original/retained counts, every excluded pixel, the seed and removal budget. The request hash binds the processing choice. Raw payloads and supplied masks remain unchanged. A registration landmark mapping to an excluded coarse sample causes fusion to fail. This conservative check is not an anatomical correspondence validator.

Connectivity uses triangle vertices; it does not prove a smooth manifold or distinguish connected artifacts. Disconnected geometry may be real anatomy, so exclusions remain an explicit processing decision. This option is inappropriate for silently discarding large ears, profiles or separate regions in a head scan.

## Physical replay

The five previously aligned frames were rebuilt. Each seed was the retained sample within four native pixels of Vision's `vision_nose:0` estimate; this model-derived seed has not been anatomically validated. Removal counts: frame 18 lost 18 samples, frame 20 lost 14, and frames 19/21/22 lost none. All retained single-view vertex records were compared exactly with the originals and were unchanged.

After cleanup, the largest bidirectional discrepancy changed as follows:

| Pair | Before | After |
|---|---:|---:|
| 18→20 | 13.01 mm | 13.29 mm |
| 19→20 | 38.47 mm | 14.50 mm |
| 21→20 | 43.41 mm | 20.68 mm |
| 22→20 | 40.14 mm | 10.02 mm |

This removes some extreme detached fragments, not every outlier. One maximum increases slightly because its nearest candidate was removed. P95 distances are mostly unchanged. These are nearest-sample diagnostics, not accuracy measurements. The five-frame fusion replays with unchanged registration gates. Substantial facial gaps and depth/normal noise remain; this is not yet a haircut-fitting surface.

Three new tests cover explicit seed selection, every excluded sample, missing/wrong seeds, removal-budget failure, unchanged connected regions and invalid inputs. The full core suite has 65 passing tests and the unsigned iPhone SDK build passes. No app reinstall or camera interruption occurred during the participant's next recording.
