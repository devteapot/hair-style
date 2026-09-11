# Accessibility verification

Current status (2026-09-11): the main guided-preferences Dynamic Type audit now passes after replacing the lazy form with eagerly laid-out scrolling cards. The combined test remains failing on a subsequent scrolled contrast audit for the regional-range status text. No issue is filtered or waived; see the latest findings below.

The native home/guided-preference test runs XCTest contrast, sufficient-description, clipping, Dynamic Type and hit-region audits. Issues are not filtered or waived. This is partial coverage of the consumer preview; capture, live rendering, editing, exports and VoiceOver task completion still need separate evaluation.

The initial home audit failed contrast on the small green app heading. The accent was darkened, home secondary text now uses an explicit darker color, and the serif headline uses a scaled metric. The subsequent home audit passed the selected audit categories in the simulator.

The guided preferences audit still fails Dynamic Type on preference labels. Inline picker rows were replaced by two-line name/value links and full selection screens, with scalable wrapping text and selected traits. The failure remains reproducible on a styling-products label. It has not been suppressed or called a false positive. The next investigation is actual accessibility-size layout/label measurements, followed by a full rerun. Current failing result: `Test-PersonalizedHair-2026.09.11_03-22-29-+0200.xcresult`; local issue screenshots are retained under `outputs/accessibility-preferences-fourth/`.

These UI changes do not establish a completed accessibility pass or physical-device readability. The installed phone build has not been replaced during this work.

## Direct large-text check

A separate simulator test launches at the default large category and accessibility XXXL, navigates to the same preference row and measures its rendered bounds. The styling-products row grows from 73.667 points to 220.333 points; the test passes. The retained XXXL screenshot was inspected: the preference name wraps across two lines and its value remains visible without clipping. Evidence: `Test-PersonalizedHair-2026.09.11_03-24-43-+0200.xcresult`, with screenshots under `outputs/preference-scaling/`.

Rows now expose a single accessibility label for the preference name and a separate selected value. The automated Dynamic Type audit still reports partial support (`Test-PersonalizedHair-2026.09.11_03-26-17-+0200.xcresult`), despite the direct scaling evidence. That discrepancy remains unresolved; the direct test does not waive the audit failure or prove all labels and states work at every size.

The dedicated selection-screen test passes contrast, sufficient-description, clipping, Dynamic Type and hit-region audits, then chooses “No” for heat tools and verifies the parent row announces that value. This test exposed a restoration bug: navigating back reloaded the saved document and discarded the unsaved choice. Restoration now runs only on the first appearance of each form instance. The corrected interaction passes (`Test-PersonalizedHair-2026.09.11_03-28-39-+0200.xcresult`). Native button semantics are retained; labels do not hide the actionable control.


## Eager preference layout and remaining scrolled contrast finding

The previous Dynamic Type failure reproduced on `Styling products` in `03-51-17`. Removing the explicit accessibility label did not resolve it (`03-52-25`); that experiment was reverted. Replacing the main preference `Form` with a `ScrollView` and eager card stack allowed the initial combined contrast/description/clipping/Dynamic Type/hit-region audit to pass (`03-53-43`, repeated `03-55-58`). This is evidence for the layout change, not a definitive diagnosis of framework internals.

Navigation rows retain separate accessible names/values, gain explicit chevrons and minimum 44-point content height, and wrap with leading alignment. Save is visually prominent. The selection-screen interaction/audit still passes. A direct default-to-accessibility-XXXL check passes, with the product row growing from 44 to 190.333 points; the inspected screenshot shows wrapped readable labels and values. Save/edit/export-availability/relaunch preservation passes with the displayed haircut hash unchanged (`03-55-58`).

The scrolled audit now includes Dynamic Type as well as the other original categories. It fails contrast on `1 regional ranges set.` The diagnostic handler logs the issue and returns false, so failure is preserved. Its reported element frame and cropped attachment require further investigation; this is not waived as a framework false positive. Local test logs are `/tmp/preferences-eager-complete.log`, and the retained result is `Test-PersonalizedHair-2026.09.11_03-55-58-+0200.xcresult`. Full accessibility, physical-device readability and VoiceOver task completion remain unverified.

After the final chevrons/leading-alignment/save-button changes, the unsigned iPhone build passes and the largest-text test passes again (`Test-PersonalizedHair-2026.09.11_03-57-42-+0200.xcresult`). The inspected final screenshot is retained under `outputs/preferences-final-scaling/`; the product row remains 190.333 points high with readable wrapping and no truncation. The phone's installed capture build was not replaced.


## Fresh scrolled audit and save-label correction

A new fresh-launch scrolled audit reproduces the same contrast failure on the regional-range status (`03-59-34`). This rules out the preceding Dynamic Type audit as a necessary trigger. Both the original and fresh-launch tests remain enabled with all categories and no suppression.

Inspection of its full screenshot also exposed a separate visible regression: the prominent Save button inherited the form's dark foreground, making its label disappear against its dark fill. The button now has an explicit white foreground. The final screenshot was inspected and shows a readable “Save design brief” label (`outputs/preferences-save-label-fixed.png`); the unsigned iPhone build passes. Both contrast audits still fail on the range-status node (`Test-PersonalizedHair-2026.09.11_04-00-27-+0200.xcresult`). The rendering correction does not close that separate audit finding.

## Regional range summary and audit discrepancy

The range count is now a visible subtitle of the “Regional length ranges” navigation row and its accessibility value, rather than a separate status element. Singular/plural wording is corrected; the subtitle uses medium-weight black text on the white card. The optional preference controls and saved-brief semantics are unchanged.

The scrolled contrast finding persists. Hiding the iOS 26+ scroll-edge effect and forcing an opaque navigation bar did not resolve it; that experiment was removed. Explicit clipping did not resolve it either and was removed. The audit also reported a partially scrolled “Length” heading during one intermediate layout. No issues are filtered, and no passing accessibility gate is claimed.

The latest retained failed audit is `Test-PersonalizedHair-2026.09.11_04-50-24-+0200.xcresult`. Its element crop under `outputs/preferences-black-summary-failure/` was inspected: the two dominant RGB values are white (18,657 pixels) and black (3,114 pixels), with antialiased edge shades. This documents a discrepancy between the exported black-on-white rendering and the framework's generic contrast failure, which supplies no measured ratio. It does not establish full-screen, all-state, physical-device or VoiceOver accessibility, and the audit remains unresolved.

The final range-row interaction test passes (`04-51-13`): the range summary exposes a nonempty accessibility value, that value survives save/relaunch, the selected range remains editable, and the displayed haircut hash stays unchanged. Its screenshot under `outputs/preferences-range-summary/` was inspected. The final unsigned iPhone build passes; the installed capture build remains unchanged.
