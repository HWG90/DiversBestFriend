"""Build the current native addon from any working directory."""
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[1]
if __name__ == '__main__':
    runpy.run_path(str(ROOT / 'native-selection-poc/build_poc.py'), run_name='__main__')
