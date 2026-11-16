#!/usr/bin/env python3
"""Update only our stopped Electron fixture, retaining its installed runtime."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('backup', type=Path)
args = parser.parse_args()
app = args.app.resolve()
info_path = app / 'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
if info.get('CFBundleIdentifier') != 'io.github.TRN408.QuadDesk.ElectronProbe':
    raise SystemExit('Refusing to update an app other than the QuadDesk Electron fixture')
executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
commands = subprocess.check_output(['ps', '-axo', 'comm='], text=True).splitlines()
if str(executable) in [line.strip() for line in commands]:
    raise SystemExit('Quit the Electron fixture before updating it')
source = Path(__file__).resolve().parent.parent / 'Tests/Fixtures/ElectronInputProbe'
args.backup.mkdir(parents=True, exist_ok=False)
resources = app / 'Contents/Resources/app'
for name in ['main.cjs', 'preload.cjs', 'package.json']:
    shutil.copyfile(resources / name, args.backup / name)
    shutil.copyfile(source / name, resources / name)
shutil.copyfile(info_path, args.backup / 'Info.plist')
info['CFBundleShortVersionString'] = json.loads((source / 'package.json').read_text())['version']
info['CFBundleVersion'] = '2'
info_path.write_bytes(plistlib.dumps(info))
subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('Updated fixture resources and verified signature:', app)
