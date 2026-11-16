#!/usr/bin/env python3
"""Package the native app without selecting a developer's private identity."""
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def signing_identity():
    return os.environ.get('QUADDESK_SIGN_IDENTITY') or '-'


def main():
    executable = Path(sys.argv[1]).resolve()
    destination = Path(sys.argv[2]).resolve()
    helper = executable.parent / 'QuadDisplayWatchdog'
    if destination.suffix != '.app' or destination.exists() or destination.with_suffix('.zip').exists():
        raise SystemExit('Choose a fresh destination ending in .app (no existing app or ZIP)')
    if not executable.is_file() or not helper.is_file():
        raise SystemExit('Build both QuadDesk and QuadDisplayWatchdog first')
    root = Path(__file__).resolve().parent.parent
    identity = signing_identity()
    with tempfile.TemporaryDirectory(prefix='quaddesk-package-') as temporary:
        app = Path(temporary) / 'QuadDesk.app'
        main_binary = app / 'Contents/MacOS/QuadDesk'
        guard_binary = app / 'Contents/Helpers/QuadDisplayWatchdog'
        for source, target in [(executable, main_binary), (helper, guard_binary)]:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            target.chmod(0o755)
            subprocess.run(['/usr/bin/strip', '-S', '-x', str(target)], check=True)
        resources = app / 'Contents/Resources'
        resources.mkdir()
        for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md']:
            shutil.copyfile(root / name, resources / name)
        shutil.copytree(root / 'LICENSES', resources / 'LICENSES')
        info = {
            'CFBundleExecutable': 'QuadDesk', 'CFBundleIdentifier': 'io.github.TRN408.QuadDesk',
            'CFBundleName': 'QuadDesk', 'CFBundleDisplayName': 'QuadDesk',
            'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.7.10',
            'CFBundleVersion': '32', 'LSMinimumSystemVersion': '14.0',
            'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
            'QuadDeskNativeWindowsPreview': True,
            'NSScreenCaptureUsageDescription': 'Enumerate selected windows for the four-app workspace. No video is saved or sent.',
        }
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        for target in [guard_binary, app]:
            subprocess.run(['/usr/bin/codesign', '--force', '--sign', identity, '--timestamp=none', str(target)], check=True)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['/usr/bin/ditto', '--norsrc', '--noextattr', str(app), str(destination)], check=True)
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', str(app), str(destination.with_suffix('.zip'))], check=True)
    print('Packaged native QuadDesk 0.7.10 (ad hoc; not notarized)' if identity == '-' else 'Packaged with the explicitly selected signing identity')


if __name__ == '__main__':
    main()
