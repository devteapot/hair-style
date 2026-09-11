# Local Object Capture reconstruction and native preview

The Mac reconstruction worker now runs Apple's RealityKit `PhotogrammetrySession` on the existing rear capture. This complements the depth-only alignment experiments with RGB feature matching. No participant upload or external GPU service is involved.

```sh
tools/dev.sh swift build --product head-photogrammetry
.build/debug/head-photogrammetry CAPTURE_BUNDLE REGION_REQUEST.json NEW_OUTPUT_DIRECTORY
tools/dev.sh swift tools/render_model_preview.swift NEW_OUTPUT_DIRECTORY/preview.usdz OUTPUT.png
tools/dev.sh swift tools/render_model_preview.swift NEW_OUTPUT_DIRECTORY/preview.usdz CLAY.png clay
```

This experimental worker requires a supported Mac running macOS 15 or later and 20–120 usable rear samples. It verifies the source bundle, builds explicit spatial masks, loads original JPEGs without changing their native orientation, and supplies masks at the decoded image dimensions plus aligned native Float32 depth in meters. Depth outside the mask, invalid ranges or insufficient confidence remains unavailable. Mask enlargement replicates depth-mask cells into the RGB raster; it is not a semantic image segmentation model.

Configuration: sequential images, high feature sensitivity, object masking, preview detail. The worker requests both a USDZ model and estimated camera poses. It records source frame/image hashes, selected masks, processing events, skipped samples and result status. Request processing has a ten-minute cancellation timer; input preparation/session initialization occurs before that timer. No external gravity or camera-pose guess is supplied.

Apple's reconstruction can interpolate or complete surfaces without exposing measured/inferred provenance per vertex. The output therefore stays `acceptedForHeadFitting: false`, even when processing succeeds. Its camera coordinate system, depth-derived scale, hidden anatomy and front-pass registration still require validation.

## Assisted capture result, 2026-09-10

- 83 RGB/depth samples submitted; 68 estimated poses returned.
- Frames 20–34 (15 samples) skipped by the reconstruction. The API reports low quality or registration issues without distinguishing the cause.
- Preview USDZ exported successfully with an embedded color texture: 4,719 imported vertices and 9,434 triangles.
- Imported bounding extents approximately 268 × 237 × 189 mm. These are model bounds including hair, not validated anatomical measurements.
- Processing requests completed in approximately 18.0 seconds after preparation and session initialization. Total wall-clock preparation time was not recorded for this first run; the worker now records both times on future runs.
- Textured and clay four-view renders inspected. Front and both profiles are recognizable with texture. The clay surface exposes coarse face/ear shape, rear hair/bun geometry and filled/cropped lower regions. Texture quality must not be used as proof of geometry accuracy.
- A vendor asset-reference warning appeared during export. The resulting USDZ contains its texture and renders on both Mac and iPhone.

Private output: `outputs/object-capture-rear/`. Original captures are unchanged. The current USDZ is an inspection artifact, not an accepted scalp or generated haircut.

## iPhone inspection

**Capture lab → Open reconstructed head** opens a locally stored/imported USDZ. The screen supports drag/pinch camera controls, view reset, a photo-texture versus clay toggle, export and explicit deletion. Import validates a bounded file and geometry before replacing the local preview. Stored files receive data protection and backup exclusion. Captures and this preview remain separate; deleting one does not imply deleting the other.

The reconstructed model was staged in the simulator and copied into the physical iPhone's app data. UI tests exercised the loaded-model branch, rotation, texture toggle and reset on simulator and physical iPhone. Final device screenshots were inspected for framing and readability, and a device round-trip hash confirmed the USDZ bytes match the Mac result. The full Swift core suite passes 72 tests. The initial empty-state test exposed an accessibility-query issue in the test, which was corrected. Participant screenshots and result bundles remain ignored local evidence; they are not published in docs.

The next technical step is to assess the returned camera poses/scale against captured evidence and register front TrueDepth detail into this reconstruction, while separating hair/bun from scalp inference. Real strand generation and the end-to-end personalized haircut flow are still outstanding.

## Primary references

- [Apple: creating 3D objects from photographs](https://developer.apple.com/documentation/realitykit/creating-3d-objects-from-photographs)
- [PhotogrammetrySample object masks](https://developer.apple.com/documentation/realitykit/photogrammetrysample/objectmask)
- [PhotogrammetrySample depth maps](https://developer.apple.com/documentation/realitykit/photogrammetrysample/depthdatamap)
- [PhotogrammetrySession configuration](https://developer.apple.com/documentation/realitykit/photogrammetrysession/configuration-swift.struct)
