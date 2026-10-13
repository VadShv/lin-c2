"""Offline tests: no VM connection, account login, or proprietary binaries."""
import os
import struct
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from l2hash import l2hash
from probe_c2 import GameCrypt, crypt, pack_auth
import l2ver41x


class CoreTests(unittest.TestCase):
    def test_game_cipher_state(self):
        encoder, decoder = GameCrypt(0x12345678), GameCrypt(0x12345678)
        for body in (b"\x08hello", b"\x0d" + bytes(4), b"\x03" + bytes(4), bytes(range(256))):
            self.assertEqual(decoder.apply(encoder.apply(body), decrypt=True), body)
        self.assertEqual(encoder.key, decoder.key)
        self.assertEqual(struct.unpack_from("<I", encoder.key)[0], 0x12345678 + 6 + 5 + 5 + 256)

    def test_auth_checksum_and_padding(self):
        data = crypt(pack_auth(b"\x05" + bytes(9)), decrypt=True)
        checksum = 0
        for value, in struct.iter_unpack("<I", data[:-8]):
            checksum ^= value
        self.assertEqual(checksum, struct.unpack_from("<I", data, len(data) - 8)[0])
        self.assertEqual(data[-4:], bytes(4))

    def test_resource_roundtrip(self):
        for plain in (b"", b"[URL]\r\nServerAddr=127.0.0.1\r\n", bytes(range(256)) * 20):
            encrypted = l2ver41x.encrypt(plain, 411)
            recovered, tail = l2ver41x.decrypt(encrypted, l2ver41x.MOD_ENC, l2ver41x.PRIV_ENC)
            self.assertEqual(recovered, plain)
            self.assertEqual(tail, b"")

    def test_classic_hash_contract(self):
        self.assertEqual(len(l2hash("offline-fixture")), 16)
        self.assertNotIn(0, l2hash("offline-fixture"))
        self.assertEqual(l2hash("abcdefghijklmnop-more"), l2hash("abcdefghijklmnop"))
        with self.assertRaises(UnicodeEncodeError):
            l2hash("пароль")

    def test_probe_requires_explicit_login_opt_in(self):
        env = {k: v for k, v in os.environ.items() if not k.startswith("L2_")}
        result = subprocess.run([sys.executable, str(ROOT / "scripts/probe_c2.py"), "--agreement"],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("L2_TEST_USER", result.stderr)

    def test_public_config_has_no_live_password(self):
        for folder in ("configs", "registry"):
            for path in (ROOT / folder).rglob("*"):
                if not path.is_file():
                    continue
                for line in path.read_text(encoding="utf-8-sig").splitlines():
                    lower = line.lower()
                    if lower.startswith(("pwd=", "password=")) or lower.startswith('"pwd"='):
                        self.assertIn("__DB_PASSWORD__", line, str(path))
        self.assertNotIn('"connStr"=hex:', (ROOT / "registry/project_l2.reg").read_text())


if __name__ == "__main__":
    unittest.main()
