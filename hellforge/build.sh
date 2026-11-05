#!/usr/bin/env bash
# Builds, tests and installs Diver's Best Friend for HellForge (the native C port in hellforge/divers-best-friend).
# Usage: ./build.sh dll                          the mod's DLL, built exactly as HellForge builds a source mod, then its
#                                                import check (tests/check_imports.sh)
#        ./build.sh test                         the Linux unit tests: tests/test_*.c with the portable units of src/
#        ./build.sh wine-test                    the tests that need the Windows build (Wine; none yet)
#        ./build.sh install <HellForge installation>
#                                                copies the mod into <installation>/mods/divers-best-friend, after
#                                                backing up what was there into <installation>/backport-backups/<UTC>/
# Zig is the native Linux 0.17.0, HellForge's pinned version (Wine cannot run zig.exe: its cache locking calls NtLockFile
# in a way Wine does not implement). Settings: HF_INSTALL (the HellForge installation the toolchain and SDK come from;
# default HellForge 0.4's Linux install, ~/.local/share/hellforge-prefix/pfx/drive_c/users/steamuser/Documents/HellForge),
# HF_ZIG (default the installation's tools/zig-linux Zig), HF_SDK (the mod SDK headers; default the installation's
# app/sdk), HF_PGREP (the pgrep install asks whether the game or HellForge runs; default pgrep).
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo="$(dirname "$here")"
mod="$here/divers-best-friend"
dllName=divers_best_friend.dll
gameBuild=25480438
hf="${HF_INSTALL:-$HOME/.local/share/hellforge-prefix/pfx/drive_c/users/steamuser/Documents/HellForge}"
zig="${HF_ZIG:-$hf/tools/zig-linux/zig}"
sdk="${HF_SDK:-$hf/app/sdk}"
export ZIG_GLOBAL_CACHE_DIR="$here/build/zig-cache" ZIG_LOCAL_CACHE_DIR="$here/build/zig-cache"

die() { echo "$*" >&2; exit 1; }
toolchain() {
  [ -x "$zig" ] && [ "$("$zig" version)" = 0.17.0 ] || die "no Zig 0.17.0 at $zig (set HF_ZIG)"
  [ -f "$sdk/hellforge_mod.h" ] || die "no mod SDK at $sdk (set HF_SDK)"
  mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
}

build_dll() {
  toolchain
  shopt -s nullglob
  local sources=("$mod"/src/*.c)
  shopt -u nullglob
  [ ${#sources[@]} -gt 0 ] || die "no C sources in $mod/src (expected src/dbf.c)"
  [ -f "$mod/src/dbf.c" ] || die "$mod/src/dbf.c is missing"
  # HellForge's source-mod flags (ModKit.Flags), run from the mod folder as HellForge runs them. A DLL from an earlier
  # build is removed first, so a failed build never leaves a stale one behind.
  rm -f "$mod/$dllName"
  (cd "$mod" && "$zig" cc -std=c11 -target x86_64-windows-gnu -shared -O2 -Wall -Werror -Wno-unused-parameter -s \
      -I "$sdk" src/*.c -o "$dllName") || die "The mod did not compile with HellForge's source-mod flags."
  rm -f "$mod"/*.lib
  echo "Built $mod/$dllName ($(( $(stat -c %s "$mod/$dllName") / 1024 )) KB, SHA-256 $(sha256sum "$mod/$dllName" | cut -c1-16)...)"
  "$here/tests/check_imports.sh" "$mod/$dllName"
}

run_tests() {
  shopt -s nullglob
  local tests=("$here"/tests/test_*.c) sources=() helpers=() file
  shopt -u nullglob
  if [ ${#tests[@]} -eq 0 ]; then echo "no tests yet (tests/test_*.c)"; return 0; fi
  toolchain
  # The portable units of src/ (not the entry point and not the Windows platform layer) and the test helpers (the POSIX
  # platform layer among them; the Wine host belongs to wine-test).
  for file in "$mod"/src/*.c; do
    case ${file##*/} in dbf.c|platform_win.c) ;; *) sources+=("$file") ;; esac
  done
  for file in "$here"/tests/*.c; do
    case ${file##*/} in test_*.c|wine_host.c) ;; *) helpers+=("$file") ;; esac
  done
  mkdir -p "$here/build/tests"
  local passed=0 failed=0 test name first flags
  for test in "${tests[@]}"; do
    name=${test##*/}; name=${name%.c}
    flags=()
    first=$(head -n 1 "$test" | tr -d '\r')
    if [[ $first =~ ^/\*[[:space:]]*flags:[[:space:]]*(.*)\*/[[:space:]]*$ ]]; then read -r -a flags <<<"${BASH_REMATCH[1]}"; fi
    if ! "$zig" cc -std=c11 -Wall -Werror -Wno-unused-parameter -g -O1 ${flags[@]+"${flags[@]}"} \
        -I "$mod/src" -I "$here/tests" -I "$sdk" "$test" ${sources[@]+"${sources[@]}"} ${helpers[@]+"${helpers[@]}"} \
        -o "$here/build/tests/$name"; then
      echo "FAIL $name (did not compile)"; failed=$((failed + 1)); continue
    fi
    if timeout 120 "$here/build/tests/$name"; then echo "PASS $name"; passed=$((passed + 1))
    else echo "FAIL $name (exit $?)"; failed=$((failed + 1)); fi
  done
  echo "tests: $passed passed, $failed failed"
  [ "$failed" -eq 0 ]
}

run_wine_tests() {
  echo "no wine tests yet"
}

running() { # the game or HellForge (by process name, or by the Windows exe in a Wine/Proton command line, or the
  # native Linux launcher of HellForge 0.4, whose process name is cut to "HellForge.Launc")
  local pgrep=${HF_PGREP:-pgrep}
  "$pgrep" -xi 'helldivers2\.exe|HellForge\.exe|HellForge\.Launc(her)?' >/dev/null 2>&1 \
    || "$pgrep" -fi '(^|[\\/ ])(helldivers2|HellForge(\.Launcher)?)\.exe( |$)' >/dev/null 2>&1
}

install_mod() {
  local install=${1:?usage: build.sh install <HellForge installation>}
  [ -f "$install/hellforge-install.json" ] && [ -d "$install/mods" ] || die "$install is not a HellForge installation."
  if running; then die "helldivers2.exe or HellForge.exe is running. Close the game and HellForge, then install again."; fi
  [ -f "$mod/$dllName" ] || die "$mod/$dllName is not built yet (./build.sh dll)."
  if [ -n "$(find "$mod/src" "$mod/hellforge-mod.json" -newer "$mod/$dllName" -print -quit)" ]; then
    die "The sources or the manifest are newer than $dllName (./build.sh dll)."
  fi
  "$here/tests/check_imports.sh" "$mod/$dllName" >/dev/null || die "$dllName fails its import check (./build.sh dll shows why)."

  local stamp backup dest="$install/mods/divers-best-friend" commit dirty=false
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  backup="$install/backport-backups/$stamp"
  mkdir -p "$install/backport-backups"
  mkdir "$backup" || die "$backup already exists."
  if [ -e "$dest" ]; then cp -a "$dest" "$backup/previous"; fi
  if [ -f "$install/mods/hellforge-mods.json" ]; then cp -a "$install/mods/hellforge-mods.json" "$backup/"; fi

  # The mod folder as it is shipped: nothing else in this folder goes along, and nothing old stays in src/.
  rm -rf "$dest"
  mkdir -p "$dest"
  cp "$mod/hellforge-mod.json" "$mod/$dllName" "$mod/LICENSE" "$dest/"
  if [ -f "$mod/README.md" ]; then cp "$mod/README.md" "$dest/"; fi
  cp -r "$mod/src" "$dest/src"

  commit=$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo unknown)
  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then dirty=true; fi
  python3 -I - "$dest" "$backup/receipt.json" "$stamp" "$commit" "$dirty" "$repo" "$gameBuild" <<'PY'
import datetime, hashlib, json, os, sys
dest, receipt, stamp, commit, dirty, repo, game = sys.argv[1:8]
files = {}
for folder, _, names in os.walk(dest):
    for name in names:
        path = os.path.join(folder, name)
        with open(path, "rb") as f:
            files[os.path.relpath(path, dest).replace(os.sep, "/")] = hashlib.sha256(f.read()).hexdigest()
manifest = json.load(open(os.path.join(dest, "hellforge-mod.json"), encoding="utf-8"))
with open(receipt, "w", encoding="utf-8", newline="\n") as f:
    json.dump({
        "installed_at_utc": datetime.datetime.strptime(stamp, "%Y%m%dT%H%M%SZ").strftime("%Y-%m-%dT%H:%M:%SZ"),
        "mod_id": manifest["id"],
        "version": manifest["version"],
        "game_build": game,
        "source": {"repo": repo, "commit": commit, "tree_dirty": dirty == "true"},
        "destination": dest,
        "files_sha256": dict(sorted(files.items())),
    }, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  echo "Installed $dest"
  echo "Backup and receipt: $backup"
}

case ${1:-} in
  dll) build_dll ;;
  test) run_tests ;;
  wine-test) run_wine_tests ;;
  install) shift; install_mod "$@" ;;
  *) echo "usage: $0 dll | test | wine-test | install <HellForge installation>" >&2; exit 2 ;;
esac
