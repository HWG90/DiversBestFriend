"""Pack DBF and NEST as separate importable mods. Stage both before publishing the bundle.

From hellforge/, run ./build.sh package, then:
python3 tools/nest_bundle.py --dbf <DBF-release.zip> --nest <NEST-release.zip> --install <HellForge-installation>
"""
import argparse
import hashlib
from io import BytesIO
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

import hud_pack

DBF = "goose.divers-best-friend"
NEST = "goose.overlay-host"
DLL = {DBF: "divers_best_friend.dll", NEST: "goose_overlay.dll"}
HOST_FILES = {"hellforge-mod.json", DLL[NEST], "imgui-LICENSE.txt", "goose_overlay.h"}
GUIDE = "INSTALL.md"


def manifest(archive, mod_id):
    names = archive.namelist()
    if len(names) != len(set(names)) or names.count("hellforge-mod.json") != 1:
        raise ValueError(f"{mod_id} needs a single root manifest and unique members")
    item = json.loads(archive.read("hellforge-mod.json"))
    code = item["code"]
    if (item["id"] != mod_id or code["dll"] != DLL[mod_id] or code["prebuilt"] is not True
            or code["game"] != "25480438" or code["dll"] not in names):
        raise ValueError(f"unexpected stable ID, DLL or target for {mod_id}")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", item["version"]):
        raise ValueError(f"invalid {mod_id} version")
    if mod_id == NEST and (set(names) != HOST_FILES or not item["name"].startswith("NEST")):
        raise ValueError("expected the NEST release distribution")
    return item


def stage(bundle, packages, install, work):
    root = work / "install"
    for directory in ("mods", "app", "game/data", "game/bin", "logs"):
        (root / directory).mkdir(parents=True)
    for name in ("hellforge-install.json", "app/app-build.json"):
        shutil.copyfile(install / name, root / name)
    cli = install / "app/cli-linux/HellForge.Cli"

    def run(command, *options):
        output = subprocess.check_output([cli, command, "--install", root, *options], cwd=root)
        return json.loads(output)

    expected = {}
    with ZipFile(bundle) as outer:
        for mod_id, name in packages.items():
            # Reproduce the player extracting each inner ZIP and feeding it to Import.
            path = work / name
            path.write_bytes(outer.read(name))
            item = run("mod-add", "--file", path)
            with ZipFile(path) as archive:
                m = manifest(archive, mod_id)
                if item["id"] != mod_id or item["version"] != m["version"]:
                    raise ValueError(f"launcher imported unexpected mod for {name}")
                expected[mod_id] = (m, archive.read(DLL[mod_id]))
                if mod_id == DBF:
                    patch = {p: archive.read(p) for p in archive.namelist() if p.startswith("data/")}
    plan = root / "plan.txt"
    result = run("mods-stage", "--logs", root / "logs", "--plan", plan, "--sandbox", "no")
    mods = result["mods"]
    if len(mods) != 2 or {m["id"] for m in mods} != set(expected) or result["codeMods"] != 2:
        raise ValueError(f"unexpected staged mods: {mods}")
    rows = [line.split("\t") for line in plan.read_text().splitlines() if line.startswith("mod\t")]
    for m in mods:
        mod_id = m["id"]
        authored, dll = expected[mod_id]
        paths = [Path(row[3]).resolve() for row in rows if row[1] == mod_id]
        if (len(paths) != 1 or not paths[0].is_relative_to(root) or paths[0].read_bytes() != dll
                or m["code"] != DLL[mod_id] or m["version"] != authored["version"] or m["source"]
                or m["dataFiles"] != (len(patch) if mod_id == DBF else 0)):
            raise ValueError(f"incorrect staged version, data or DLL for {mod_id}")
        print(f'{mod_id} {m["version"]} {DLL[mod_id]} sha256={hashlib.sha256(dll).hexdigest()}')
    if len(patch) != 3 or any((root / "game" / name).read_bytes() != body for name, body in patch.items()):
        raise ValueError("staged HUD patch differs from DBF release")
    app = json.loads((root / "app/app-build.json").read_bytes())
    print(f'Launcher {app["version"]} {app["commit"]} staged both DLLs and the DBF HUD patch.')


def build(dbf, nest, install, output):
    dbf_bytes = dbf.read_bytes()
    hud_pack.verify_zip(BytesIO(dbf_bytes), hud_pack.release_files())
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.resolve()) as tmp:
        work = Path(tmp)
        parts = {NEST: nest.read_bytes(), DBF: dbf_bytes}
        names, versions = {}, {}
        for mod_id, data in parts.items():
            with ZipFile(BytesIO(data)) as archive:
                versions[mod_id] = manifest(archive, mod_id)["version"]
            prefix = "NEST" if mod_id == NEST else "divers-best-friend"
            names[mod_id] = f"{prefix}-{versions[mod_id]}.zip"
        release = work / "bundle.zip"
        files = {names[k]: v for k, v in parts.items()}
        files[GUIDE] = (hud_pack.HF / "NEST-BUNDLE.md").read_bytes()
        hud_pack.write_zip(release, files)
        stage(release, names, install.resolve(), work)
        target = output / f"divers-best-friend-{versions[DBF]}-with-NEST-{versions[NEST]}.zip"
        release.replace(target)
        return target


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dbf", type=Path, required=True, help="verified DBF release ZIP from build.sh package")
    parser.add_argument("--nest", type=Path, required=True, help="release ZIP from the NEST build")
    parser.add_argument("--install", type=Path, required=True, help="read-only source of Linux launcher and metadata")
    parser.add_argument("--out-dir", type=Path, default=hud_pack.HF / "build/exports")
    opts = parser.parse_args()
    target = build(opts.dbf, opts.nest, opts.install, opts.out_dir)
    print(f"{target} sha256={hashlib.sha256(target.read_bytes()).hexdigest()}")
