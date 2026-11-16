"""Package the isolated receiver from an already downloaded Electron.app.

Run through a local build queue. This script never launches an app or generates input.
"""
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

runtime = Path(sys.argv[1]).resolve()
destination = Path(sys.argv[2]).resolve()
if runtime.suffix != '.app' or destination.suffix != '.app' or destination.exists():
    raise SystemExit('Use an existing Electron.app and a new destination ending in .app')
version_file = runtime / 'Contents/Frameworks/Electron Framework.framework/Resources/Info.plist'
version = plistlib.loads(version_file.read_bytes()).get('CFBundleVersion')
if version != '42.11.15':
    raise SystemExit(f'Expected Electron 42.11.15, got {version!r}')
destination.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir=destination.parent, prefix='electron-probe-') as temporary:
    app = Path(temporary) / destination.name
    subprocess.run(['ditto', '--norsrc', '--noextattr', str(runtime), str(app)], check=True)
    resources = app / 'Contents/Resources/app'
    resources.mkdir(exist_ok=True)
    for name in ['main.cjs', 'preload.cjs', 'package.json']:
        shutil.copyfile(Path(__file__).parent / name, resources / name)
    info_file = app / 'Contents/Info.plist'
    info = plistlib.loads(info_file.read_bytes())
    info.update(CFBundleIdentifier='io.github.TRN408.QuadDesk.ElectronProbe',
                CFBundleName='QuadDesk Electron Probe', CFBundleDisplayName='QuadDesk Electron Probe')
    info_file.write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', '--timestamp=none', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    app.rename(destination)
print(f'Packaged: {destination}')
