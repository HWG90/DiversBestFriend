"""Build or verify the combined HellForge mod, without touching an installation."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

HF = Path(__file__).resolve().parents[1]
ROOT = HF.parent
MOD = HF / "divers-best-friend"
HUD = HF / "hud"
HOST = HF / "tools/hud_archive_host.lua"
R46 = ("layout", "guards", "mission_blacklist", "pointing", "camera",
       "icon_colors", "duplicate", "emote", "blacklist", "feedback")
WHEEL = ("wheel_native", "wheel_latch", "wheel_input", "wheel_selection", "wheel_release", "wheel_expanded")


def source_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


r46 = source_module("dbf_r46", ROOT / "tools/release_package.py")


def factories():
    original = r46.sources(None)
    for name in R46:
        body = original["src/" + name + ".lua"].decode("utf-8")
        if name in ("duplicate", "emote"):
            allocation = "storage=ffi.new('uint8_t[?]',"
            if body.count(allocation) != 1:
                raise ValueError("unexpected native root allocator in " + name)
            body = body.replace(allocation, "storage=b.alloc_widget(")
        yield body
    style = (HUD / "hd2_ui_style.lua").read_text(encoding="utf-8")
    yield "local kit = (function()\n" + style + "\nend)()\nreturn {style=kit, cooldown_tokens=kit.tokens}"
    for name in (*WHEEL, "cooldown_gui", "binding_warning", "cooldown_dock", "weapon_reader", "weapon_strip",
                 "terminal_guards", "terminal", "runtime"):
        yield (HUD / (name + ".lua")).read_text(encoding="utf-8")


def render():
    template = HOST.read_text(encoding="utf-8")
    marker = "-- @modules@"
    if template.count(marker) != 1:
        raise ValueError("expected one host factory marker")
    modules = "\n".join("function()\n" + body + "\nend," for body in factories())
    return template.replace(marker, modules).encode("utf-8")


def payload_header():
    """Compile-time bytes of DBF's private VM chunk, reproduced in the source ZIP."""
    body = render()
    # Hex bytes avoid execution-charset conversion, string-size limits and C escapes.
    rows = (", ".join(f"0x{byte:02x}" for byte in body[i:i + 20]) for i in range(0, len(body), 20))
    return ("/* Generated from DBF HUD sources by hud_pack.py. */\n"
            "static const char dbf_hud_payload[] = {\n" + ",\n".join(rows) + "\n};\n").encode("ascii")


NEST_FILES = {"goose_overlay.dll", "goose_overlay.h", "imgui-LICENSE.txt"}


def embedded_nest_files(path=None):
    path = Path(path or os.environ.get("DBF_NEST_ZIP") or
                HF.parent.parent / "overlay-host-mcm-geometry/dist/NEST-0.8.2.zip")
    with ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != 4 or set(names) != NEST_FILES | {"hellforge-mod.json"}:
            raise ValueError("expected NEST DLL, API header, license and manifest only")
        manifest = json.loads(archive.read("hellforge-mod.json"))
        code = manifest.get("code", {})
        if (manifest.get("id") != "goose.overlay-host" or manifest.get("version") != "0.8.2"
                or code.get("dll") != "goose_overlay.dll" or code.get("game") != "25480438"
                or code.get("prebuilt") is not True):
            raise ValueError("unexpected embedded NEST release identity or game target")
        return {name: archive.read(name) for name in NEST_FILES}


def release_files():
    body = render()
    subprocess.run(["luajit", "-e", 'assert(loadstring(io.read("*a"), "@DBF_HUD"))'], input=body, check=True)
    files = {}
    manifest = json.loads((MOD / "hellforge-mod.json").read_bytes())
    dll = manifest["code"]["dll"]
    if dll != "divers_best_friend.dll" or manifest["code"].get("prebuilt") is not True:
        raise ValueError("expected prebuilt DBF DLL in the manifest")
    for name in ("hellforge-mod.json", dll, "LICENSE"):
        files[name] = (MOD / name).read_bytes()
    for path in sorted((MOD / "src").iterdir()):
        if path.suffix in (".c", ".h"):
            files["src/" + path.name] = path.read_bytes()
    files["src/dbf_hud_payload.h"] = payload_header()
    if body not in files[dll]:
        raise ValueError("DBF DLL lacks the current embedded HUD payload; rebuild with build.sh dll")
    if (MOD / "README.md").is_file():
        files["README.md"] = (MOD / "README.md").read_bytes()
    files["CREDITS.md"] = (ROOT / "CREDITS.md").read_bytes()
    files.update(embedded_nest_files())
    files["INSTALL.md"] = (HF / "NEST-BUNDLE.md").read_bytes()
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
    parser.add_argument("mode", choices=("package", "verify", "header"))
    parser.add_argument("path", nargs="?", type=Path)
    args = parser.parse_args()
    if args.mode == "header":
        if not args.path:
            parser.error("header requires a destination")
        args.path.parent.mkdir(parents=True, exist_ok=True)
        content = payload_header()
        if not args.path.exists() or args.path.read_bytes() != content:
            with tempfile.NamedTemporaryFile(dir=args.path.parent, delete=False) as tmp:
                tmp.write(content)
            Path(tmp.name).replace(args.path)
        return
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
