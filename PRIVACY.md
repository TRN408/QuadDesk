# Privacy

The four-app workspace has no analytics, QuadDesk account system or update
service. It does not save video, audio or typed content. Input goes to the
original Mac apps; QuadDesk does not forward or record their keystrokes.

The optional mobile browser loads websites directly with macOS WebKit. Those
sites receive normal browser requests and any information you enter into them.
All columns share WebKit's persistent default website data store: cookies,
logins, caches and site storage can remain on this Mac after closing the app.
This store is separate from Safari/Chrome and is not copied from those browsers.
QuadDesk does not save a separate browsing history or tab URL list. Closing a
column stops its page; closing the browser window releases all its web views.
Browser-only mode (`--mobile-browser`) needs no Screen Recording or
Accessibility permission and makes no display or other-app window changes.

Screen Recording is used to enumerate shareable windows. Accessibility is used
to identify, focus, resize and normalize the selected windows. The default app
does not start a screen-recording stream.

The local recovery file is
`~/Library/Application Support/QuadDesk/window-recovery.json`.
It contains selected window titles, IDs, app bundle IDs, process launch dates and
original geometry. It is stored with owner-only file permissions, and removed
after successful recovery. macOS unified logs include display/window IDs,
geometry, lifecycle and error diagnostics. Review them before sharing reports.

Legacy capture/input modules and optional input receiver fixtures are retained
for development. Their entry point is not used by the packaged native app.
Fixtures can record test input lengths, event coordinates and counters locally;
they are not distributed as app runtimes. Existing apps and browser extensions
continue to have their own independent network and privacy behavior.
