"""Exercise the installed launcher's real ZIP import and session staging in an empty temp root."""
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


def run_game_vm(work, install, loader, dll, staged):
    vm = work / "lua51.dll"
    shutil.copyfile(install / "game/bin/lua51.dll", vm)
    if hashlib.sha256(vm.read_bytes()).hexdigest() != VM_SHA256:
        raise ValueError("unexpected game VM for build 25480438")
    shutil.copyfile(dll, work / dll.name)
    shutil.copyfile(hud_pack.HF / "tests/staged_hud_vm.lua", work / "smoke.lua")
    body = hud_pack.verify_archive(staged.read_bytes())
    (work / "staged.lua").write_bytes(body)
    cc = "x86_64-w64-mingw32-gcc"
    runner = work / "hf_lua.exe"
    subprocess.run([cc, "-O2", loader / "tools/hf_lua.c", vm, "-o", runner], check=True)
    subprocess.run([cc, "-shared", "-DHF_LUA_API=__declspec(dllexport)", "-I", hud_pack.HF / "sdk",
                    hud_pack.HF / "tests/wine_modloader_stub.c", "-o", work / "hellforge_modloader.dll"], check=True)
    steam = Path.home() / ".local/share/Steam"
    proton = os.environ.get("PROTON", str(steam / "steamapps/common/Proton - Experimental/proton"))
    prefix = hud_pack.HF / "build/stage-proton"
    prefix.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "STEAM_COMPAT_DATA_PATH": str(prefix),
           "STEAM_COMPAT_CLIENT_INSTALL_PATH": str(steam), "WINEDEBUG": "-all"}
    for key in ("SteamAppId", "SteamGameId", "WINEPREFIX"):
        env.pop(key, None)
    subprocess.run([proton, "run", runner, "smoke.lua"], env=env, cwd=work, timeout=180, check=True)
    receipt = (work / "vm-passed.txt").read_text(encoding="ascii")
    if receipt != "PASS staged HUD VM: 3 enable/frame/shutdown cycles (LuaJIT 2.1.0-alpha)":
        raise ValueError("game VM did not acknowledge the final shutdown")
    print(receipt)


def stage(package, install, loader):
    cli = install / "app/cli-linux/HellForge.Cli"
    app = json.loads((install / "app/app-build.json").read_bytes())
    loader_name = "HF-LLL-0.1.0-25480438.zip"
    loader_zip = install / "mods" / loader_name
    if not loader_zip.is_file():
        loader_zip = loader / "dist" / loader_name
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
        run_game_vm(work, install, loader, paths[0], staged)
        print(json.dumps({"hf_lll_sha256": hashlib.sha256(loader_zip.read_bytes()).hexdigest(), "game_vm_sha256": VM_SHA256, "launcher": app["version"], "commit": app["commit"], "version": manifest["version"],
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
