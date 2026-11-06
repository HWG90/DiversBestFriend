"""Exercise production DBF and both NEST generations in isolated Wine processes."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

HF = Path(__file__).resolve().parents[1]


def win(path):
    return "Z:" + str(path.resolve()).replace("/", "\\")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("nest", type=Path, help="production shared-runtime goose_overlay.dll")
    parser.add_argument("legacy", type=Path, help="released NEST-0.8.1.zip")
    parser.add_argument("--dbf", type=Path, default=HF / "divers-best-friend/divers_best_friend.dll")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    work = args.output or Path(tempfile.mkdtemp(prefix="dbf-nest-boot-"))
    work = work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    with ZipFile(args.legacy) as package:
        names = [n for n in package.namelist() if n.endswith("/goose_overlay.dll") or n == "goose_overlay.dll"]
        if len(names) != 1:
            raise ValueError("expected one legacy NEST DLL")
        legacy = package.read(names[0])
    for label, data in (("DBF", args.dbf.read_bytes()), ("NEST", args.nest.read_bytes()), ("legacy", legacy)):
        print(label, hashlib.sha256(data).hexdigest(), flush=True)
    compiler = os.environ.get("CC_WINDOWS", "x86_64-w64-mingw32-gcc")
    exe = work / "wine_nest_boot.exe"
    subprocess.run([compiler, "-std=c11", "-Wall", "-Werror", "-Wno-unused-parameter",
                    "-Wno-format-truncation", "-I" + str(HF / "sdk"),
                    "-I" + str(HF / "divers-best-friend/src"),
                    str(HF / "tests/wine_nest_boot.c"), "-o", str(exe)], check=True)
    proton = Path(os.environ.get("PROTON", str(Path.home() / ".local/share/Steam/steamapps/common/Proton - Experimental/proton")))
    env = os.environ.copy()
    env.update(STEAM_COMPAT_DATA_PATH=str(work / "prefix"),
               STEAM_COMPAT_CLIENT_INSTALL_PATH=str(Path.home() / ".local/share/Steam"),
               WINEDEBUG="-all")
    (work / "prefix").mkdir(exist_ok=True)
    env.pop("WINEPREFIX", None)
    with (work / "prefix.log").open("w") as log:
        subprocess.run([str(proton), "run", "C:\\windows\\system32\\cmd.exe", "/c", "exit"],
                       env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    env["WINEPREFIX"] = str(work / "prefix/pfx")
    wine = proton.parent / "files/bin/wine"
    for mode in ("bundled", "existing", "late", "legacy", "planned", "inactive"):
        root = work / mode
        (root / "dbf").mkdir(parents=True, exist_ok=True)
        (root / "standalone").mkdir(exist_ok=True)
        shutil.copyfile(args.dbf, root / "dbf/divers_best_friend.dll")
        shutil.copyfile(args.nest, root / "dbf/goose_overlay.dll")
        (root / "standalone/goose_overlay.dll").write_bytes(legacy if mode == "legacy" else args.nest.read_bytes())
        with (work / (mode + ".log")).open("w") as log:
            result = subprocess.run([str(wine), win(exe), mode], cwd=root, env=env,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=45)
        print((work / (mode + ".log")).read_text(), end="", flush=True)
        result.check_returncode()
    print("PASS production NEST boot in six scenarios. Evidence", work)


if __name__ == "__main__":
    main()
