"""Verify a launcher upgrade and exercise the staged private HUD in the pinned game VM."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

import hud_pack

VM_SHA256 = "2c8720c9f446c848436ad993b1a88099d76f0b0b09df53689719b797c3039ce7"
DBF = "goose.divers-best-friend"
DLL = "divers_best_friend.dll"


def run_game_vm(work, install, dll, prelude=None):
    vm = work / "lua51.dll"
    shutil.copyfile(install / "game/bin/lua51.dll", vm)
    if hashlib.sha256(vm.read_bytes()).hexdigest() != VM_SHA256:
        raise ValueError("unexpected game VM for build 25480438")
    shutil.copyfile(dll, work / DLL)
    runner = work / "stage_vm.exe"
    cc = ["x86_64-w64-mingw32-gcc", "-O2", "-Wall", "-Werror", "-I", hud_pack.HF / "sdk"]
    subprocess.run([*cc, hud_pack.HF / "tests/wine_staged_hud_vm.c", vm, "-o", runner], check=True)
    subprocess.run([*cc, "-shared", "-DHF_LUA_API=__declspec(dllexport)",
                    hud_pack.HF / "tests/wine_modloader_stub.c", "-o", work / "hellforge_modloader.dll"], check=True)
    args = []
    if prelude is not None:
        target = work / "prelude.lua"
        if prelude.resolve() != target.resolve():
            shutil.copyfile(prelude, target)
        args.append(target.name)
    steam = Path.home() / ".local/share/Steam"
    proton = os.environ.get("PROTON", str(steam / "steamapps/common/Proton - Experimental/proton"))
    prefix = hud_pack.HF / "build/stage-proton"
    prefix.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "STEAM_COMPAT_DATA_PATH": str(prefix),
           "STEAM_COMPAT_CLIENT_INSTALL_PATH": str(steam), "WINEDEBUG": "-all"}
    for key in ("SteamAppId", "SteamGameId", "WINEPREFIX"):
        env.pop(key, None)
    log = work / "vm-stage.log"
    errors = work / "vm-error.log"
    for path in (log, errors):
        path.unlink(missing_ok=True)
    result = subprocess.run([proton, "run", runner, *args], env=env, cwd=work, timeout=180)
    output = log.read_text(errors="replace") if log.exists() else ""
    print(output, end="")
    receipt = "PASS staged HUD VM: one production attachment per VM, 2 VM lifetimes, 6 chained updates"
    if result.returncode or not output.splitlines() or output.splitlines()[-1] != receipt:
        detail = errors.read_text(errors="replace") if errors.exists() else "runner did not start"
        raise ValueError(f"missing successful VM receipt (Proton exit {result.returncode}): {detail}")


def stage(package, install, previous):
    cli = install / "app/cli-linux/HellForge.Cli"
    with tempfile.TemporaryDirectory(prefix="dbf-hud-stage-") as temp:
        work = Path(temp)
        for folder in ("mods", "app", "game/data", "game/bin", "logs"):
            (work / folder).mkdir(parents=True)
        for name in ("hellforge-install.json", "app/app-build.json"):
            shutil.copyfile(install / name, work / name)

        def run(command, *options):
            stdout = subprocess.check_output([cli, command, "--install", work, *options], cwd=work)
            return json.loads(stdout)

        plan = work / "plan.txt"

        def stage_mods():
            return run("mods-stage", "--logs", work / "logs", "--plan", plan, "--sandbox", "no")

        old = run("mod-add", "--file", previous.resolve())
        prior = stage_mods()
        if (old["id"] != DBF or old["version"] != "R50-hellforge.9" or
                len(prior["mods"]) != 1 or prior["mods"][0]["dataFiles"] != 3 or len(prior["staged"]) != 3):
            raise ValueError("upgrade baseline must be the previous DBF release with its archive")
        added = run("mod-add", "--file", package.resolve())
        if added["id"] != DBF or added["replaced"] != old["installed"]:
            raise ValueError("launcher failed to replace the original DBF mod")
        result = stage_mods()
        with ZipFile(package) as release:
            manifest = json.loads(release.read("hellforge-mod.json"))
            mods = result["mods"]
            if (len(mods) != 1 or mods[0]["id"] != DBF or mods[0]["code"] != DLL or
                    mods[0]["version"] != manifest["version"] or mods[0]["dataFiles"] or mods[0]["source"]
                    or result["codeMods"] != 1 or result["staged"]
                    or any("Shared Loader" in msg for msg in result["problems"])):
                raise ValueError(f"unexpected standalone plan: {result}")
            leftovers = list((work / "game/data").glob("*.patch_*"))
            if leftovers:
                raise ValueError(f"stale DBF addon survived the launcher upgrade: {leftovers}")
            rows = [line.split("\t") for line in plan.read_text().splitlines() if line.startswith("mod\t")]
            if len(rows) != 1 or rows[0][1] != DBF:
                raise ValueError("expected just DBF in the code plan")
            dll = Path(rows[0][3]).resolve()
            if not dll.is_relative_to(work) or dll.read_bytes() != release.read(DLL):
                raise ValueError("launcher-planned DLL differs from the release")
        print(f'{old["version"]} -> {added["version"]}: one DBF code mod, zero staged patches')
        run_game_vm(work, install, dll)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("install", type=Path)
    parser.add_argument("--previous", type=Path, required=True)
    args = parser.parse_args()
    stage(args.package, args.install, args.previous)
