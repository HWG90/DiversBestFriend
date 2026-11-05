"""Exercise the archive host through HF-LLL's real discovery and manager with a mock renderer."""
import os
from pathlib import Path
import runpy
import shutil
import struct
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LOADER = Path(os.environ.get("HF_LLL_ROOT", ROOT.parent / "HF-LLL"))


class ArchiveLifecycle(unittest.TestCase):
    @unittest.skipUnless(shutil.which("luajit") and (LOADER / "src/manager.lua").is_file(),
                         "needs luajit and adjacent HF-LLL sources (or HF_LLL_ROOT)")
    def test_archive_discovery_pending_cleanup_and_exclusive_owner(self):
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
        writer = runpy.run_path(str(ROOT / "build.py"))
        key = writer["resource_hash"]("mods/goose/divers_best_friend")
        archive = writer["make_archive"]({key: struct.pack("<II", len(source), 2) + source})
        with tempfile.TemporaryDirectory() as temp:
            patch = Path(temp) / "9ba626afa44a3aa3.patch_37"
            patch.write_bytes(archive)
            subprocess.run(["luajit", HERE.parent / "tests/hud_archive_lifecycle.lua", patch],
                           cwd=LOADER, check=True)
