"""Test the private HUD factory's exclusive owner and deferred cleanup."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent

class HudLifecycle(unittest.TestCase):
    @unittest.skipUnless(shutil.which("luajit"), "needs LuaJIT")
    def test_private_factory_defers_release_and_prevents_a_second_owner(self):
        fixture = """
function() return { expected_dt = 0.25 } end,
function()
    local function update(self, dt)
        assert(dt == expected_dt)
        _G.updates = (_G.updates or 0) + 1
    end
    return { dbf_hud_runtime = function()
        return { update = update, shutdown = function() return _G.allow_release == true end }
    end }
end,
"""
        source = (HERE / "hud_archive_host.lua").read_text().replace("-- @modules@", fixture).encode()
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "private.lua"
            path.write_bytes(source)
            subprocess.run(["luajit", HERE.parent / "tests/hud_archive_lifecycle.lua", path], check=True)
