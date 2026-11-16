# Third-party notices

QuadDesk is distributed under the MIT license in LICENSE.

The virtual-display API declarations in `Sources/QuadVirtualDisplay` were informed
by [DeskPad](https://github.com/Stengo/DeskPad), copyright 2022 Bastian Andelefski,
MIT licensed. Its license is preserved in `LICENSES/DeskPad-MIT.txt`.

The optional `_AXUIElementGetWindow` declaration in `Sources/QuadDesk/Accessibility.swift`
was researched using [yabai](https://github.com/asmvik/yabai), copyright 2019
Åsmund Vikane, MIT licensed. Its license is preserved in `LICENSES/yabai-MIT.txt`.
QuadDesk implements its own runtime checks and window management.

Apple system frameworks are linked from macOS and are not redistributed.
The app has no third-party runtime dependencies. The optional Electron test
fixture contains receiver source only; Electron binaries and dependencies are
not included in this repository or release. Any separately downloaded Electron
runtime retains its own licenses and notices.
