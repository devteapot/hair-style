# Native tube/ribbon comparison

The guide lab and model review now offer **Compare preview renderers** for the
currently displayed revision. The screen prepares both derivatives off the main
thread and switches between them while retaining the camera pose. It shows the
same source revision, material colors and an eightfold diagnostic width in both
modes. It does not edit or select a haircut, or change the live renderer.

The scene refresh identity now includes representation, radial resolution and
radius scale as well as the canonical haircut hash. Previously a same-revision
renderer switch could leave the old scene geometry displayed. Accessibility
values identify the mesh actually installed in the scene, so UI checks can
distinguish a real geometry switch from a changed picker label.

## Geometry evidence

For the 763-guide fitted candidate used in the durable Swift delivery test:

| Representation | Vertices | Triangles |
|---|---:|---:|
| Three-sided tubes | 230,426 | 457,800 |
| Double-sided ribbons | 152,600 | 151,074 |

Both retain canonical revision
`eb3bb690068ddd5eb7f37f93a238752a0e2b51999c23c2ee5f24425cf3dcd51e`
and the same materials. Independent ribbon-pair midpoint replay against every
canonical guide point gives a maximum discrepancy of 1.39 × 10⁻¹⁷ m. Private
compiled artifacts and the numerical report are under
`outputs/renderer-comparison/`.

These counts are not runtime measurements. The ribbons are untextured flat strips
and can disappear edge-on. Neither representation reconstructs natural density,
individual follicles, or the participant's uncaptured loose-hair appearance.
Sustained phone performance, thermal behavior and visual quality across view
directions remain to be measured before selecting a production representation.

## Native verification

Seven ribbon/live-package contract tests, the unsigned iOS device build and two
simulator UI tests pass. The synthetic test checks tubes → ribbons → tubes using
the installed scene's method/count/source identity. The personal-candidate test
checks the exact counts above, unchanged revision identity, and unchanged saved
selection after leaving the comparison. Its first run exposed a test restoration
race; the corrected test waits for the prior studio to finish restoring before
replacing the isolated test fixture.

The personal tube and ribbon screenshots were inspected. Both retain the same
framing and guide layout; the strips show less apparent coverage at some angles.
They remain sparse research guides, not a realistic full hairstyle. Screenshots
are private under `outputs/renderer-comparison-personal-ui/` and
`outputs/renderer-comparison-synthetic-ui/`. The physical phone was not installed
or activated, and the default/live representation was not changed.
