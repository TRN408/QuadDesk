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

By contributing, you agree that your contributions are licensed under this
repository's MIT license. Substantial changes should include meaningful regression
coverage and a clear statement of manual validation limits.
