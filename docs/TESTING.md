# Validation scope

This is an experimental alpha. A passing unit test is not proof of reliable
physical input or display recovery on a different Mac.

## Automated checks

- 59 Swift tests: layout, window identity, recovery records, capture/input
  regression behavior, watchdog leases and expansion detection.
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

The public bundle ID and ad hoc package have automated validation; a clean-Mac
permission flow for this newly named bundle has not been manually completed.
The app is not notarized. No all-day, sleep/wake, Intel, external-display or full
IME certification is claimed. Global keyboard shortcuts still require physical
keyboard validation; automated app-directed key events are not equivalent.

## Manual Chrome scale regression

Open `Tests/Fixtures/BrowserScaleProbe.html` in a separate Chrome window. Note the
fixed 24px text at normal display scale. Select it plus three other app windows,
start work mode, and press its green button. Verify normal display scale and the
same readable text size, return to four windows, and repeat with ordinary zoom.
Quit QuadDesk and verify the original display and window positions. Close only
the test window. Do not use personal messages or production documents for test input.
