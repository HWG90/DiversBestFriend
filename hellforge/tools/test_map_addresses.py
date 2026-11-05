"""Tests for map_addresses.py (the 25480438 address table).

Run from the repository root:
    DBF_R46_DIR=<R46 native-selection-poc folder> python3 -I -B -m unittest discover -s hellforge/tools -p 'test_*.py'

The synthetic tests always run. The tests on the real inputs need DBF_R46_DIR (R46's HellForge native-selection-poc
folder) and HellForge's game copy and SDK (HF_INSTALL, default HellForge 0.4's Linux install,
~/.local/share/hellforge-prefix/pfx/drive_c/users/steamuser/Documents/HellForge); without them they are skipped and
say why. The compile tests also need HellForge's Zig (HF_ZIG).
"""
import json
import os
import random
import re
import struct
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import map_addresses as ma  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
HELLFORGE = os.path.dirname(HERE)
SRC = os.path.join(HELLFORGE, "divers-best-friend", "src")
RECEIPTS = os.path.join(HELLFORGE, "receipts")
HF_INSTALL = os.environ.get("HF_INSTALL", os.path.expanduser(
    "~/.local/share/hellforge-prefix/pfx/drive_c/users/steamuser/Documents/HellForge"))
GAME_DLL = os.path.join(HF_INSTALL, "game", "data", "game", "game.dll")
CONTENT_H = os.path.join(os.environ.get("HF_SDK", os.path.join(HF_INSTALL, "app", "sdk")), "hellforge_content.h")
ZIG = os.environ.get("HF_ZIG", os.path.join(HF_INSTALL, "migration", "toolchain", "zig-x86_64-linux-0.17.0", "zig"))
R46 = os.environ.get("DBF_R46_DIR", "")

HAVE_REAL = bool(R46) and os.path.isfile(os.path.join(R46, "guards.lua")) and os.path.isfile(GAME_DLL) \
    and os.path.isfile(CONTENT_H)
WHY_NO_REAL = "set DBF_R46_DIR to R46's native-selection-poc folder and HF_INSTALL to a HellForge 25480438 install"
HAVE_ZIG = os.path.isfile(ZIG) and os.access(ZIG, os.X_OK)

FEATURE_ORDER = ["STATE", "STRATAGEMS", "HUD_READ", "LIST_OPACITY", "ENTRY", "SCRAMBLE", "POINTING", "CAMERA",
                 "LATCH", "SOUND", "DOCK", "WEAPON", "TERMINAL"]


def zig_compile(directory, source_text, name, target=None):
    """Compiles one probe translation unit with the mod's warning flags. Zig 0.17.0's -fsyntax-only still passes -c
    and then fails to move an object it never wrote, so the probe is compiled to an object instead (a superset)."""
    probe = os.path.join(directory, name + ".c")
    with open(probe, "w", encoding="utf-8", newline="\n") as f:
        f.write(source_text)
    cache = os.path.join(HELLFORGE, "build", "zig-cache")
    os.makedirs(cache, exist_ok=True)
    env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=cache, ZIG_LOCAL_CACHE_DIR=cache)
    command = [ZIG, "cc", "-std=c11", "-Wall", "-Werror", "-Wno-unused-parameter", "-I", directory, "-c", probe,
               "-o", os.path.join(directory, name + ".o")]
    if target:
        command[2:2] = ["-target", target]
    return subprocess.run(command, capture_output=True, text=True, env=env)


# --- synthetic inputs -------------------------------------------------------------------------------------------

def make_pe(sections, stamp=0x6AB3B43F, image_size=0x40000):
    """A minimal PE32+ image: sections are (va, vsize, raw bytes). Raw data is laid out from file offset 0x400."""
    pe_offset = 0x80
    optional_size = 0xF0
    header = bytearray(0x400)
    header[0:2] = b"MZ"
    struct.pack_into("<I", header, 0x3C, pe_offset)
    header[pe_offset:pe_offset + 4] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", header, pe_offset + 4, 0x8664, len(sections), stamp, 0, 0, optional_size, 0x2022)
    optional = pe_offset + 24
    struct.pack_into("<H", header, optional, 0x20B)
    struct.pack_into("<I", header, optional + 56, image_size)
    struct.pack_into("<I", header, optional + 108, 16)
    raw = bytearray()
    table = optional + optional_size
    for i, (va, vsize, data) in enumerate(sections):
        raw_ptr = 0x400 + len(raw) if data else 0
        struct.pack_into("<8sIIII", header, table + 40 * i, b"", vsize, va, len(data), raw_ptr)
        struct.pack_into("<I", header, table + 40 * i + 36, 0x60000020)
        raw += data
    return bytes(header) + bytes(raw)


def lua_bytes(data):
    return "".join("\\x%02x" % b for b in data)


class Fixture:
    """A synthetic R46 folder, game.dll, address table and content header in a temporary directory."""

    def __init__(self, directory):
        self.dir = directory
        self.r46 = os.path.join(directory, "r46")
        os.makedirs(self.r46)
        rng = random.Random(25480438)
        self.packed = rng.randbytes(0x10000)       # section 1: encrypted-looking raw data
        self.plain = bytes(0x2000)                 # section 3: raw data that is not packed (zeros)
        self.dll = os.path.join(directory, "game.dll")
        self.content = os.path.join(directory, "hellforge_content.h")
        self.table = os.path.join(directory, "addresses.json")
        self.out_h = os.path.join(directory, "out", "addresses_25480438.h")
        self.kinds = os.path.join(directory, "out", "kind_names_25480438.h")
        self.receipt = os.path.join(directory, "out", "receipt.json")
        with open(self.content, "w", encoding="utf-8") as f:
            f.write('#define HF_STRATAGEM_ALPHA 1u /* Alpha "One" - a thing */\n'
                    '#define HF_STRATAGEM_BETA 3u /* Beta\\Two */\n')
        self.stamp = 0x6AB3B43F
        # entry_fn and same match section 1 (same lies 0x10 above the bound entry_fn); gone lies in section 2, which
        # has no raw data; packed differs in section 1 (packed on disk) and is marked; layout matches section 3.
        self.guards = [
            ("entry_fn", 0x1000, self.packed[0:16]),
            ("same", 0x1010, self.packed[0x10:0x20]),
            ("gone", 0x20100, b"\x48\x89\x5c\x24\x08"),
            ("packed", 0x6000, b"\x90" * 8),
            ("layout", 0x22000, bytes(4)),
            ("unused", 0x20200, b"\xcc\xcc"),
        ]
        self.native = ["-- synthetic native.lua", "local root=pointer(base+0x22800)",
                       "local panel=root+0x24e340+0x146dc0", "local fn=ffi.cast('void (*)(void)',base+0x1000)"]
        self.entries = {
            "build": "25480438",
            "addresses": [
                {"name": "HUD_ROOT", "kind": "rva", "value": "0x22800", "source": "R46 native.lua:2"},
                {"name": "HUD_PANEL_OFFSET", "kind": "offset", "value": "0x395100", "expr": "0x24e340+0x146dc0",
                 "source": "R46 native.lua:3"},
            ],
            "bound_functions": {
                "entry_fn": {"rva": "0x1000", "features": ["ENTRY"], "source": "R46 native.lua:4"},
            },
            "witnesses": {
                "entry_fn": {"features": ["ENTRY"], "reason": "the bound function itself"},
                "same": {"features": ["ENTRY", "LATCH"], "reason": "inside entry_fn"},
                "gone": {"features": ["HUD_READ"], "reason": "layout"},
                "packed": {"features": ["STATE"], "reason": "layout", "file_check": "expect_differs",
                           "file_check_reason": "section 1 is packed on disk"},
                "layout": {"features": ["STATE"], "reason": "layout"},
                "unused": {"dropped": True, "reason": "guards code the port never calls"},
            },
        }

    def write(self, sections=None):
        if sections is None:
            sections = [(0x1000, 0x1F000, self.packed), (0x20000, 0x1000, b""), (0x22000, 0x2000, self.plain)]
        with open(self.dll, "wb") as f:
            f.write(make_pe(sections, stamp=self.stamp))
        lines = ["local native_guards = {"]
        for name, rva, data in self.guards:
            lines.append("    {name='%s',rva=0x%x,bytes='%s'}," % (name, rva, lua_bytes(data)))
        lines.append("}")
        with open(os.path.join(self.r46, "guards.lua"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        with open(os.path.join(self.r46, "native.lua"), "w", encoding="utf-8") as f:
            f.write("\n".join(self.native) + "\n")
        with open(self.table, "w", encoding="utf-8") as f:
            json.dump(self.entries, f, indent=2)

    def run(self):
        self.write()
        err = StringIO()
        with redirect_stderr(err), redirect_stdout(StringIO()):
            code = ma.main([self.r46, self.dll, self.out_h, self.receipt, "--table", self.table,
                            "--content-header", self.content, "--kind-names", self.kinds])
        return code, err.getvalue()


class SyntheticTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def test_parse_guards_both_quotes_and_lines(self):
        text = ("-- comment\nlocal g = {\n    {name='a',rva=0x10,bytes='\\x01\\x02'},\n}\n"
                'g[#g+1]={name="b",rva=0x20,bytes="\\xff"}\n'
                "g[#g+1]={name='c',rva=0x30,bytes=''}\n")
        guards = ma.parse_guards(text)
        self.assertEqual([(g.name, g.rva, g.data, g.line) for g in guards],
                         [("a", 0x10, b"\x01\x02", 3), ("b", 0x20, b"\xff", 5), ("c", 0x30, b"", 6)])

    def test_parse_guards_rejects_other_escapes_and_duplicates(self):
        with self.assertRaises(ma.GeneratorError):
            ma.parse_guards("g={ {name='a',rva=0x10,bytes='\\n'} }")
        with self.assertRaises(ma.GeneratorError):
            ma.parse_guards("g={ {name='a',rva=0x10,bytes='\\x01'}, {name='a',rva=0x20,bytes='\\x02'} }")

    def test_pe_reader_maps_rvas_through_sections(self):
        self.fx.write()
        with open(self.fx.dll, "rb") as f:
            pe = ma.PeImage(f.read())
        self.assertEqual(pe.stamp, 0x6AB3B43F)
        self.assertEqual(pe.file_offset(0x1000, 4), 0x400)
        self.assertEqual(pe.file_offset(0x1010, 16), 0x410)
        self.assertIsNone(pe.file_offset(0x20100, 4))           # section with no raw data
        self.assertIsNone(pe.file_offset(0x10FFE, 4))            # straddles the end of section 1's raw data
        with self.assertRaises(ma.GeneratorError):
            pe.file_offset(0x50000, 4)                           # in no section

    def test_checks_file_unreadable_and_expected_differs(self):
        code, err = self.fx.run()
        self.assertEqual(code, 0, err)
        with open(self.fx.receipt, encoding="utf-8") as f:
            receipt = json.load(f)
        checks = {w["name"]: w["check"] for w in receipt["witnesses"]}
        self.assertEqual(checks["same"], "file")
        self.assertEqual(checks["gone"], "unreadable")
        self.assertEqual(checks["packed"], "expect_differs")
        self.assertEqual(checks["layout"], "file")

    def test_unexpected_difference_fails_and_names_every_witness(self):
        self.fx.guards.append(("bad", 0x6100, b"\x90" * 8))
        self.fx.guards.append(("worse", 0x22010, b"\x01\x02"))
        self.fx.entries["witnesses"]["bad"] = {"features": ["STATE"], "reason": "layout"}
        self.fx.entries["witnesses"]["worse"] = {"features": ["STATE"], "reason": "layout"}
        code, err = self.fx.run()
        self.assertNotEqual(code, 0)
        self.assertIn("bad", err)
        self.assertIn("worse", err)
        self.assertFalse(os.path.exists(self.fx.out_h), "nothing is written when a witness differs")
        self.assertFalse(os.path.exists(self.fx.receipt))

    def test_expect_differs_needs_a_packed_section(self):
        self.fx.guards.append(("plain", 0x22010, b"\x01\x02"))
        self.fx.entries["witnesses"]["plain"] = {"features": ["STATE"], "reason": "layout",
                                                 "file_check": "expect_differs", "file_check_reason": "claimed"}
        code, err = self.fx.run()
        self.assertNotEqual(code, 0)
        self.assertIn("plain", err)

    def test_expect_differs_on_matching_bytes_is_stale(self):
        self.fx.entries["witnesses"]["same"]["file_check"] = "expect_differs"
        self.fx.entries["witnesses"]["same"]["file_check_reason"] = "stale"
        code, err = self.fx.run()
        self.assertNotEqual(code, 0)
        self.assertIn("same", err)

    def test_wrong_build_is_refused(self):
        self.fx.stamp = 0x6AE0E5FF
        code, err = self.fx.run()
        self.assertNotEqual(code, 0)
        self.assertIn("6ae0e5ff", err.lower())

    def test_every_guard_needs_an_assignment(self):
        del self.fx.entries["witnesses"]["layout"]
        self.fx.entries["witnesses"]["ghost"] = {"features": ["STATE"], "reason": "not in guards.lua"}
        code, err = self.fx.run()
        self.assertNotEqual(code, 0)
        self.assertIn("layout", err)
        self.assertIn("ghost", err)

    def test_witness_must_carry_its_bound_functions_features(self):
        self.fx.entries["witnesses"]["same"]["features"] = ["LATCH"]   # 0x10 above entry_fn (ENTRY)
        code, err = self.fx.run()
        self.assertNotEqual(code, 0)
        self.assertIn("same", err)
        self.assertIn("entry_fn", err)

    def test_cited_source_line_must_hold_the_value(self):
        self.fx.entries["addresses"][0]["source"] = "R46 native.lua:4"
        code, err = self.fx.run()
        self.assertNotEqual(code, 0)
        self.assertIn("HUD_ROOT", err)
        self.fx.entries["addresses"][0]["source"] = "R46 native.lua:2"
        self.fx.entries["addresses"][1]["value"] = "0x395104"
        code, err = self.fx.run()
        self.assertNotEqual(code, 0)
        self.assertIn("HUD_PANEL_OFFSET", err)

    def test_header_emits_defines_masks_and_omits_dropped(self):
        code, err = self.fx.run()
        self.assertEqual(code, 0, err)
        with open(self.fx.out_h, encoding="utf-8") as f:
            header = f.read()
        self.assertTrue(header.startswith("/* Generated by tools/map_addresses.py. Do not edit by hand"))
        self.assertIn("#define DBF_RVA_HUD_ROOT 0x22800u /* R46 native.lua:2 */", header)
        self.assertIn("#define DBF_OFF_HUD_PANEL_OFFSET 0x395100u", header)
        defined = re.findall(r"^#define DBF_FEATURE_([A-Z_]+) (\d+)$", header, re.M)
        self.assertEqual(defined, [(n, str(i)) for i, n in enumerate(FEATURE_ORDER)] + [("COUNT", "13")])
        self.assertIn('{ "same", 0x1010u, 16, (1u << DBF_FEATURE_ENTRY) | (1u << DBF_FEATURE_LATCH), ', header)
        self.assertNotIn('"unused"', header)
        with open(self.fx.kinds, encoding="utf-8") as f:
            kinds = f.read()
        self.assertTrue(kinds.startswith("/* Generated by tools/map_addresses.py. Do not edit by hand"))
        self.assertIn('[1] = "Alpha \\"One\\""', kinds)
        self.assertIn('[3] = "Beta\\\\Two"', kinds)
        with open(self.fx.receipt, encoding="utf-8") as f:
            receipt = json.load(f)
        dropped = [w for w in receipt["witnesses"] if w.get("dropped")]
        self.assertEqual([w["name"] for w in dropped], ["unused"])
        self.assertEqual(dropped[0]["reason"], "guards code the port never calls")

    def add_value_lines(self):
        """native.lua:5-8, lines holding constants as R46 writes them (decimal and hex)."""
        self.fx.native += ["if u32(read(state+0xac21c,4),0)~=4 then return nil end",
                           "local key=num(registry+0xf32f20+24*lookup(registry,0xf22ec8,network,65536))",
                           "assert(network<0x7fff,'Local network index unavailable')",
                           "local at=base+141312"]

    def test_value_kind_emits_val_defines_after_the_addresses(self):
        self.add_value_lines()
        self.fx.entries["addresses"] += [
            {"name": "GAMEPLAY_MODE", "kind": "value", "value": "4", "source": "R46 native.lua:5"},
            {"name": "LOOKUP_LIMIT", "kind": "value", "value": "65536", "source": "R46 native.lua:6"},
            {"name": "NETWORK_LIMIT", "kind": "value", "value": "0x7fff", "source": "R46 native.lua:7"},
            {"name": "MENU_CLOSED", "kind": "value", "value": "0", "source": "R46 native.lua:5"},
        ]
        code, err = self.fx.run()
        self.assertEqual(code, 0, err)
        with open(self.fx.out_h, encoding="utf-8") as f:
            header = f.read()
        self.assertIn("#define DBF_VAL_GAMEPLAY_MODE 4u /* R46 native.lua:5 */", header)
        self.assertIn("#define DBF_VAL_LOOKUP_LIMIT 65536u /* R46 native.lua:6 */", header)
        self.assertIn("#define DBF_VAL_NETWORK_LIMIT 0x7fffu /* R46 native.lua:7 */", header)
        self.assertIn("#define DBF_VAL_MENU_CLOSED 0u /* R46 native.lua:5 */", header)
        self.assertLess(header.index("DBF_OFF_HUD_PANEL_OFFSET"), header.index("DBF_VAL_GAMEPLAY_MODE"),
                        "values follow the addresses")
        self.assertNotIn("DBF_RVA_GAMEPLAY_MODE", header)
        self.assertNotIn("DBF_OFF_GAMEPLAY_MODE", header)
        with open(self.fx.receipt, encoding="utf-8") as f:
            receipt = json.load(f)
        rows = {a["name"]: a for a in receipt["addresses"]}
        self.assertEqual(rows["GAMEPLAY_MODE"]["kind"], "value")
        self.assertEqual(rows["GAMEPLAY_MODE"]["value"], "4")
        self.assertEqual(rows["GAMEPLAY_MODE"]["define"], "DBF_VAL_GAMEPLAY_MODE")
        self.assertEqual(rows["NETWORK_LIMIT"]["value"], "0x7fff")
        self.assertEqual(receipt["tally"]["addresses"], 2)
        self.assertEqual(receipt["tally"]["values"], 4)

    def test_value_must_appear_on_its_line_as_a_whole_literal(self):
        self.add_value_lines()
        for value, line in (("5", 5), ("4", 2), ("6", 6), ("553", 6), ("0x7ff", 7), ("141313", 8)):
            with self.subTest(value=value, line=line):
                self.fx.entries["addresses"] = self.fx.entries["addresses"][:2] + [
                    {"name": "PROBE", "kind": "value", "value": value, "source": "R46 native.lua:%d" % line}]
                code, err = self.fx.run()
                self.assertNotEqual(code, 0, "%s is not a literal of native.lua:%d" % (value, line))
                self.assertIn("PROBE", err)
                self.assertFalse(os.path.exists(self.fx.out_h))

    def test_value_format(self):
        self.add_value_lines()
        for value in ("4.0", "-4", "0X7fff", "04", "", "0x", 4, "4294967296"):
            with self.subTest(value=value):
                self.fx.entries["addresses"] = self.fx.entries["addresses"][:2] + [
                    {"name": "PROBE", "kind": "value", "value": value, "source": "R46 native.lua:5"}]
                code, err = self.fx.run()
                self.assertNotEqual(code, 0, repr(value))
                self.assertIn("PROBE", err)

    def test_offsets_may_be_written_in_decimal_but_rvas_may_not(self):
        self.add_value_lines()
        self.fx.entries["addresses"].append(
            {"name": "REGISTRY_KEY_STRIDE", "kind": "offset", "value": "0x18", "source": "R46 native.lua:6"})
        code, err = self.fx.run()
        self.assertEqual(code, 0, err)
        with open(self.fx.out_h, encoding="utf-8") as f:
            self.assertIn("#define DBF_OFF_REGISTRY_KEY_STRIDE 0x18u /* R46 native.lua:6 */", f.read())
        self.fx.entries["addresses"][-1]["value"] = "0x19"
        code, err = self.fx.run()
        self.assertNotEqual(code, 0)
        self.assertIn("REGISTRY_KEY_STRIDE", err)
        self.fx.entries["addresses"][-1] = {"name": "HUD_ROOT_DECIMAL", "kind": "rva", "value": "0x22800",
                                           "source": "R46 native.lua:8"}
        code, err = self.fx.run()
        self.assertNotEqual(code, 0, "an RVA must appear in hex")
        self.assertIn("HUD_ROOT_DECIMAL", err)

    def test_value_names_share_the_address_namespace(self):
        self.add_value_lines()
        self.fx.entries["addresses"].append({"name": "HUD_ROOT", "kind": "value", "value": "4",
                                             "source": "R46 native.lua:5"})
        code, err = self.fx.run()
        self.assertNotEqual(code, 0)
        self.assertIn("HUD_ROOT", err)

    @unittest.skipUnless(HAVE_ZIG, "HellForge's Zig is not installed (HF_ZIG)")
    def test_synthetic_headers_compile(self):
        code, err = self.fx.run()
        self.assertEqual(code, 0, err)
        out = os.path.dirname(self.fx.out_h)
        result = zig_compile(out, '#define DBF_ADDRESSES_DEFINE\n#include "addresses_25480438.h"\n'
                                  '#include "kind_names_25480438.h"\n'
                                  'int probe(void);\nint probe(void) { return dbf_witness_count; }\n', "define")
        self.assertEqual(result.returncode, 0, result.stderr)


@unittest.skipUnless(HAVE_REAL, WHY_NO_REAL)
class RealInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.out = cls._tmp.name
        cls.header = os.path.join(cls.out, "addresses_25480438.h")
        cls.kinds = os.path.join(cls.out, "kind_names_25480438.h")
        cls.receipt_path = os.path.join(cls.out, "addresses-25480438.json")
        err = StringIO()
        with redirect_stderr(err), redirect_stdout(StringIO()):
            cls.code = ma.main([R46, GAME_DLL, cls.header, cls.receipt_path, "--content-header", CONTENT_H,
                                "--kind-names", cls.kinds])
        cls.err = err.getvalue()
        cls.receipt = None
        if cls.code == 0:
            with open(cls.receipt_path, encoding="utf-8") as f:
                cls.receipt = json.load(f)

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def read(self, path):
        with open(path, encoding="utf-8") as f:
            return f.read()

    def test_r46_guards(self):
        with open(os.path.join(R46, "guards.lua"), encoding="latin-1") as f:
            guards = ma.parse_guards(f.read())
        self.assertEqual(len(guards), 92)
        by_name = {g.name: g for g in guards}
        self.assertEqual(by_name["position"].rva, 0x14476A0)
        self.assertEqual(len(by_name["position"].data), 32)
        self.assertEqual(by_name["hud_root"].rva, 0xAD9D8E)

    def test_pe_reader_on_game_dll(self):
        with open(GAME_DLL, "rb") as f:
            pe = ma.PeImage(f.read())
        self.assertEqual(pe.stamp, 0x6AB3B43F)
        self.assertEqual(pe.file_offset(0x1000, 1), 0x600)
        self.assertEqual(pe.file_offset(0x2111000, 1), 0x850E00)
        self.assertIsNone(pe.file_offset(0x14476A0, 32))      # first section: no raw data this far

    def test_generator_succeeds(self):
        self.assertEqual(self.code, 0, self.err)

    def test_every_emitted_witness_is_checked(self):
        self.assertIsNotNone(self.receipt, self.err)
        emitted = [w for w in self.receipt["witnesses"] if not w.get("dropped")]
        self.assertTrue(emitted)
        for w in emitted:
            self.assertIn(w["check"], ("file", "unreadable", "expect_differs"), w["name"])
        self.assertNotIn("differs", [w["check"] for w in self.receipt["witnesses"]])
        self.assertEqual(len(self.receipt["witnesses"]), 92)

    def test_header_has_the_hud_root(self):
        self.assertEqual(self.code, 0, self.err)
        self.assertIn("#define DBF_RVA_HUD_ROOT 0x346d538", self.read(self.header))

    def test_header_has_the_reader_values(self):
        self.assertEqual(self.code, 0, self.err)
        header = self.read(self.header)
        for define in ("#define DBF_VAL_GAMEPLAY_MODE 4u", "#define DBF_VAL_HUD_READY 1u",
                       "#define DBF_VAL_CARD_COUNT 16u", "#define DBF_VAL_LOOKUP_MAX_CAPACITY 65536u",
                       "#define DBF_VAL_VANILLA_KINDS 149u", "#define DBF_VAL_DEFINITION_RELOCATION_SPAN 0x400000u"):
            self.assertIn(define, header)

    def test_kind_names(self):
        self.assertEqual(self.code, 0, self.err)
        kinds = self.read(self.kinds)
        self.assertIn('[118] = "Orbital Precision Strike"', kinds)
        self.assertIn('[4] = "Orbital Gatling Barrage"', kinds)
        self.assertIn("static const char* const dbf_kind_names[150]", kinds)
        self.assertNotIn("[0] =", kinds)

    def test_receipt_holds_hashes_and_no_machine_paths(self):
        self.assertIsNotNone(self.receipt, self.err)
        self.assertEqual(self.receipt["game_dll"]["time_date_stamp"], "0x6ab3b43f")
        self.assertRegex(self.receipt["game_dll"]["sha256"], r"^[0-9a-f]{64}$")
        self.assertIn("guards.lua", self.receipt["inputs"])
        text = json.dumps(self.receipt)
        for part in (os.path.expanduser("~"), R46, HF_INSTALL):
            self.assertNotIn(part, text)

    @unittest.skipUnless(HAVE_ZIG, "HellForge's Zig is not installed (HF_ZIG)")
    def test_headers_compile_for_linux_and_windows(self):
        self.assertEqual(self.code, 0, self.err)
        define = ('#define DBF_ADDRESSES_DEFINE\n#include "addresses_25480438.h"\n#include "kind_names_25480438.h"\n'
                  'int probe(void);\nint probe(void) { return dbf_witness_count + (dbf_kind_names[118] != 0); }\n')
        use = ('#include "addresses_25480438.h"\n#include "kind_names_25480438.h"\n'
               'int probe(void);\nint probe(void) { return dbf_witnesses[0].size + (int)DBF_RVA_HUD_ROOT; }\n')
        for target in (None, "x86_64-windows-gnu"):
            for name, text in (("define", define), ("use", use)):
                result = zig_compile(self.out, text, "%s_%s" % (name, target or "native"), target)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_committed_files_are_current(self):
        self.assertEqual(self.code, 0, self.err)
        for fresh, committed in ((self.header, os.path.join(SRC, "addresses_25480438.h")),
                                 (self.kinds, os.path.join(SRC, "kind_names_25480438.h")),
                                 (self.receipt_path, os.path.join(RECEIPTS, "addresses-25480438.json"))):
            self.assertTrue(os.path.isfile(committed), committed)
            self.assertEqual(self.read(fresh), self.read(committed), os.path.basename(committed))


if __name__ == "__main__":
    unittest.main()
