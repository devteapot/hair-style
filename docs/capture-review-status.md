# Capture review: saved evidence versus scan quality

The review screen now separately states whether the recording was saved or is incomplete, whether file-integrity checks passed, and that scan quality has not yet been verified. It explains that the image/depth viewer displays one recorded frame rather than a reconstructed head. Synthetic fixtures retain their own explanation.

The former “Evidence checks passed” label is now “Saved files are intact.” This prevents checksums and file presence from being presented as approval of coverage, motion or sharpness. Export/deletion and the existing frame viewer remain available. Explanatory text in this screen uses darker ink for readability on the fixed light theme.

This is a communication improvement, not automated capture-quality scoring. Coverage, subject motion, image sharpness and semantic masks still need implementation and validation. The app has not been reinstalled during the participant's replacement capture.

## Copied rear metadata

The local manifest inventory contains an earlier interrupted rear pass with 31 frames and a completed rear pass with 61 frames. All indexed frames declare depth payloads and matching RGB/depth timestamps. The interrupted pass records 11 tracking-initialization frames; the completed pass records three initialization frames and two excessive-motion frames, followed by/among 56 normal-tracking frames.

These are metadata observations only. Rear payload integrity, actual head coverage and metric calibration have not been verified from this inventory. The completed pass must not be assumed to be the replacement currently being recorded. The participant described a self-capture as poor and is redoing it with assistance; the earlier passes remain separate from reconstruction inputs.
