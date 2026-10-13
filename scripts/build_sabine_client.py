"""Update only l2.ini in the previously supplied client overlay."""
import hashlib
import struct
import sys
import zipfile
import zlib
import re
import argparse
import ipaddress
from pathlib import Path

import l2ver41x as rsa

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-overlay", type=Path, required=True)
parser.add_argument("--host", required=True, help="Server IPv4")
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
source, target = args.source_overlay, args.output
host = str(ipaddress.IPv4Address(args.host)).encode("ascii")
if source.resolve() == target.resolve():
    parser.error("Source and output must be different files")
with zipfile.ZipFile(source) as old:
    original = old.read("system/l2.ini")
    plain, _ = rsa.decrypt(original, rsa.MOD_ENC, rsa.PRIV_ENC)
    edited, count = re.subn(rb"(?im)^ServerAddr=[^\r\n]*", b"ServerAddr=" + host, plain)
    assert count == 1, "Expected exactly one ServerAddr key"
    encrypted = rsa.encrypt(edited, 411)
    encrypted += b"\0" * 12 + struct.pack("<I", zlib.crc32(encrypted)) + b"\0" * 4
    decoded, tail = rsa.decrypt(encrypted, rsa.MOD_ENC, rsa.PRIV_ENC)
    assert decoded == edited
    assert struct.unpack_from("<I", tail, 12)[0] == zlib.crc32(encrypted[:-20])
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as new:
        for entry in old.infolist():
            new.writestr(entry, encrypted if entry.filename == "system/l2.ini"
                         else old.read(entry.filename))
with zipfile.ZipFile(source) as old, zipfile.ZipFile(target) as new:
    assert new.testzip() is None
    changed = [entry for entry in old.namelist() if old.read(entry) != new.read(entry)]
    assert changed == ["system/l2.ini"], changed
print("OUTPUT:", target)
print("ONLY_CHANGED:", changed)
print("SHA256:", hashlib.sha256(target.read_bytes()).hexdigest())
