# Contributing

Issues and pull requests are welcome. Check existing issues and keep each change
focused. Include macOS version, chip, display topology, reproducible steps and
whether recovery returned the original display and windows. Redact screenshots,
window titles, documents and logs before attaching them.

Run the commands in README.md. Keep display/input integration tests manual and
explicit; never make CI change display configuration or send input to other apps.
Preserve recovery records on failure, use exact process/window identities, and
do not lengthen watchdog deadlines to hide a blocked main loop.

The core native build uses Apple frameworks only. Node.js is optional for the
fixture lifecycle tests; no dependency installation is needed for those tests.
The optional Electron fixture requires a separately obtained official runtime
and its notices. Do not commit runtimes, signing identities, certificates,
recovery journals, screenshots or personal paths.

For permission-flow validation, finish the candidate build and package checks
before granting permissions. Install that exact app in Applications and keep its
executables unchanged throughout manual testing. Rebuilding or re-signing an ad
hoc candidate can invalidate the existing grants even if System Settings still
shows enabled switches. Confirm the app's preflight status, not just the switches.
If macOS logs a code-requirement mismatch, quit the app and replace only its
identified entries in the two privacy lists with the installed candidate. Never
reset unrelated apps' permissions or treat an enabled stale entry as a pass.
Record which build was physically tested; copying a verified ZIP without
re-signing preserves that candidate's code identity.
See also [Apple DTS on stable signing and TCC](https://developer.apple.com/forums/thread/730043).

By contributing, you agree that your contributions are licensed under this
repository's MIT license. Substantial changes should include meaningful regression
coverage and a clear statement of manual validation limits.
