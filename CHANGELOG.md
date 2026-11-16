# Changelog

## 0.7.10-alpha.1 — 2026-11-16

- Add Screen Recording and Accessibility setup buttons, live permission status,
  installation-location guidance and a normal-quit action for permission changes.
- Enable window selection only after both permissions, and enable preview/work
  mode only with four distinct windows while setup is idle.
- Make setup resizable and vertically scrollable, with wrapping instructions.
- Start the 15-second preview after all four windows have been arranged. Keep
  independent, bounded watchdog phases for preparation and visible preview.
- Add readiness, setup construction and small-window scrolling regressions
  plus preview watchdog-phase regressions (72 Swift tests total), and a first-run
  verification checklist.
- Verified on the public app identity on one Apple Silicon Mac: four-app preview
  for 15.012 seconds after placement, then automatic display/window restoration
  with zero remaining recovery records. The downloadable app remains ad hoc
  signed and not notarized.

## 0.7.9-alpha.1

First public, MIT-licensed source snapshot and Apple Silicon test build.

- Native four-app desktop scaling without input forwarding.
- Normal-scale focus mode, Chrome native fullscreen detection and four-window return.
- Independent display watchdog and geometry recovery journal.
- Same-name window selection preservation and stale-window cleanup.
- 59 Swift tests and 6 optional receiver lifecycle tests.

Experimental, private-API based and not notarized. See README.md and docs/TESTING.md.
