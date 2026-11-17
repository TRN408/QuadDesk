# Architecture

`QuadDesk` is a Swift/AppKit app. The packaged native path uses
`NativeWindowsController`, `QuadNativeDisplay` and `QuadVirtualDisplay`.

1. Check permissions and reject unsupported existing display topologies.
2. Resolve four explicit window identities and save their normal geometry.
3. Arm `QuadDisplayWatchdog` before creating a temporary virtual desktop.
4. Mirror that desktop to the physical display and arrange the real windows.
5. Detect enlargement or focused native fullscreen using bounded, serialized
   background AX reads. Confirm twice; discard results from old layout generations.
6. For four-to-one, restore the physical display first, normalize fullscreen,
   then fill the normal display. For one-to-four, normalize before rebuilding.
7. On stop, restore recorded windows. Preserve unresolved recovery records.

The watchdog accepts only its correctly bundled parent, keeps the original
display snapshot, and uses a fixed preview deadline or work-mode heartbeats.
It never accepts an arbitrary process ID from the command line. Display changes
are app/session scoped, not permanent settings.

`QuadCore` and `QuadDisplayCore` contain value-based logic tested without display
mutation. Legacy capture/input sources remain for regression research, but are
not the packaged native app's entry path. Optional fixtures are separate from
the runtime. API references and licenses are in THIRD_PARTY_NOTICES.md.


The optional `MobileBrowserController` owns an ordinary resizable AppKit window
with a two-row grid of fixed-viewport `WKWebView` panes.
`BrowserGridPlan` computes uniform fitting without gutters or cropping. Each
`ScaledBrowserTile` uses an AppKit bounds/frame transform around a 390×844
reference canvas, so WebKit CSS widths and native input coordinates are
preserved while the whole pane is scaled. It does not use
capture, synthetic input, AX, virtual displays or the watchdog. Each column has
native WebKit navigation and input; the default website data store is shared
and persistent. Mobile widths use a mobile user agent; desktop mode resets it.
`--mobile-browser` uses a separate app delegate that bypasses native workspace
setup and permission checks. HTTP is allowed only in web content by the bundle's
ATS configuration so user-entered local/intranet HTTP pages can load.
