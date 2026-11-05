"""Check the cooldown mappings against a virtual-layout copy of game.dll, offline."""
import hashlib
from pathlib import Path
import re
import struct
import sys

source = (Path(__file__).resolve().parents[1] / "hud/cooldown_dock.lua").read_text()
image = Path(sys.argv[1]).read_bytes()
assert hashlib.sha256(image).hexdigest() == "642b0aac0b4f577054993a965054827455ef143ced9895b2dfd09d1ecd433a37"
pe = struct.unpack_from("<I", image, 60)[0]
assert image[pe:pe+4] == b"PE\0\0" and struct.unpack_from("<I", image, pe+8)[0] == 0x6AB3B43F

entries = {
    0x1446840: "48895c2410574883ec200f2805af3df8",
    0x1839520: "48895c2408488974241048897c24184c",
    0x1839fd0: "4d85c90f84810a00004c8bdc55564155",
    0x144c5c0: "40534883ec204c8bca488bd9488b91e0",
    0x144c2c0: "488b81e00000004532c94c8bc14885c0",
    0x144cfb0: "4883ec28448b014c8bd1418bc0458bc8",
    0x14491f0: "4883ec284c8bc9663991bc0000007507",
    0x1448ad0: "40574883ec20f30f104144488bf90f2e",
}
assert {int(rva, 16) for rva in re.findall(r"b\.base\+(0x[0-9a-f]+)", source)} == entries.keys()
layout = {
    0x12f0c17: "488d8f40e32400",  # Gameplay HUD argument
    0x12e9726: "4883c160",        # Frame argument
    0x1818b9e: "498dbf703e0000",  # Health bar
    0x1818c53: "4d8db7300b0000488bd7498bce",  # Row parent and health child
    0x1839b15: "4d8dbe20090000",  # Badge group
    0x1839c8e: "498dbee00c0000",  # Count text
    0x183aef1: "448b86bc140000488d8ee00c0000",  # Count cache feeds native text
}
for rva, expected in {**entries, **layout}.items():
    assert image.startswith(bytes.fromhex(expected), rva), hex(rva)
for site, target in [(0x12f0c2b, 0x12e96d0), (0x12e97c6, 0x1816a60), (0x1818c60, 0x144c5c0)]:
    assert image[site] == 0xe8 and site+5+struct.unpack_from("<i", image, site+1)[0] == target
print("25480438 dump: all eight dock calls, badge fields and health-bar construction chain verified")
