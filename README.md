# QuadDesk

Four full-size Mac app windows, scaled onto one display. Focus any quadrant to
read and work at the normal display scale, then return to four windows.

[日本語](README.ja.md) · [Download 0.7.10 alpha](https://github.com/TRN408/QuadDesk/releases/tag/v0.7.10-alpha.1) · [MIT license](LICENSE)

**Free and open source. Experimental alpha, not a finished window manager.**

## What it does

- Arranges four real app windows on a larger virtual desktop and mirrors it to
  your display. Mouse, keyboard and scrolling go directly to the original apps.
- Uses the available area without an extra QuadDesk frame around each app.
- Restores normal display scale when a selected window is maximized or enters
  fullscreen, including Chrome's green button. App font and browser zoom settings
  are preserved.
- Keeps original window positions for restoration and uses a separate display
  watchdog if the main process exits or stops responding.

## Requirements and limits

macOS 14 or later is required by the code. The current app download is **Apple
Silicon (arm64)**; real-machine validation has been on macOS 15.6 with one built-in
display. Intel Macs and other macOS versions are unverified. External displays
and existing mirroring are rejected before the app changes display settings.

The app uses private virtual-display APIs. OS updates can break compatibility.
All menus, the Dock and other windows become smaller in four-window mode because
the entire desktop changes scale. Switching can briefly blank or move windows.
Multiple windows of the same app already on different Spaces may not be found.
Long sessions, sleep/wake and all IME workflows are not yet validated.
Finder's original window state could not be captured on the tested Mac; choose
another normal app window for now.

## Install

1. Download `QuadDesk-0.7.10-alpha.1-macos-arm64.zip` from the
   [alpha release](https://github.com/TRN408/QuadDesk/releases/tag/v0.7.10-alpha.1).
2. Extract and move `QuadDesk.app` to Applications before granting permissions.
3. Open it and use the Screen Recording and Accessibility setup buttons to grant
   both permissions in macOS System Settings. Restart QuadDesk after permission
   changes if necessary, then check that the app reports both grants.

Version 0.7.10 adds permission-setting buttons, automatic status checks and
start-button gating. See the [first-run checklist (Japanese)](docs/FIRST_RUN.md),
including how to identify the correct app and replace stale permission entries
after updating an ad hoc signed build.

The download is ad hoc signed and **not Apple-notarized**. macOS may block it on
first launch. Review the source or build locally if you prefer; consult
[Apple's app-opening guidance](https://support.apple.com/en-us/102445) if you
choose to trust the downloaded build. Do not disable Gatekeeper or SIP.

## Use

Select four different normal app windows. The default preview lasts 15 seconds
after all four windows are arranged; preparation has a separate 25-second
watchdog limit. Enable work mode for use until stopped. The app attempts to
leave fullscreen/minimized state before saving each window's normal geometry.
On stop it restores that normal geometry, not the original fullscreen Space.

| Action | Shortcut / alternative |
| --- | --- |
| Focus quadrant 1–4 at normal scale | Control + Option + 1–4, or grid menu |
| Return to four windows | Control + Option + 0, grid menu, or Dock in focus mode |
| Stop and restore | Control + Option + Esc, grid menu, or quit QuadDesk |

Clicking QuadDesk in the Dock while four windows are active stops the session.
Only selected windows trigger automatic focus. Windows closed during a session
must be selected again; another app is never chosen as their replacement.

## Build and test

Install Xcode / Command Line Tools with a Swift 5.9+ toolchain. Development has
used Swift 6.2.4. No Swift package dependencies or account keys are required.

```sh
git clone https://github.com/TRN408/QuadDesk.git
cd QuadDesk
bash scripts/validate_native_windows.sh "$PWD/dist/QuadDesk.app"
# Optional receiver lifecycle tests, with Node.js 18+:
node --test Tests/Fixtures/ElectronInputProbe/lifecycle.test.cjs
python3 scripts/verify_package.py dist/QuadDesk.app
```

Open `dist/QuadDesk.app`. The build defaults to ad hoc signing; an optional
`QUADDESK_SIGN_IDENTITY` can select a certificate you own. Public builds use
`io.github.TRN408.QuadDesk`. Test/build commands do not change display settings.

See [testing](docs/TESTING.md), [architecture](docs/ARCHITECTURE.md),
[privacy](PRIVACY.md), and [contributing](CONTRIBUTING.md). Known validation limits
are described in the testing document. The public repository starts from a
clean source snapshot; personal development logs and old local history are not
part of the publication.

## License

MIT: use, modify and redistribute, including commercially, while preserving the
license notices. See [third-party notices](THIRD_PARTY_NOTICES.md).

## Mobile browser (unreleased on this branch)

Open **モバイルブラウザを開く** from setup or the Browser menu. Three independent
live WebKit columns open initially; add up to six. Each has its own URL field,
back/forward, reload/stop and close controls. Choose 320, 390 or 430 CSS points,
or desktop width (1024). Overflow scrolls horizontally without shrinking text.
Changing width reloads that page. New-window links open in a new column if one
is available. The mobile user agent requests mobile site variants; this is
macOS WebKit, not iOS or touch emulation. Site compatibility varies.

All columns share a persistent QuadDesk website data store, separate from
Safari/Chrome. Existing browser logins are not imported. Closing the browser
releases its pages; tab URLs/layout are not restored. Downloads, external-app
links and extensions are not supported. See [Privacy](PRIVACY.md).

Run `./dist/QuadDesk.app/Contents/MacOS/QuadDesk --mobile-browser` for browser-only
mode, without Screen Recording/Accessibility permission or display changes.
