"""Build or verify the combined HellForge mod, without touching an installation."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import struct
import subprocess
import tempfile
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

HF = Path(__file__).resolve().parents[1]
ROOT = HF.parent
MOD = HF / "divers-best-friend"
HUD = HF / "hud"
HOST = HF / "tools/hud_archive_host.lua"
ADDON = "mods/goose/divers_best_friend"
PATCH = "data/9ba626afa44a3aa3.patch_0"
R46 = ("layout", "guards", "mission_blacklist", "pointing", "camera",
       "icon_colors", "duplicate", "emote", "blacklist", "feedback")
WHEEL = ("wheel_native", "wheel_latch", "wheel_input", "wheel_selection", "wheel_release", "wheel_expanded")


def source_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


archive = source_module("dbf_archive", ROOT / "build.py")
r46 = source_module("dbf_r46", ROOT / "tools/release_package.py")


def factories():
    original = r46.sources("BSL")
    for name in R46:
        yield original["src/" + name + ".lua"].decode("utf-8")
    style = (HUD / "hd2_ui_style.lua").read_text(encoding="utf-8")
    yield "local kit = (function()\n" + style + "\nend)()\nreturn {style=kit, cooldown_tokens=kit.tokens}"
    terminal = ("terminal_guards", "terminal")
    present = [(HUD / (name + ".lua")).is_file() for name in terminal]
    if any(present) and not all(present):
        raise ValueError("terminal_guards.lua and terminal.lua must be supplied together")
    optional = terminal if all(present) else ()
    for name in (*WHEEL, "cooldown_gui", "cooldown_dock", "weapon_reader", "weapon_strip", *optional, "runtime"):
        yield (HUD / (name + ".lua")).read_text(encoding="utf-8")


def render():
    template = HOST.read_text(encoding="utf-8")
    marker = "-- @modules@"
    if template.count(marker) != 1:
        raise ValueError("expected one host factory marker")
    modules = "\n".join("function()\n" + body + "\nend," for body in factories())
    return template.replace(marker, modules).encode("utf-8")


def verify_archive(data, expected):
    """Validate a single Stingray Lua resource, independently of the writer."""
    if len(data) < 184 or struct.unpack_from("<III", data) != (0xF0000011, 1, 1):
        raise ValueError("expected one archive type and one resource")
    if struct.unpack_from("<Q", data, 32)[0] != len(data):
        raise ValueError("wrong archive size")
    if struct.unpack_from("<QI", data, 80) != (archive.TYPE, 1):
        raise ValueError("invalid Lua type descriptor")
    name, kind, offset = struct.unpack_from("<QQQ", data, 104)
    size, gpu, stream = struct.unpack_from("<III", data, 160)
    if (name, kind) != (archive.resource_hash(ADDON), archive.TYPE):
        raise ValueError("wrong addon resource key or type")
    if gpu or stream or offset < 184 or offset % 16 or size < 8 or offset + size > len(data):
        raise ValueError("invalid addon resource bounds or sidecar dependency")
    if struct.unpack_from("<II", data, offset) != (size - 8, 2):
        raise ValueError("invalid addon source envelope")
    body = data[offset + 8:offset + size]
    if not body.startswith(("-- HD2-Addon: " + ADDON + "\n").encode()) or body != expected:
        raise ValueError("archived source disagrees with the host or its inputs")


def release_files():
    body = render()
    subprocess.run(["luajit", "-e", 'assert(loadstring(io.read("*a"), "@DBF_HUD"))'], input=body, check=True)
    patch = archive.make_archive({archive.resource_hash(ADDON): struct.pack("<II", len(body), 2) + body})
    verify_archive(patch, body)
    files = {PATCH: patch, PATCH + ".stream": b"", PATCH + ".gpu_resources": b""}
    manifest = json.loads((MOD / "hellforge-mod.json").read_bytes())
    dll = manifest["code"]["dll"]
    if dll != "divers_best_friend.dll" or manifest["code"].get("prebuilt") is not True:
        raise ValueError("expected prebuilt DBF DLL in the manifest")
    for name in ("hellforge-mod.json", dll, "LICENSE"):
        files[name] = (MOD / name).read_bytes()
    for path in sorted((MOD / "src").iterdir()):
        if path.suffix in (".c", ".h"):
            files["src/" + path.name] = path.read_bytes()
    if (MOD / "README.md").is_file():
        files["README.md"] = (MOD / "README.md").read_bytes()
    files["CREDITS.md"] = (ROOT / "CREDITS.md").read_bytes()
    return files


def verify_zip(path, files):
    with ZipFile(path) as package:
        names = package.namelist()
        if sorted(names) != sorted(files):
            raise ValueError("unexpected, duplicate or missing zip member")
        for name, content in files.items():
            if package.read(name) != content:
                raise ValueError("zip member differs from current build: " + name)


def write_zip(target, files):
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=target.parent) as work:
        temp = Path(work) / "release.zip"
        with ZipFile(temp, "w") as package:
            for name, data in sorted(files.items()):
                info = ZipInfo(name)
                info.external_attr = 0o100644 << 16
                package.writestr(info, data, compress_type=ZIP_DEFLATED)
        verify_zip(temp, files)
        temp.replace(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("package", "verify"))
    parser.add_argument("path", nargs="?", type=Path)
    args = parser.parse_args()
    files = release_files()
    version = json.loads(files["hellforge-mod.json"])["version"]
    if not re.fullmatch(r"[A-Za-z0-9._-]+", version):
        raise ValueError("invalid mod version for export filename")
    path = args.path or HF / "build/exports" / f"divers-best-friend-{version}.zip"
    if args.mode == "package":
        write_zip(path, files)
    else:
        verify_zip(path, files)
    print(path)


if __name__ == "__main__":
    main()
