# Experimental observed-surface remeshing

The first physical multi-view patch exposed a limitation of radius-based vertex fusion: retaining each view's triangles creates overlapping sheets. `SurfaceRemesher` extracts new triangles from a shared local field instead. It is an offline reconstruction experiment, not the complete-head or haircut-fitting asset path.

```sh
tools/dev.sh swift build
.build/debug/capture-inspect remesh-surface OBSERVED_SURFACE.json REMESH.json
```

Input is the existing registered `ObservedSurface`. Build that input through the capture-backed surface command so payload integrity, calibration, timestamps, masks and held-out landmark registration are checked. The remesher validates finite oriented samples and processing bounds; it does not reopen the original capture or independently authenticate an arbitrary supplied JSON file. Output includes a canonical source hash, original frame evidence, coordinate convention, algorithm/options and explicit incomplete/not-suitable-for-fitting flags. Output vertices are interpolated geometry, not new direct depth observations.

The algorithm splats local signed distances to oriented sample tangent planes onto a sparse grid. Defaults: 2 mm grid, 6 mm compact support, normal agreement at least 0.8. Only cells whose eight corners have sufficient coherent support are extracted, using consistently tiled marching tetrahedra. Shared grid-edge crossings produce shared vertices. Triangle winding follows each tetrahedron's field gradient; using averaged measured normals caused inconsistent winding on the physical replay and was corrected.

This is not projective TSDF fusion. It has no camera-ray visibility reasoning or occlusion model, and it inherits registration/mask/normal errors. Local interpolation can extend mask boundaries or bridge small holes up to the support radius; larger unsupported regions remain open. There is no global closure, scalp inference, landmark refitting or claim of anatomical accuracy.

The topology inspection reports boundary edges, edges with more than two incident triangles and inconsistent winding across two-triangle edges. The latter two reject the result. These checks do not prove vertex-manifoldness, absence of self-intersections, measurement accuracy or completeness. Processing bounds cap input/output vertices at 250,000, supported grid nodes at one million and output triangles at 500,000.

## Verification

Five new tests cover offset plane observations, a large unsupported hole, a curved field, invalid inputs/options and topology failures. The full core suite has 59 passing tests. An unsigned iPhone SDK build passed; the CLI replay runs on the development Mac, not on the iPhone.

The participant's five-frame patch produced 23,802 vertices and 45,162 triangles, with zero nonmanifold edges, zero inconsistent winding edges and 2,480 boundary edges. The previous per-view triangle fusion had 20,408 nonmanifold edges. Visual inspection shows a smoother partial face with significant holes around the eyes, nose, mouth and chin. Smoothness is not evidence of improved accuracy. Raw and derived participant artifacts remain under ignored outputs.

Next: verify dense overlap independently, improve local normals/depth quality without erasing features, evaluate a camera-aware integration method, and compare against measured fixtures and repeat captures. The reconstructed patch must not become the fitting surface merely because edge checks pass.
