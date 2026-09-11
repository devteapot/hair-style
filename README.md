# Personalized Hair — iOS technology preview

A native iOS experience that captures a person's head and hair, generates a haircut specifically for them, and presents the same design on an interactive 3D head and in a live camera preview.

This is a technology preview under active development, not a validated haircut recommendation product. The public repository contains source, specifications, tests, and synthetic fixtures. Participant captures, personal assets, model weights, and local verification evidence are excluded; links to local evidence in the research notes will not resolve in a fresh clone.

The M0 native capture/replay harness is implemented and builds for iPhone and Simulator. It records synchronized front TrueDepth evidence and rear ARKit image/depth/pose evidence, reviews individual frames in 3D, and exports checksummed ZIP bundles. Physical sensor validation, head reconstruction, personalized generation, and live haircut preview remain in progress.

- [Product and technical specification](docs/product-technical-spec.md): scope, experience, capture, generation, representations, architecture, and data contracts.
- [Implementation and validation plan](docs/implementation-plan.md): milestones, experiments, acceptance criteria, and unresolved decisions.
- [Implementation status](docs/implementation-status.md): verified progress and remaining gates.
- [Capture bundle format](docs/capture-bundle-format.md): coordinates, calibration, integrity and replay.
- [Landmark registration](docs/registration.md): rigid alignment and calibrated depth selection with independent validation.
- [Observed surfaces](docs/observed-surface.md): masked depth triangulation and registered fusion with per-vertex evidence.
- [Experimental surface remeshing](docs/surface-remeshing.md): shared local surface extraction, topology checks and physical replay limitations.
- [Anatomical frame](docs/anatomical-frame.md): explicit landmark selection and rigid conversion to canonical head coordinates.
- [Face landmarks](docs/face-landmarks.md): Vision estimates mapped to native capture pixels, optional calibrated depth and review overlays.
- [Canonical haircut contract](docs/haircut-contract.md): scalp-bound guides, regional edits, validation and immutable revision storage.
- [Guide clearance](docs/guide-clearance.md): capsule/triangle checks against supplied face and ear surfaces and optional edit rejection.
- [Native guide studio](docs/guide-studio.md): synthetic 3D guide inspection, preview/save, original comparison and persistent undo/redo.
- [Research inventory](docs/research-inventory.md): inspected model sources and integration constraints.

## Build and test

Requires a full Xcode installation and XcodeGen. `tools/dev.sh` selects `/Applications/Xcode.app` or `/Applications/Xcode-Beta.app` for that command without changing the machine's global developer directory. Set `DEVELOPER_DIR` explicitly to use another installation.

```sh
tools/dev.sh swift test
xcodegen generate --spec ios/project.yml
tools/dev.sh xcodebuild -project ios/PersonalizedHair.xcodeproj \
  -scheme PersonalizedHair -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

Open `ios/PersonalizedHair.xcodeproj` in Xcode, select your development team and a compatible physical iPhone, and run. The provisional deployment target is iOS 18. No signing team is embedded in source. Physical front TrueDepth and assisted rear LiDAR passes have been recorded and replayed; complete coverage and measured calibration remain unverified.

The app checks camera capabilities and asks the subject to agree before starting a local capture. Simulator users can open **Capture lab → Create synthetic calibration fixture** to exercise review, 3D point-cloud inspection, ZIP export and deletion. That fixture is explicitly synthetic and does not stand in for a scanned face.

**Capture lab → Open synthetic guide studio** exercises canonical guide rendering and edits, immutable revision selection, original comparison and saved undo/redo. Its two curves and scalp plane are engineering fixtures, not personalized generated hair.

For UI tests, obtain a simulator ID with `tools/dev.sh xcrun simctl list devices available`, then run:

```sh
tools/dev.sh xcodebuild -project ios/PersonalizedHair.xcodeproj \
  -scheme PersonalizedHair -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
```

## Inspect a capture on the Mac

```sh
tools/dev.sh swift run capture-inspect fixture outputs/fixtures
# Substitute the bundle path printed by the previous command:
tools/dev.sh swift run capture-inspect inspect /path/to/bundle
tools/dev.sh swift run capture-inspect ply /path/to/bundle 0 outputs/frame.ply
python3 tools/doctor.py --output outputs/environment.json
tools/dev.sh swift run capture-inspect register fixtures/registration/asymmetric.json outputs/registration.json
python3 tools/check_registration.py
python3 tools/check_surface.py
python3 tools/check_anatomical.py
python3 tools/check_face_landmarks.py
python3 tools/check_haircut.py
python3 tools/check_clearance.py
```

Unzip an exported capture before inspecting it. The `ply` command exports a single camera-space point cloud; the separate `surface` command exports a partial registered mesh. Neither completes hidden head anatomy. Real subject evidence, generated outputs, research checkouts and build products are ignored by Git. Do not store private captures under `docs/`.

The first complete product demonstration still requires a custom haircut from a real capture, a meaningful edit, and the same revision in both preview modes. See the implementation status for what remains.

For capture-wide rear spatial masks and an unmerged multi-view inspection, see [rear spatial filtering](docs/rear-world-region.md). This preview still requires subject-motion correction and semantic filtering.

A local Mac Object Capture worker can now create a textured diagnostic USDZ from a rear RGB/depth bundle. The iPhone app opens it through **Capture lab → Open reconstructed head**. See [Object Capture reconstruction and preview](docs/object-capture-reconstruction.md) for commands and current limitations.
