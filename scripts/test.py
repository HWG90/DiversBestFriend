"""Run portable package checks, optionally followed by Windows LuaJIT fixtures."""
import argparse
import os
from pathlib import Path
import runpy
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package-only', action='store_true', help='No game DLL required')
    args = parser.parse_args()
    os.chdir(ROOT)
    subprocess.run([sys.executable, 'scripts/build.py'], check=True)
    subprocess.run([sys.executable, 'native-selection-poc/tests/test_package.py'], check=True)
    if args.package_only:
        return
    runner = runpy.run_path(str(ROOT / 'run_lua.py'))
    if not runner['DLL'].is_file():
        parser.error('Set HD2_LUA51_DLL to your installed game lua51.dll, or use --package-only')
    run = runner['run']
    for path in sorted((ROOT / 'native-selection-poc/tests').glob('*_test.lua')):
        print(path.name, flush=True)
        run(path.read_bytes(), path.name)
    run((ROOT / 'native-selection-poc/test_selection.lua').read_bytes(), 'selection')
    run(b"assert(loadfile('native-selection-poc/NativeStratagemRadial.lua'))", 'assembled syntax')

if __name__ == '__main__':
    main()
