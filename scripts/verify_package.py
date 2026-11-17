#!/usr/bin/env python3
"""Verify a locally produced bundle and its ZIP; does not launch the GUI."""
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def check(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'io.github.TRN408.QuadDesk'
    assert info['CFBundleShortVersionString'] == '0.7.10'
    assert info['CFBundleVersion'] == '32'
    assert info['QuadDeskNativeWindowsPreview'] is True
    assert info['NSAppTransportSecurity'] == {'NSAllowsArbitraryLoadsInWebContent': True}
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    signature = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', str(app)], capture_output=True, text=True, check=True).stderr
    if os.environ.get('QUADDESK_SIGN_IDENTITY', '-') == '-':
        assert 'Signature=adhoc' in signature, 'Default public builds must use ad hoc signing'
    for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'LICENSES/DeskPad-MIT.txt', 'LICENSES/yabai-MIT.txt']:
        assert (app / 'Contents/Resources' / name).is_file(), 'Missing license notice'
    result = {}
    for name in ['MacOS/QuadDesk', 'Helpers/QuadDisplayWatchdog']:
        binary = app / 'Contents' / name
        data = binary.read_bytes()
        assert os.access(binary, os.X_OK), 'Executable permissions missing'
        assert not re.search(rb'/Users/[^/\s\x00]+/', data), 'Home-directory path embedded in binary'
        assert b'-----BEGIN PRIVATE KEY-----' not in data
        result[name] = hashlib.sha256(data).hexdigest()
    return result


def main():
    app = Path(sys.argv[1]).resolve()
    archive = app.with_suffix('.zip')
    hashes = check(app)
    with zipfile.ZipFile(archive) as package:
        assert package.testzip() is None
        assert all(name.startswith('QuadDesk.app/') and '..' not in Path(name).parts for name in package.namelist())
    with tempfile.TemporaryDirectory(prefix='quaddesk-verify-') as temporary:
        subprocess.run(['/usr/bin/ditto', '-x', '-k', str(archive), temporary], check=True)
        assert hashes == check(Path(temporary) / 'QuadDesk.app')
    print(json.dumps({'version': '0.7.10', 'verified': True, 'sha256': hashes}, indent=2))


if __name__ == '__main__':
    main()
