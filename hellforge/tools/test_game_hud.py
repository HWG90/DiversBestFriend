"""Run the engine HUD regressions as part of build.sh test."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

HF = Path(__file__).resolve().parents[1]
TESTS = HF / "tests"


class GameHud(unittest.TestCase):
    def test_engine_controllers(self):
        for script in ("test_hud_runtime", "test_hud_wheel_input", "binding_warning",
                       "cooldown_hud", "offline_terminal"):
            with self.subTest(controller=script):
                subprocess.run(["luajit", TESTS / (script + ".lua")], cwd=HF.parent, check=True)

    @unittest.skipUnless(os.environ.get("DBF_WEAPON_IMAGE"), "requires mapped game build 25480438")
    def test_native_hud_and_terminal_witnesses(self):
        image = os.environ["DBF_WEAPON_IMAGE"]
        for script in ("wheel_admission_dump", "cooldown_dump", "terminal_mapping"):
            with self.subTest(mapping=script):
                subprocess.run([sys.executable, TESTS / (script + ".py"), image], cwd=HF.parent, check=True)
