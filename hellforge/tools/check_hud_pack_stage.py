"""Exercise the installed launcher's real ZIP import and session staging in an empty temp root."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

import hud_pack


def stage(package, install, loader):
    cli = install / "app/cli-linux/HellForge.Cli"
    app = json.loads((install / "app/app-build.json").read_bytes())
    loader_zip = loader / "dist/HF-LLL-0.1.0-25480438.zip"
    with tempfile.TemporaryDirectory(prefix="dbf-hud-stage-") as temp:
        work = Path(temp)
        for folder in ("mods", "app", "game/data", "game/bin", "logs"):
            (work / folder).mkdir(parents=True)
        for name in ("hellforge-install.json", "app/app-build.json"):
            shutil.copyfile(install / name, work / name)

        def run(command, *options):
            stdout = subprocess.check_output([cli, command, "--install", work, *options], cwd=work)
            return json.loads(stdout)

        run("mod-add", "--file", loader_zip.resolve())
        run("mod-add", "--file", package.resolve())
        plan = work / "plan.txt"
        result = run("mods-stage", "--logs", work / "logs", "--plan", plan, "--sandbox", "no")
        with ZipFile(package) as release:
            manifest = json.loads(release.read("hellforge-mod.json"))
            identifier, dll = manifest["id"], manifest["code"]["dll"]
            selected = [m for m in result["mods"] if m["id"] == identifier]
            if (len(selected) != 1 or selected[0]["code"] != dll or selected[0]["dataFiles"] != 3
                    or selected[0]["version"] != manifest["version"] or selected[0]["source"]):
                raise ValueError("launcher did not stage expected mixed mod: " + str(result["mods"]))
            rows = [line.split("\t") for line in plan.read_text().splitlines() if line.startswith("mod\t")]
            paths = [Path(row[3]) for row in rows if row[1] == identifier]
            if len(paths) != 1 or not paths[0].resolve().is_relative_to(work) or paths[0].read_bytes() != release.read(dll):
                raise ValueError("DLL in launcher plan differs from package")
            data = work / "game/data"
            patch = release.read(hud_pack.PATCH)
            matches = [p for p in data.glob("9ba626afa44a3aa3.patch_*") if p.suffix.removeprefix(".patch_").isdigit() and p.read_bytes() == patch]
            if len(matches) != 1:
                raise ValueError("expected one byte-identical staged patch")
            staged = matches[0]
            for suffix in (".stream", ".gpu_resources"):
                if Path(str(staged) + suffix).read_bytes() != release.read(hud_pack.PATCH + suffix):
                    raise ValueError("staged companion differs: " + suffix)
        subprocess.run(["luajit", hud_pack.HF / "tests/check_hud_discovery.lua", loader.resolve(),
                        staged.name, hud_pack.ADDON, data, *sorted(p.name for p in data.iterdir())], input=staged.read_bytes(), check=True)
        print(json.dumps({"launcher": app["version"], "commit": app["commit"], "version": manifest["version"],
                          "planned_dll": paths[0].name, "dll_sha256": hashlib.sha256(paths[0].read_bytes()).hexdigest(),
                          "staged_patch": staged.name, "patch_sha256": hashlib.sha256(staged.read_bytes()).hexdigest(),
                          "package_sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
                          "data_files": selected[0]["dataFiles"], "stage_notes": result["problems"]}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("install", type=Path)
    parser.add_argument("loader", type=Path)
    args = parser.parse_args()
    stage(args.package, args.install, args.loader)
