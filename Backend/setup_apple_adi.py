#!/usr/bin/env python3
"""Extract the supported macOS ADI library directly from Apple's installer.

Protocol research: sacca97/os-findmy-e, tools/fetch_mac_coreadi.py (MIT).
No Apple binary or account credentials are distributed with this update.
"""
import argparse
import gzip
import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import urllib.request

DMG_URL = 'https://secure-appldnld.apple.com/itunes12/041-56365-20210413-79A5AC6D-6B0A-46EC-B399-5A381183E3BE/iTunes12.8.3.dmg'
DMG_SHA256 = 'dd08b9967db3e5847955fa168ce880303abf5f36de12abb2061e7ef1a25be214'
ADI_SHA256 = '2eafc3c79c7f41a8afbfbeaaf23ee5dab5ad5bda55ec8e54dbc0ddf1d20ce630'
FRAMEWORK = 'System/Library/PrivateFrameworks/CoreADI.framework/Versions/A/CoreADI'


def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def read_framework(payload):
    """Read one regular file from odc CPIO; never extract archive paths."""
    data = gzip.decompress(payload)
    pos = 0
    while pos + 76 <= len(data):
        if data[pos:pos+6] != b'070707':
            raise ValueError('Unsupported or truncated Apple CPIO payload')
        mode = int(data[pos+18:pos+24], 8)
        name_size = int(data[pos+59:pos+65], 8)
        size = int(data[pos+65:pos+76], 8)
        start = pos + 76
        end = start + name_size
        if name_size < 1 or end + size > len(data):
            raise ValueError('Truncated Apple CPIO entry')
        name = data[start:end-1].decode()
        if name.removeprefix('./') == FRAMEWORK and mode & 0o170000 == 0o100000:
            return data[end:end+size]
        if name == 'TRAILER!!!':
            break
        pos = end + size
    raise ValueError('CoreADI not found in the verified Apple installer')


def x86_slice(data):
    if data[:4] != b'\xca\xfe\xba\xbe':
        raise ValueError('Unsupported Apple universal binary')
    count = struct.unpack_from('>I', data, 4)[0]
    for i in range(count):
        cpu, _, offset, size, _ = struct.unpack_from('>IIIII', data, 8 + i*20)
        if cpu == 0x01000007:
            binary = data[offset:offset+size]
            if len(binary) != size or hashlib.sha256(binary).hexdigest() != ADI_SHA256:
                raise ValueError('Unsupported CoreADI build (SHA-256 mismatch)')
            return binary
    raise ValueError('The Apple installer has no x86_64 CoreADI')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dmg', type=Path, help='Use a locally downloaded official iTunes12.8.3.dmg')
    parser.add_argument('--destination', type=Path, default=Path(os.environ.get('MACOS_ADI_BINARY', Path(__file__).resolve().parent/'runtime/CoreADI.x86_64')))
    args = parser.parse_args()
    destination = args.destination.expanduser().resolve()
    if destination.is_file() and digest(destination) == ADI_SHA256:
        print('Apple ADI is already installed and verified.')
        return
    sevenzip = shutil.which('7zz') or shutil.which('7z')
    if not sevenzip:
        raise SystemExit('7-Zip fehlt. Auf Debian: apt install 7zip (alternativ p7zip-full).')
    with tempfile.TemporaryDirectory(prefix='tracker-apple-') as temporary:
        root = Path(temporary)
        dmg = args.dmg.resolve() if args.dmg else root/'iTunes12.8.3.dmg'
        if args.dmg is None:
            print('Downloading the official Apple installer (about 278 MiB)...', flush=True)
            with urllib.request.urlopen(DMG_URL, timeout=60) as response, dmg.open('wb') as file:
                shutil.copyfileobj(response, file)
        if digest(dmg) != DMG_SHA256:
            raise SystemExit('Apple installer SHA-256 mismatch; no runtime file was changed.')
        subprocess.run([sevenzip, 'x', str(dmg), 'iTunes/Install iTunes.pkg', '-o'+str(root/'dmg'), '-y'], check=True, stdout=subprocess.DEVNULL)
        subprocess.run([sevenzip, 'x', str(root/'dmg/iTunes/Install iTunes.pkg'), 'CoreADI.pkg/Payload', '-o'+str(root/'pkg'), '-y'], check=True, stdout=subprocess.DEVNULL)
        binary = x86_slice(read_framework((root/'pkg/CoreADI.pkg/Payload').read_bytes()))
        destination.parent.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(prefix='.CoreADI-', dir=destination.parent)
        try:
            with os.fdopen(fd, 'wb') as file:
                file.write(binary)
            os.chmod(name, 0o644)
            os.replace(name, destination)
        finally:
            Path(name).unlink(missing_ok=True)
    print('Apple ADI installed and SHA-256 verified:', destination)


if __name__ == '__main__':
    main()
