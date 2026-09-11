# Automatic face landmark extraction

The shared core now runs Apple's Vision face-landmark request on verified saved capture images. The native review screen can display the resulting estimates over the original image; the Mac CLI exports a report. This is an initial automatic landmark candidate stage for M1.2/M1.3, not an accepted head registration, anatomical frame or hair analysis.

## Analysis and coordinates

The caller explicitly supplies the clockwise rotation that makes the face upright: none, 90°, 180° or 270°. Current captures preserve native sensor pixels but do not yet record device-to-upright orientation. Image mirroring and unexpected embedded EXIF orientation are rejected. Image decoding must agree with the manifest dimensions.

Vision request revision 3 and the 76-point constellation are pinned. A single face must pass the provisional detection confidence threshold (default 0.7). No face, multiple faces, low detection confidence and absent landmarks are distinct report statuses. Multiple faces are not resolved by silently picking the largest or most confident one. Model/framework errors propagate as errors.

Mac and physical iPhone requests use Vision's automatic compute-device selection. Simulator selects supported CPU devices for each reported compute stage: its default accelerator path failed to create an inference context in testing. The chosen policy is recorded in the report. If no supported CPU stage is available, extraction fails rather than returning an invented no-face result.

Vision's region-local normalized points are first mapped through its face bounding box into the upright image. Their lower-left origin is converted to top-left, then the supplied rotation is inverted to return native sensor pixels. This follows [Apple's landmark coordinate convention](https://developer.apple.com/documentation/vision/faceobservation/landmarks2d) and [ImageIO orientation definitions](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation). Tests independently derive one asymmetric point's expected native coordinates for all four rotations in a non-square image.

The resulting image rays are sampled with the existing calibrated depth adapter, including inverse lens point correction when needed. Invalid/missing depth or insufficient recorded confidence leaves the 3D point absent with a reason; it does not replace the depth with a model estimate. Valid depth at a pixel does not establish that it belongs to skin or that the anatomical landmark is accurate.

Reports bind to capture/frame IDs and the stored-frame hash, record OS version, request method, rotation and thresholds, and preserve Vision's region names and within-region indices. These names/indices are candidate labels, not verified anatomical side conventions or stable correspondence guarantees across large pose changes. Pupils may be inaccurate during blinking, as noted in the SDK headers. No automatic conversion to the four canonical-frame labels is performed.

## Native review

Open a saved pass, keep **Image** selected, choose **Rotation to upright for analysis**, and tap **Analyze face landmarks**. The display retains the original sensor image. Green points have usable recorded depth; amber points have no usable depth. The report remains temporary. Frame/orientation changes discard it, and superseded asynchronous results cannot overwrite the current review.

This does not start the camera or upload images. The existing capture export contains original evidence, not this temporary report. Use the CLI to save a standalone derived report.

## CLI

```sh
tools/dev.sh swift run capture-inspect face-landmarks \
  /path/to/bundle 0 clockwise90 outputs/landmarks.json
python3 tools/check_face_landmarks.py
```

Exit 0 means landmark estimates were produced, not that registration or capture quality passed. Exit 2 means a structured no-face/multiple-face/low-confidence/missing-landmarks result was written. Exit 1 means invalid evidence, arguments, decoding or model execution failed.

## Evidence and remaining validation

The real Vision request has run on the synthetic plane fixture, which correctly yields no face. CLI replay exercises all four rotations and rejects a tampered image. Core coordinate tests pass, and the native Simulator flow exercises the no-face response. These checks do **not** establish positive human detection quality, pixel/3D landmark accuracy, multiple-face recall, anatomical left/right interpretation or physical repeatability.

Positive validation needs consenting real captures with independently reviewed landmark overlays and depth samples, neutral/turned/blinking cases, multiple visible people, and the supported device matrix. Hair/clip/background segmentation, blur/exposure/motion gating, cross-frame correspondence and registration acceptance remain separate work. A face contour is not a complete skin or scalp mask.
