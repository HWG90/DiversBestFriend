"""Regression cases for resource discovery, deterministic packaging and tamper detection."""
import struct
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

import hud_pack as pack


class HudArchive(unittest.TestCase):
    def setUp(self):
        self.body = ("-- HD2-Addon: " + pack.ADDON + "\nreturn true\n").encode()
        self.data = pack.archive.make_archive({pack.archive.resource_hash(pack.ADDON):
                                               struct.pack("<II", len(self.body), 2) + self.body})

    def test_discovery_fields(self):
        pack.verify_archive(self.data, self.body)
        # Header count, resource key/type/range, envelope, leading source marker.
        for offset in (8, 104, 112, 120, 160, 164, 192, 196, 200):
            with self.subTest(offset=offset):
                changed = bytearray(self.data)
                changed[offset] ^= 1
                with self.assertRaises(ValueError):
                    pack.verify_archive(changed, self.body)

    def test_zip_roundtrip_is_deterministic_and_detects_drift(self):
        files = {pack.PATCH: self.data, pack.PATCH + ".stream": b"", "LICENSE": b"example"}
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "test.zip"
            pack.write_zip(target, files)
            original = target.read_bytes()
            pack.write_zip(target, files)
            self.assertEqual(original, target.read_bytes())
            with self.assertRaisesRegex(ValueError, "differs"):
                pack.verify_zip(target, {**files, "LICENSE": b"changed"})
            with ZipFile(target, "a") as package:
                package.writestr("extra", b"")
            with self.assertRaisesRegex(ValueError, "member"):
                pack.verify_zip(target, files)
