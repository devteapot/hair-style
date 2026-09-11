# Held profile reconstruction

Evaluated 2026-09-11. Sharp held-profile frames produce a locally consistent partial surface. The direct connection to the frontal reference still fails, so the profile remains a separate camera-coordinate patch. It has not replaced or been attached to the app's head model.

Frames 24, 25 and 32 of the second repeat front pass were semantically masked and independently replayed. Inspection of frame 24 shows the visible side face, ear and forehead retained; hair and background excluded. Semantic accuracy remains unvalidated. No synchronization skew occurs in these three frames.

Image/depth flow registrations 25→24, 32→24 and 32→25 all pass the unchanged local rigid gates. Their 1,200 fitting/held-out residuals were independently reconstructed from original depth and lens calibration. The direct 24→8 frontal registration fails to find a consistent rigid alignment and contributes no transform to fusion.

Comparing the chain 32→25→24 against direct 32→24 across 7,412 original frame-32 samples gives median displacement 0.256 mm, nearest-rank p95 0.654 mm and maximum 0.930 mm; relative rotation differs by 0.522°. These are consistency measures on shared, correlated observations, not physical repeatability or anatomical accuracy.

The three verified masks and local registrations feed the existing raw projective fusion with 1.5 mm voxels, a 6 mm truncation band, two-frame minimum support and an 8 mm raw depth-spread limit. The result contains 45,849 vertices and 86,816 triangles. Every output vertex passes independent original-depth support checks; the mesh has 5,270 boundary edges, zero nonmanifold edges and zero inconsistent-winding edges.

The fixed-camera comparison was inspected and still shows noisy geometry and holes. Its display rotation only makes native sensor coordinates upright; it does not establish an anatomical frame or align the patch to the frontal reconstruction. The next reconstruction step must establish a separately validated cross-pose connection, with correspondence visibility and quality checks. Local consistency alone cannot authorize that connection.

[Sanitized evidence](evidence/held-profile-2026-09-11.json) records all trials, including the failed frontal connection, mask checks, loop measurements and fusion support. Private participant geometry and comparison images remain under ignored `outputs/profile-held/`. No new capture, native-core change, device installation or app-model replacement occurred.


## Semantic landmark compatibility trial

A separate frame-24→8 trial requires an inferred nose label near each nose landmark and either inferred eye label near each eye landmark in both images. The fixed neighborhood is 7×7 native pixels. Original even/odd fit/validation roles remain unchanged, and every excluded landmark remains in an audit. This is a model-based compatibility proxy, not verified visibility.

Five fitting and five held-out points remain. Their independently replayed held-out median is 10.786 mm and p95 is 22.147 mm, failing the unchanged 4/10 mm limits. These reduced-denominator results are not directly comparable to the original full landmark set. Bounded dense refinement of this initializer also rejects the trial when correction exceeds its 8-degree / 15-mm limit. Neither result contributes to fusion.

The reusable research filter is `tools/filter_semantic_landmarks.py`; its replay reproduces the trial selection exactly and verifies the saved label hashes/frame bindings. [Sanitized evidence](evidence/semantic-landmarks-2026-09-11.json) retains all exclusions and failure results. The frontend/profile connection remains unresolved. Further M2 experiments may use the existing provisional head with explicit uncertainty, but cannot claim that M1's reconstruction gate passed.
