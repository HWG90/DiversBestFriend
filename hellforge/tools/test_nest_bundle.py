"""Bundle composition regressions; nest_bundle.build also runs the real launcher on each release."""
from io import BytesIO
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import nest_bundle as pack


def package_files(mod_id):
    dll = pack.DLL[mod_id]
    manifest = {"name": "NEST" if mod_id == pack.NEST else "Diver's Best Friend",
                "version": "1.0", "id": mod_id, "code": {"game": "25480438", "prebuilt": True, "dll": dll}}
    return {"hellforge-mod.json": json.dumps(manifest).encode(), dll: mod_id.encode()}


class Bundle(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.dbf = self.root / "dbf.zip"
        self.files = package_files(pack.DBF)
        pack.hud_pack.write_zip(self.dbf, self.files)
        self.host = self.root / "host.zip"
        self.host_files = {**package_files(pack.NEST), "goose_overlay.h": b"api", "imgui-LICENSE.txt": b"license"}
        pack.hud_pack.write_zip(self.host, self.host_files)
        self.release = self.root / "release"
        mock = patch.object(pack.hud_pack, "release_files", return_value=self.files)
        mock.start()
        self.addCleanup(mock.stop)

    def build(self):
        return pack.build(self.dbf, self.host, self.root, self.release)

    def test_two_separate_root_packages_and_atomic_publication(self):
        with patch.object(pack, "stage"):
            bundle = self.build()
            original = bundle.read_bytes()
            self.assertEqual(original, self.build().read_bytes())
        with ZipFile(bundle) as outer:
            self.assertEqual(set(outer.namelist()), {pack.GUIDE, "NEST-1.0.zip", "divers-best-friend-1.0.zip"})
            self.assertEqual(outer.read("divers-best-friend-1.0.zip"), self.dbf.read_bytes())
            self.assertEqual(outer.read("NEST-1.0.zip"), self.host.read_bytes())
            with ZipFile(BytesIO(outer.read("NEST-1.0.zip"))) as host:
                self.assertEqual(set(host.namelist()), pack.HOST_FILES)
                for name in host.namelist():
                    self.assertEqual(host.read(name), self.host_files[name])
        with patch.object(pack, "stage", side_effect=ValueError("import failed")), self.assertRaises(ValueError):
            self.build()
        self.assertEqual(bundle.read_bytes(), original)

    def test_wrong_host_or_extra_file_fails_before_stage(self):
        pack.hud_pack.write_zip(self.host, {**self.host_files, "settings.ini": b"private"})
        with self.assertRaisesRegex(ValueError, "NEST release distribution"):
            self.build()
        pack.hud_pack.write_zip(self.host, {**self.host_files, "hellforge-mod.json": self.files["hellforge-mod.json"]})
        with self.assertRaisesRegex(ValueError, "stable ID"):
            self.build()
