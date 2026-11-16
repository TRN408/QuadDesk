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
