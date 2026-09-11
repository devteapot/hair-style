# Experimental face-conditioned fringe policy

The offline pipeline can now change a regional haircut constraint using an explicitly selected, depth-backed face proportion. This is post-generation policy conditioning of fixed HAAR guides, not person-conditioned neural generation or validated style selection.

`face-conditioned-brief INPUT.json SCALP_REVIEW.json REQUEST.json OUTPUT.json` replays the scalp review, verifies matching source geometry and provenance, and measures chin distance below the eye plane relative to eye landmark separation. It changes only the fringe maximum length within the existing brief limits. The reference ratio of 1.25 and 40 mm reference length are experimental constants, not population norms or an aesthetic recommendation. The multiplier is bounded to 0.75–1.25. User constraints remain binding; aesthetic quality and physical feasibility remain explicitly unverified.

## Physical comparison

The second repeat front pass supplied the same inferred scalp for both variants. The generic reference caps the fringe at 40 mm; the provisional personal proportion caps it at 50 mm. Independent arc-length and identity checks found 142 changed fringe guides, four already-short fringe guides unchanged, and all 617 other guides exactly unchanged. Source model guides, seed, roots, material bindings and envelope guard are identical.

The rendered comparison was inspected: the green fringe is visibly longer in the personal-policy row, while the other regions remain consistent. The gray observed face is noisy and incomplete, the amber scalp is inferred, and guide radii are enlarged eightfold for inspection. This is a diagnostic view, not a finished hairstyle preview.

## Limitations retained

- The provisional chin vertex lies 7.28 mm from the selected Vision contour point, outside the exploratory 3 mm correspondence preference. Its anatomical identity is not accepted. This trial exercises the policy rather than establishing a reliable personal measurement.
- The retained surface's superior extent was not used as a forehead measurement: it depends on capture coverage.
- The initial 20 mm root adjustment allowance rejected the mapping. Twenty guides exceed that allowance; maximum adjustment is 29.787 mm. A separately labeled 30 mm research mapping enabled this comparison. The envelope guard remains unchanged, and the fit remains unaccepted.
- Actual hairline, natural texture, growth direction, available length and styling feasibility remain unknown. A longer fringe has not been shown to suit this person.
- Full head reconstruction, autonomous ranking, guided product integration and person-conditioned neural generation remain unfinished. No M1 or M2 exit gate is claimed.

## Validation

All 111 core tests pass, including personal/reference divergence, preservation of guided bounds and rejection of invalid feature/geometry inputs. The unsigned iPhone SDK build succeeds. No new package was installed on the phone and no camera session was started.

Sanitized evidence is in [the comparison report](evidence/face-conditioned-design-2026-09-11.json). Participant geometry and renderings remain in ignored local outputs under `outputs/face-conditioned-design/`.
