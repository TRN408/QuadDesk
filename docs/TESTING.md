# Validation scope

This is an experimental alpha. A passing unit test is not proof of reliable
physical input or display recovery on a different Mac.

## Automated checks

- 72 Swift tests: layout, window identity, recovery records, capture/input
  regression behavior, watchdog leases, expansion detection, setup readiness,
  actual setup construction, width-constrained scrolling at 600×300, and bounded
  preparation/visible preview watchdog phases.
- 6 Node tests for the optional Electron receiver lifecycle (no Electron runtime needed).
- Native app/helper builds, ad hoc signatures, ZIP integrity and bundled license notices.
- A source publication audit excludes personal development history, window
  titles, recovery journals, signing credentials and home-directory paths.

CI never creates a virtual display or controls a user's apps.

## Real-machine checks before the public snapshot

On Apple Silicon, macOS 15.6, one built-in display with original logical
1440×900 / Retina scale 2:

- Four real selected windows on a 2880×1800 logical desktop.
- User-confirmed native mouse/keyboard operation in Discord in an earlier native build.
- About seven minutes of work mode, ordinary restoration and independent display
  restoration after terminating the main app in earlier native builds.
- Chrome green-button native fullscreen and ordinary maximize both restore
  1440×900 / scale 2 and a normal-scale focused window.
- Returning to all four windows, preserving the original recovery record through
  those transitions, and ordinary quit restoring all four with zero pending records.

The 0.7.10 candidate has a separate local
[public-identity first-run report](FIRST_RUN_RESULTS.md) and
[manual checklist](FIRST_RUN.md). Its onboarding and work-mode checks were run on
the same Mac with initially absent public-bundle permissions, not another Mac.
Build 32 completed an automatically driven four-app preview: 15.012 seconds
after placement, followed by verified display/window restoration with zero
remaining recovery records. Preparation took about 17 seconds and complete
restoration about 14 seconds on this run; display switching is not instantaneous.
The 0.7.9-alpha.1 downloadable release has not received those changes.
The app is not notarized. No all-day, sleep/wake, Intel, external-display or full
IME certification is claimed. Focus/return shortcuts still require physical
keyboard validation; the owner confirmed the stop shortcut on build 31.
Automated app-directed key events are not equivalent to physical-key checks.

## Manual Chrome scale regression

Open `Tests/Fixtures/BrowserScaleProbe.html` in a separate Chrome window. Note the
fixed 24px text at normal display scale. Select it plus three other app windows,
start work mode, and press its green button. Verify normal display scale and the
same readable text size, return to four windows, and repeat with ordinary zoom.
Quit QuadDesk and verify the original display and window positions. Close only
the test window. Do not use personal messages or production documents for test input.
