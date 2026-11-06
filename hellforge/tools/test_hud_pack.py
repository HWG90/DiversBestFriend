"""Regressions for the embedded runtime and deterministic release ZIP."""
import re
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

import hud_pack as pack


class HudPackage(unittest.TestCase):
    def test_generated_header_holds_exact_complete_private_chunk(self):
        header = pack.payload_header()
        data = bytes(int(value, 16) for value in re.findall(rb"0x([0-9a-f]{2})", header))
        self.assertEqual(data, pack.render())
        self.assertNotIn(b"-- HD2-Addon:", data[:256])

    def test_zip_roundtrip_is_deterministic_and_detects_drift(self):
        files = {"divers_best_friend.dll": b"dll payload", "LICENSE": b"example"}
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
