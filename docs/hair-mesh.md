# Hair mesh compilation

`HairMeshCompiler` turns validated canonical guide centerlines into capped indexed tube meshes. The derivative retains haircut ID, revision, exact haircut hash and scalp hash, together with material records, radial resolution and any diagnostic radius scaling. It never replaces the editable guide asset.

The default output has six radial sides and uses recorded material radii. The compiler builds a ring at each guide point, propagating a normal by tangent-plane projection to reduce frame discontinuities. Vertices/normals are shared by batches grouped by material and anatomical region; triangle indices use UInt32. End caps close each guide. A reversing centerline with an undefined centered tangent is rejected.

The compiler rejects output exceeding 250,000 vertices instead of silently dropping guides or changing detail. Radial sides can be selected from 3–12. Radius scale 1 is the material radius; larger scales through 100 are diagnostic and recorded explicitly. Sampling reduction, density interpolation, hair cards, UV/textures, advanced hair shading and LOD selection remain future work. Tube overlap at sharp bends and self-intersection are not a physical-quality guarantee.

The synthetic native studio uses a radius scale of 30 with its 50 µm material, preserving the previous 1.5 mm diagnostic appearance. It now adds a hair geometry node per batch rather than a cylinder node per segment. Region colors and root dots remain diagnostic. The studio retains its 2,000-segment interaction limit; the compiler's larger budget is not a validated phone performance limit. Mesh compilation is synchronous for this bounded lab; production compilation must run off the main thread or arrive as a validated derivative.

Tests check root/tip ring centers, radii, normals, triangle bounds/areas, determinism, source identity after edits, stale-input rejection and output-budget enforcement. Native UI tests exercise preview/save/compare/undo/redo/relaunch. These checks do not prove live-camera alignment, sustained FPS, photorealism or a complete hairstyle.
