"""Offline weapon-strip regression and optional evidence check against a mapped 25480438 dump."""
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import unittest

HF = Path(__file__).resolve().parents[1]


class WeaponStrip(unittest.TestCase):
    @unittest.skipUnless(shutil.which("luajit"), "needs LuaJIT")
    def test_r50_options_and_refusals(self):
        subprocess.run(["luajit", HF / "tests/weapon_strip.lua", HF / "hud"], check=True)

    @unittest.skipUnless(os.environ.get("DBF_WEAPON_IMAGE"), "set DBF_WEAPON_IMAGE to a mapped build 25480438 game.dll")
    def test_target_image(self):
        data = Path(os.environ["DBF_WEAPON_IMAGE"]).read_bytes()
        pe, = struct.unpack_from("<I", data, 60)
        self.assertEqual(struct.unpack_from("<I", data, pe + 8)[0], 0x6AB3B43F)
        self.assertEqual(len(data), 0x4744000)
        source = (HF / "hud/weapon_reader.lua").read_text()
        rows = re.findall(r'\{0x([a-f0-9]+), "([a-f0-9]+)"\}', source)
        self.assertGreater(len(rows), 20)
        for address, digits in rows:
            rva, witness = int(address, 16), bytes.fromhex(digits)
            self.assertEqual(data[rva:rva + len(witness)], witness, hex(rva))
        # Both option-provider loads and the RPM component point at the globals used by the reader.
        for rva, expected in [(0x1828099, 0x3326CE0), (0x18280EA, 0x33264C0), (0x617974, 0x33266D8)]:
            self.assertEqual(rva + 7 + struct.unpack_from("<i", data, rva + 3)[0], expected)
