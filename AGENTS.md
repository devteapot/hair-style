# Working on Personalized Hair

- Continue toward the full scope in `docs/implementation-plan.md`; distinguish
  software verification from physical capture accuracy and styling quality.
- The owner requested commits and pushes as verified progress is made. Commit
  coherent checkpoints and push to the configured GitHub remote.
- The repository is public. Keep participant captures, personal head/hair assets,
  model weights, credentials, and local evidence out of commits. Preserve the
  exclusions in `.gitignore`; do not force-add excluded artifacts.
- Run Swift, Xcode, and xcrun commands through `tools/dev.sh`. The Xcode project
  is generated from `ios/project.yml` with XcodeGen.
- Do not install a phone build or activate its camera while a participant may
  be recording. Read-only device inventory and local development can continue.
