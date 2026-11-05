#!/usr/bin/env bash
# Fails unless every DLL that <dll> imports is one the game always has next to a mod: KERNEL32.dll or the C runtime
# (msvcrt.dll, ucrtbase.dll, api-ms-win-crt-*.dll). Any other import (user32, d3d11, a MinGW runtime DLL, ...) would
# have to be found at load time and is a refusal waiting to happen, so it is named and fails the build.
# The import table comes from llvm-objdump, else Zig's objdump, else MinGW's objdump, else a PE parser (python3 -I).
# Usage: check_imports.sh <dll>     Settings: HF_ZIG (as build.sh), HF_INSTALL
set -euo pipefail
dll=${1:?usage: check_imports.sh <dll>}
[ -f "$dll" ] || { echo "check_imports: $dll does not exist" >&2; exit 2; }
hf="${HF_INSTALL:-$HOME/.local/share/hellforge-prefix/pfx/drive_c/users/steamuser/Documents/HellForge}"
zig="${HF_ZIG:-$hf/tools/zig-linux/zig}"

try_objdump() { # try_objdump <objdump command...>: sets $imports to the imported DLL names, one per line; fails when it cannot
  imports=$("$@" -p "$dll" 2>/dev/null | sed -n 's/^[[:space:]]*DLL Name:[[:space:]]*//p') || imports=""
  [ -n "$imports" ]
}
imports_with_python() {
  python3 -I - "$dll" <<'PY'
import struct, sys
data = open(sys.argv[1], "rb").read()
def u16(o): return struct.unpack_from("<H", data, o)[0]
def u32(o): return struct.unpack_from("<I", data, o)[0]
if data[:2] != b"MZ": sys.exit("not a PE file")
pe = u32(0x3C)
if data[pe:pe + 4] != b"PE\0\0": sys.exit("no PE signature")
sections = u16(pe + 6)
optional = pe + 24
magic = u16(optional)
if magic not in (0x10B, 0x20B): sys.exit("unknown optional header")
dirs = optional + (96 if magic == 0x10B else 112)   # data directories start here
table = []
for i in range(sections):
    s = optional + u16(pe + 20) + i * 40
    table.append((u32(s + 12), max(u32(s + 8), u32(s + 16)), u32(s + 20)))   # rva, size, raw pointer
def raw(rva):
    for virtual, size, pointer in table:
        if virtual <= rva < virtual + size: return rva - virtual + pointer
    sys.exit("RVA outside every section")
def cstring(offset):
    return data[offset:data.index(b"\0", offset)].decode("ascii")
names = []
for index in (1, 13):                                  # import table, delay-load import table
    rva = u32(dirs + index * 8)
    if rva == 0: continue
    entry = raw(rva)
    while True:
        if index == 1:
            if not any(data[entry:entry + 20]): break
            name_rva = u32(entry + 12); entry += 20
        else:
            if not any(data[entry:entry + 32]): break
            name_rva = u32(entry + 4); entry += 32
        names.append(cstring(raw(name_rva)))
print("\n".join(names))
PY
}

imports=""
{ command -v llvm-objdump >/dev/null 2>&1 && try_objdump llvm-objdump; } \
  || { [ -x "$zig" ] && try_objdump "$zig" objdump; } \
  || { command -v x86_64-w64-mingw32-objdump >/dev/null 2>&1 && try_objdump x86_64-w64-mingw32-objdump; } \
  || imports=$(imports_with_python)

[ -n "$imports" ] || { echo "check_imports: no imports found in $dll (the table could not be read)" >&2; exit 2; }
bad=0
echo "$(basename "$dll") imports:"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  lower=${name,,}
  case $lower in
    kernel32.dll|msvcrt.dll|ucrtbase.dll|api-ms-win-crt-*.dll) echo "  $name" ;;
    *) echo "  $name   <-- not allowed" >&2; bad=1 ;;
  esac
done < <(printf '%s\n' "$imports" | sort -fu)
if [ "$bad" != 0 ]; then echo "check_imports: $(basename "$dll") imports a DLL other than KERNEL32 and the C runtime" >&2; exit 1; fi
echo "check_imports: ok"
