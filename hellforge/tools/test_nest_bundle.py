"""Single-import package contract and rejection regressions."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import nest_bundle as pack


class Bundle(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.host = self.root / "NEST.zip"
        manifest = {"id": pack.NEST, "version": "0.8.2",
                    "code": {"dll": "goose_overlay.dll", "prebuilt": True, "game": "25480438"}}
        self.host_files = {name: name.encode() for name in pack.hud_pack.NEST_FILES}
        self.host_files["hellforge-mod.json"] = json.dumps(manifest).encode()
        pack.hud_pack.write_zip(self.host, self.host_files)
        self.files = {**pack.hud_pack.embedded_nest_files(self.host),
                      "hellforge-mod.json": json.dumps({"id": pack.DBF}).encode(),
                      "divers_best_friend.dll": b"dbf", "INSTALL.md": b"direct import"}
        self.dbf = self.root / "divers-best-friend-R50-hellforge.11.zip"
        pack.hud_pack.write_zip(self.dbf, self.files)
        mock = patch.object(pack.hud_pack, "release_files", return_value=self.files)
        mock.start()
        self.addCleanup(mock.stop)

    def test_one_root_manifest_no_wrapper_and_both_stage_modes(self):
        with patch.object(pack, "stage") as stage:
            target = pack.build(self.dbf, self.host, self.root, self.root / "out")
        self.assertEqual(stage.call_count, 2)
        self.assertIsNone(stage.call_args_list[0].args[3])
        self.assertEqual(stage.call_args_list[1].args[3], self.host)
        self.assertEqual(target.name, self.dbf.name)
        self.assertEqual(target.read_bytes(), self.dbf.read_bytes())
        with ZipFile(target) as archive:
            self.assertEqual(archive.namelist().count("hellforge-mod.json"), 1)
            self.assertEqual(json.loads(archive.read("hellforge-mod.json"))["id"], pack.DBF)
            self.assertFalse(any(n.endswith(".zip") for n in archive.namelist()))
            self.assertTrue(pack.hud_pack.NEST_FILES <= set(archive.namelist()))

    def test_wrong_host_or_unexpected_assets_rejected(self):
        for extra in ("settings.ini", "fs-sinclair.ttf"):
            pack.hud_pack.write_zip(self.host, {**self.host_files, extra: b"private"})
            with self.assertRaisesRegex(ValueError, "expected NEST"):
                pack.hud_pack.embedded_nest_files(self.host)
        manifest = json.loads(self.host_files["hellforge-mod.json"])
        manifest["id"] = pack.DBF
        pack.hud_pack.write_zip(self.host, {**self.host_files, "hellforge-mod.json": json.dumps(manifest).encode()})
        with self.assertRaisesRegex(ValueError, "identity"):
            pack.hud_pack.embedded_nest_files(self.host)

    def test_failed_staging_does_not_replace_output(self):
        out = self.root / "out"
        out.mkdir()
        target = out / self.dbf.name
        target.write_bytes(b"previous")
        with patch.object(pack, "stage", side_effect=ValueError("import failed")), self.assertRaises(ValueError):
            pack.build(self.dbf, self.host, self.root, out)
        self.assertEqual(target.read_bytes(), b"previous")
