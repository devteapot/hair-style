# Dense rigid refinement experiment

Evaluated 2026-09-11. A bounded rigid surface refinement improves its fitting objective on the turning frame but fails the existing held-out landmark gate. No fusion transform or app model was replaced.

`tools/refine_face_rigid.py` starts from the failed frame-20→8 landmark estimate strictly as a research initializer. It uses original single-view measured vertices, excluding every point within 12 native RGB pixels of any held-out landmark on both source and target surfaces. Up to 2,000 deterministic source samples are matched to target vertices by exact nearest-sample search. Correspondences farther than 12 mm are excluded from fitting, and the nearest 80% of eligible matches fit a proper rigid transform with no scaling. These fitting exclusions do not remove any held-out residual from validation.

The optimizer never reads held-out residuals. It stops after at most 30 iterations or a maximum sample update below 10 micrometers. Corrections are bounded to 8 degrees relative to the initializer and 15 mm displacement of the fitting-cloud centroid. It rejects insufficient overlap, degenerate matches or an update that increases the fixed-correspondence fitting error. It cannot emit an accepted fusion artifact, even if a later experiment passes its landmark gate.

Three synthetic numerical checks pass: nearest search agrees with brute force including coincident points; a known 2-degree rigid transform and translation are recovered without scaling; distant clouds and insufficient sample sets are rejected. These checks establish implementation behavior, not camera accuracy.

On the recorded turn, fitting RMS falls from 2.717 mm at the first iteration to 1.550 mm at the last. This is a trimmed fitting objective whose correspondences change during optimization. Held-out median changes from 6.112 to 6.090 mm, and nearest-rank p95 from 27.120 to 25.161 mm. Both remain above the existing 4/10 mm limits. All ten held-out residuals are retained in the report.

Inspection of the source/target landmark overlay shows visible motion blur in the turning source frame. That may contribute to unreliable image correspondence and sampled depth, but this experiment does not isolate its cause from registration or model errors. Subsequent investigation should prioritize sharper held poses and explicit correspondence visibility rather than relax the gate or infer success from lower fitting error.

[Sanitized evidence](evidence/dense-refinement-2026-09-11.json) records the full iteration history, all validation residuals, test results and source hashes. Private geometry, matrices and the inspected image remain under ignored `outputs/dense-refinement/`. This was an offline Python experiment; native core, device build and app assets did not change.
