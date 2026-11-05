"""Run with python3 hellforge/tests/wheel_admission_dump.py <25480438 RVA-layout dump>."""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tools"))
import hud_pack

def main():
    image = Path(sys.argv[1]).resolve()
    if hashlib.sha256(image.read_bytes()).hexdigest() != "642b0aac0b4f577054993a965054827455ef143ced9895b2dfd09d1ecd433a37":
        sys.exit("Expected the 25480438 RVA-layout dump")
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / "hud.lua"
        source.write_bytes(hud_pack.render())
        subprocess.run(["luajit", str(HERE / "wheel_admission_dump.lua"), str(source), str(image)], check=True)

if __name__ == "__main__":
    main()
