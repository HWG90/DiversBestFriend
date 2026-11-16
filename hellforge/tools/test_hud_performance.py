"""Exercise actual HUD controllers with counted native calls and frame clocks."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class HudPerformance(unittest.TestCase):
    def test_controllers(self):
        for name in ("test_hud_pacing", "test_hud_retained"):
            with self.subTest(name=name):
                subprocess.run(["luajit", f"hellforge/tests/{name}.lua"], cwd=ROOT, check=True)
