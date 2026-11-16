# Public-identity onboarding validation — 0.7.10 candidate

Date: 2026-11-16. Environment: Apple Silicon, macOS 15.6 (24G84), one built-in
display. Public app ID: `io.github.TRN408.QuadDesk`; installed location:
`/Applications/QuadDesk.app`; app version/build: 0.7.10 / 32. Ad hoc signed.

This is a local test of the next candidate. It is not a claim that the current
0.7.9-alpha.1 release has the new onboarding controls. The Mac had previously
used a development app with a different bundle ID; it was stopped normally before
this test. Public-identity permissions initially showed as not granted. This is
not a second Mac, a fresh macOS account, or a quarantined browser-download test.

## Automated verification

- 72 Swift regressions passed with zero failures, covering readiness, real setup
  construction, wrapping/scrolling at 600×300, and independent watchdog phase limits.
- Native main app and independent watchdog built successfully.
- Six Node lifecycle regressions passed for the optional Electron fixture.
- Strict app/helper signature, package identifiers, version/build, bundled
  notices, ZIP contents and executable hashes verified.
- Installed main app and helper hashes match the tested package.

## Observed onboarding behavior

The permission, selection and physical-input checks were completed on build 31.
Build 32 also launched with its updated instructions and correctly blocked start
when both permissions became absent after re-signing. After replacing the stale
registrations, the owner and the app UI both confirmed the two permissions as
granted on the unchanged build 32; the app loaded nine window candidates.
The final preview was then started automatically through computer use and
cross-checked against the app's own placement, timer and restoration logs.
The settings UI after restoration still showed both grants, four retained
selections and an enabled preview button.

A follow-up diagnosis confirmed the cause of the enabled-but-ungranted state:
macOS TCC logged a failed code-requirement match for both Screen Recording and
Accessibility. The saved requirement still identified build 31's ad hoc code
hash, while the installed executable was build 32. The installed files matched
the verified build 32 package. Merely enabling the existing rows did not replace
that saved requirement. Only the public app's entries were removed and re-added
through System Settings, without modifying the app again.

| Check | Result |
| --- | --- |
| Open installed public-identity app | Passed; settings controls visible and instructions wrap |
| Both permissions absent | Passed; window menus and preview disabled |
| Screen Recording granted, Accessibility absent | Passed; Screen Recording updated to granted, preview remained disabled |
| Both permissions granted | Passed after replacing a stale Accessibility registration; app reports both granted and loads window list |
| Permissions granted but fewer than four targets | Passed; preview disabled |
| Four distinct selected windows | Passed; preview enabled |
| Duplicate target in two slots | Passed; preview disabled with selection guidance |
| Return to four distinct targets | Passed; preview enabled again |
| Work mode: four distinct apps | Passed on build 31; all four placements verified and visible state reached at 2880×1800 |
| Physical input and stop | Owner confirmed four panes visible, Chrome/Electron input and scrolling, and restoration using Control + Option + Esc on build 31 |
| Work-mode recovery records | Passed on build 31; remaining records zero, journal removed, original display verified |
| Build 32 permission repair and window list | Passed; owner and app UI both confirm two grants, candidates loaded, binary unchanged |
| Default 15-second display and automatic restoration | Passed on build 32; all four placements at 2880×1800, 15.012 seconds visible, original display and geometry restored, zero remaining records |
| Ready after automatic restoration | Passed on build 32; two grants retained, four selections retained, preview enabled |

Permission changes were authorized by the Mac owner; the owner performed the
Touch ID/password authentication. No TCC database resets or unrelated permission
changes were used. An existing Accessibility entry remained visually enabled
while the app's trust check was false. A simple toggle and restart did not fix it.
After identifying the public app through “Show in Finder”, removing only that
entry and adding the installed app again resolved it. This recovery path is in
[FIRST_RUN.md](FIRST_RUN.md).

## Runtime findings and fixes

On build 31, the original preview's 15-second limit could expire while Chrome
was still being arranged, before all four panes were visible. Work mode completed
all four placements and was used for the physical-input check. Build 32 moves
the 15-second countdown after successful four-pane placement. The independent
watchdog accepts exactly one `VISIBLE` phase transition, allows at most 25 seconds
for preparation and 25 seconds for the visible phase, and never extends previews
with heartbeats or repeated transitions. Work-mode heartbeat behavior is unchanged.

The build 32 runtime check exercised that phase extension: display preparation
took 16.534 seconds, and the owner stayed alive for 31.386 seconds after the
watchdog's initial READY, beyond the old 25-second total deadline. The visible
period lasted 15.012 seconds before automatic stop. The watchdog confirmed the
original display 5.268 seconds after stop; complete window restoration and the
settings result finished after 14.017 seconds. Chrome briefly failed an AX query
during restoration, then the bounded retry reacquired it and confirmed its
original logical frame. No failed recovery records or journal remained.

This build 32 check verifies automatic setup, placement, timing and restoration;
it does not substitute for a new physical keyboard-input test. The physical
input result above belongs to build 31. The tested build 32 executables and their
signatures were not modified during permission repair or runtime validation.

An attempt to include Finder failed to capture its original window state before
display configuration changed. No recovery journal or display change was left
by that attempt. Finder compatibility is unresolved; the successful four-app
test used TextEdit, a separate Chrome test window, an Electron fixture and an
AppKit fixture. This is not an all-app compatibility certification.

## Distribution limits

The local Gatekeeper assessment of the installed build 32 returned rejection
(exit 3). No Developer ID Application identity is available in the test environment;
Apple Development signing is not used as a substitute for public distribution.
The package is not notarized. It was launched locally without browser quarantine,
so this test does not prove the first-download Gatekeeper flow succeeds.

Another Mac, Intel, different macOS versions, physical focus/return shortcuts
(Control + Option + 1–4 / 0), sleep/wake, all-day sessions and complete IME
workflows remain unverified. The stop shortcut was owner-confirmed on build 31.
Earlier native-build recovery/fullscreen results are documented separately in
[TESTING.md](TESTING.md), not counted as new-candidate first-run results here.
