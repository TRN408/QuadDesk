#!/usr/bin/env python3
"""Package the separate, opt-in native display comparison app."""
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from package import signing_identity


def main():
    binary, helper, destination = map(lambda p: Path(p).resolve(), sys.argv[1:4])
    if destination.suffix != '.app' or destination.exists():
        raise SystemExit('Choose a fresh .app destination')
    identity = signing_identity()
    with tempfile.TemporaryDirectory(prefix='quaddesk-native-', dir='/private/tmp') as temporary:
        app = Path(temporary) / destination.name
        executable = app / 'Contents/MacOS/QuadDeskNativePreview'
        watchdog = app / 'Contents/Helpers/QuadDisplayWatchdog'
        executable.parent.mkdir(parents=True)
        watchdog.parent.mkdir(parents=True)
        for source, target in [(binary, executable), (helper, watchdog)]:
            shutil.copyfile(source, target)
            target.chmod(0o755)
        with (app / 'Contents/Info.plist').open('wb') as handle:
            plistlib.dump({
                'CFBundleExecutable': 'QuadDeskNativePreview',
                'CFBundleIdentifier': 'io.github.TRN408.QuadDeskNativePreview',
                'CFBundleName': 'QuadDeskNativePreview',
                'CFBundleDisplayName': 'QuadDesk Native Preview',
                'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.1.1',
                'CFBundleVersion': '2', 'LSMinimumSystemVersion': '14.0',
                'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
            }, handle)
        for target in [watchdog, app]:
            subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp=none', str(target)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['ditto', '--norsrc', '--noextattr', str(app), str(destination)], check=True)
        subprocess.run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', str(app), str(destination.with_suffix('.zip'))], check=True)
        print(f'Preview only: {destination}')


if __name__ == '__main__':
    main()
