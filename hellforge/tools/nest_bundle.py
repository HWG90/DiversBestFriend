"""Verify the single directly importable DBF release with its bundled NEST host.

Legacy --dbf/--nest invocation remains supported, but produces no wrapper ZIP.
"""
import argparse
import hashlib
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

import hud_pack

DBF = "goose.divers-best-friend"
NEST = "goose.overlay-host"
DLL = {DBF: "divers_best_friend.dll", NEST: "goose_overlay.dll"}


def stage(package, install, work, standalone=None):
    root = work / "install"
    for directory in ("mods", "app", "game/data", "game/bin", "logs"):
        (root / directory).mkdir(parents=True)
    for name in ("hellforge-install.json", "app/app-build.json"):
        shutil.copyfile(install / name, root / name)
    cli = install / "app/cli-linux/HellForge.Cli"

    def run(command, *options):
        return json.loads(subprocess.check_output([cli, command, "--install", root, *options], cwd=root))

    if standalone:
        run("mod-add", "--file", standalone.resolve())
    first = run("mod-add", "--file", package.resolve())
    again = run("mod-add", "--file", package.resolve())
    if first["id"] != DBF or again["replaced"] != first["installed"]:
        raise ValueError("same-version import did not replace stable DBF entry")
    plan = root / "plan.txt"
    result = run("mods-stage", "--logs", root / "logs", "--plan", plan, "--sandbox", "no")
    expected_ids = {DBF, NEST} if standalone else {DBF}
    mods = result["mods"]
    if (len(mods) != len(expected_ids) or {m["id"] for m in mods} != expected_ids
            or result["codeMods"] != len(expected_ids) or result["staged"]
            or any(m["dataFiles"] or m["source"] for m in mods)
            or any("Shared Loader" in p for p in result["problems"])):
        raise ValueError(f"unexpected single-ZIP staging: {result}")
    rows = [line.split("\t") for line in plan.read_text().splitlines() if line.startswith("mod\t")]
    if standalone:
        host_rows = [row for row in rows if row[1] == NEST]
        if len(host_rows) != 1:
            raise ValueError("expected one preserved standalone host")
        with ZipFile(standalone) as archive:
            path = Path(host_rows[0][3]).resolve()
            if not path.is_relative_to(root) or path.read_bytes() != archive.read(DLL[NEST]):
                raise ValueError("DBF import altered the standalone host")
    dbf_rows = [row for row in rows if row[1] == DBF]
    if len(dbf_rows) != 1:
        raise ValueError("expected exactly one DBF entry point")
    dll = Path(dbf_rows[0][3]).resolve()
    with ZipFile(package) as archive:
        for name in {DLL[DBF], *hud_pack.NEST_FILES}:
            path = dll.parent / name
            if not path.is_relative_to(root) or path.read_bytes() != archive.read(name):
                raise ValueError("launcher lost or altered bundled file: " + name)
    print(f"PASS direct ZIP import/reimport: {len(mods)} launcher mod(s), one DBF, bundled NEST intact")


def build(dbf, nest, install, output, previous_nest=None):
    files = hud_pack.release_files()
    host = hud_pack.embedded_nest_files(nest)
    if any(files[name] != data for name, data in host.items()):
        raise ValueError("explicit NEST differs from package build input")
    hud_pack.verify_zip(dbf, files)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.resolve()) as tmp:
        work = Path(tmp)
        lanes = [("bundled", None), ("standalone", nest)]
        if previous_nest:
            lanes.append(("legacy", previous_nest))
        for mode, standalone in lanes:
            lane = work / mode
            lane.mkdir()
            stage(dbf, install.resolve(), lane, standalone)
        target = output / dbf.name
        if target.resolve() != dbf.resolve():
            hud_pack.write_zip(target, files)
        return target


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dbf", type=Path, required=True)
    parser.add_argument("--nest", type=Path, required=True)
    parser.add_argument("--install", type=Path, required=True)
    parser.add_argument("--previous-nest", type=Path, help="also check coexistence with an existing standalone host ZIP")
    parser.add_argument("--out-dir", type=Path, default=hud_pack.HF / "build/exports")
    args = parser.parse_args()
    target = build(args.dbf, args.nest, args.install, args.out_dir, args.previous_nest)
    print(f"{target} sha256={hashlib.sha256(target.read_bytes()).hexdigest()}")
