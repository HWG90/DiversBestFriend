"""Exit successfully only for a verified, separate retail HD2 game or crash reporter."""
from pathlib import Path
import sys


def separate_retail_process(pid, install):
    process = Path("/proc") / str(int(pid))
    prefix = next((item[11:] for item in (process / "environ").read_bytes().split(b"\0")
                   if item.startswith(b"WINEPREFIX=")), None)
    if not prefix:
        return False
    prefix = Path(prefix.decode()).resolve()
    if prefix.parts[-4:] != ("steamapps", "compatdata", "553850", "pfx") or install.resolve().is_relative_to(prefix):
        return False
    cwd = (process / "cwd").resolve(strict=True)
    if cwd.parts[-3:] != ("steamapps", "common", "Helldivers 2"):
        return False
    retail = cwd / "bin"
    if retail.resolve() == (install / "game/bin").resolve():
        return False
    names = {str((retail / name).resolve()) for name in ("helldivers2.exe", "crs-handler.exe")}
    mappings = (process / "maps").read_text()
    if "hellforge_modloader.dll" in mappings.lower():
        return False
    return any(line.split(maxsplit=5)[-1] in names for line in mappings.splitlines())


if __name__ == "__main__":
    try:
        sys.exit(0 if separate_retail_process(sys.argv[1], Path(sys.argv[2])) else 1)
    except (OSError, ValueError):
        sys.exit(1)
