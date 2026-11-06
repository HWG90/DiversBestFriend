"""Opt-in target integration: set DBF_BSL_ZIP, DBF_RELEASE_ZIP and DBF_HF_INSTALL.

Use a target-compatible Bingus release and the standalone
DBF inner ZIP. For loaders with a PE build gate, set DBF_BSL_TEST_SOURCE to
the upstream source checkout providing tests/build_fixture.lua and scripts/archive.py.
No loader, game bytecode or modified install is stored in this repo.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
from zipfile import ZipFile

from check_hud_pack_stage import run_game_vm

HERE = Path(__file__).resolve().parents[1]
DBF = "goose.divers-best-friend"
INPUTS = ("DBF_BSL_ZIP", "DBF_RELEASE_ZIP", "DBF_HF_INSTALL")


@unittest.skipUnless(all(os.environ.get(key) for key in INPUTS), "needs BSL ZIP, DBF ZIP and target installation")
class BingusCoexistence(unittest.TestCase):
    def test_staged_callback_and_private_dbf_owner(self):
        bsl, dbf, install = (Path(os.environ[key]).resolve() for key in INPUTS)
        print(f"BSL fixture {bsl.name} sha256={hashlib.sha256(bsl.read_bytes()).hexdigest()}")
        with ZipFile(bsl) as package:
            self.assertIn("BingusSharedLoader-manifest.json", package.namelist())
            packaged_patches = {hashlib.sha256(package.read(name)).digest() for name in package.namelist()
                                if ".patch_" in name and name.rsplit("_", 1)[1].isdigit()}
        with ZipFile(dbf) as package:
            dll_name = json.loads(package.read("hellforge-mod.json"))["code"]["dll"]
            dll_bytes = package.read(dll_name)
        with tempfile.TemporaryDirectory(prefix="dbf-bsl-") as work:
            scratch = Path(work)
            root = scratch / "install"
            for folder in ("app", "mods", "game/data", "game/bin", "logs"):
                (root / folder).mkdir(parents=True)
            for name in ("hellforge-install.json", "app/app-build.json"):
                shutil.copyfile(install / name, root / name)

            def cli(command, *args):
                return json.loads(subprocess.check_output(
                    [install / "app/cli-linux/HellForge.Cli", command, "--install", root, *args], cwd=root))

            self.assertEqual(json.loads((root / "hellforge-install.json").read_text(encoding="utf-8-sig"))["buildId"], "25480438")
            loader_id = cli("mod-add", "--file", bsl)["id"]
            plan = root / "plan.txt"

            def staged():
                result = cli("mods-stage", "--logs", root / "logs", "--plan", plan, "--sandbox", "no")
                data = root / "game/data"
                files = {name: (data / name).read_bytes() for name in result["staged"]}
                return {m["id"] for m in result["mods"]}, files

            ids, baseline = staged()
            self.assertEqual(ids, {loader_id})
            self.assertEqual(cli("mod-add", "--file", dbf)["id"], DBF)
            ids, files = staged()
            self.assertEqual(ids, {loader_id, DBF})
            self.assertEqual(files.keys(), baseline.keys(), "DBF added or displaced BSL data")
            for name in files:
                self.assertTrue(files[name] == baseline[name], f"DBF changed staged {name}")
            rows = [line.split("\t") for line in plan.read_text().splitlines() if line.startswith("mod\t")]
            dll_paths = [Path(row[3]).resolve() for row in rows if row[1] == DBF]
            self.assertEqual(len(dll_paths), 1)
            dll = dll_paths[0]
            self.assertTrue(dll.is_relative_to(root))
            self.assertEqual(dll.read_bytes(), dll_bytes)

            callbacks = []
            for name, patch in files.items():
                if ".patch_" not in name or not name.rsplit("_", 1)[1].isdigit():
                    continue
                magic, types, count = struct.unpack_from("<III", patch)
                self.assertEqual(magic, 0xF0000011)
                table = 72 + 32 * types
                for index in range(count):
                    row = table + 80 * index
                    key, kind, offset = struct.unpack_from("<QQQ", patch, row)
                    if (key, kind) == (0x7251FDD9BB62480A, 0xA14E8DFA2CD117E2):
                        self.assertIn(hashlib.sha256(patch).digest(), packaged_patches)
                        size, = struct.unpack_from("<I", patch, row + 56)
                        length, encoding = struct.unpack_from("<II", patch, offset)
                        self.assertEqual((size, encoding), (length + 8, 2))
                        callbacks.append(patch[offset + 8:offset + size])
            self.assertEqual(len(callbacks), 1, "expected one staged stock Wwise callback provider")
            vm = scratch / "vm"
            vm.mkdir()
            (vm / "bsl-callback.ljbc").write_bytes(callbacks[0])
            upstream = os.environ.get("DBF_BSL_TEST_SOURCE")
            if upstream:
                for name in ("tests/build_fixture.lua", "scripts/archive.py"):
                    target = vm / "bsl-test-source" / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(Path(upstream) / name, target)
            run_game_vm(vm, install, dll, HERE / "tests/bsl_coexistence.lua")
