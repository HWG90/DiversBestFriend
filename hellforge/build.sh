#!/usr/bin/env bash
# Builds, tests and installs Diver's Best Friend for HellForge (the native C port in hellforge/divers-best-friend).
# Usage: ./build.sh dll                          the mod's DLL, built exactly as HellForge builds a source mod, then its
#                                                import check (tests/check_imports.sh)
#        ./build.sh test                         the Linux unit tests: tests/test_*.c with the portable units of src/
#        ./build.sh wine-test                    the DLL (as dll does), then the real DLL under Proton's Wine: tests/wine_host.c
#                                                loads it with a stand-in HfApi over the synthetic image of tests/synthetic.c,
#                                                once per case, with the stub Overlay Hosts and loader built here
#        ./build.sh install <HellForge installation>
#                                                copies the mod into <installation>/mods/divers-best-friend, after
#                                                backing up what was there into <installation>/backport-backups/<UTC>/
# Zig is the native Linux 0.17.0, HellForge's pinned version (Wine cannot run zig.exe: its cache locking calls NtLockFile
# in a way Wine does not implement). Settings: HF_INSTALL (the HellForge installation the toolchain and SDK come from;
# default HellForge 0.4's Linux install, ~/.local/share/hellforge-prefix/pfx/drive_c/users/steamuser/Documents/HellForge),
# HF_ZIG (default the installation's tools/zig-linux Zig), HF_SDK (the mod SDK headers; default the installation's
# app/sdk), HF_PGREP (the pgrep install asks whether the game or HellForge runs; default pgrep), PROTON (wine-test: default
# Steam's Proton - Experimental; its prefix is build/proton).
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
  # platform layer among them; the Wine host and its stubs, tests/wine_*.c, belong to wine-test).
  for file in "$mod"/src/*.c; do
    case ${file##*/} in dbf.c|platform_win.c) ;; *) sources+=("$file") ;; esac
  done
  for file in "$here"/tests/*.c; do
    case ${file##*/} in test_*.c|wine_*.c) ;; *) helpers+=("$file") ;; esac
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
  build_dll
  local out="$here/build/wine" flags=(-std=c11 -target x86_64-windows-gnu -O1 -Wall -Werror -Wno-unused-parameter)
  mkdir -p "$out"
  # The stand-in HellForge with the synthetic image; the stub Overlay Hosts (one goose_overlay.dll per API version, each
  # in a folder of its own) with the recording OvApi of tests/fake_ov.c; the stub hellforge_modloader.dll.
  "$zig" cc "${flags[@]}" -I "$mod/src" -I "$here/tests" -I "$sdk" "$here/tests/wine_host.c" "$here/tests/synthetic.c" \
      -o "$out/wine_host.exe" || die "The Wine host did not compile."
  local api
  for api in 3 4 5; do
    mkdir -p "$out/overlay-api$api"
    "$zig" cc "${flags[@]}" -shared -DSTUB_API=$api -I "$mod/src" -I "$here/tests" "$here/tests/wine_overlay_stub.c" \
        "$here/tests/fake_ov.c" -o "$out/overlay-api$api/goose_overlay.dll" || die "The API $api stub Overlay Host did not compile."
  done
  mkdir -p "$out/modloader"
  "$zig" cc "${flags[@]}" -shared "$here/tests/wine_modloader_stub.c" -o "$out/modloader/hellforge_modloader.dll" \
      || die "The stub loader did not compile."
  find "$out" -name '*.lib' -delete

  # As the Overlay Host's build.sh --test runs host_test.exe: Proton sets up a prefix (here build/proton; no Steam app
  # ids, so nothing registers with Steam as a game), then each case runs on Proton's own wine, which keeps its output.
  local proton="${PROTON:-$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/proton}"
  [ -x "$proton" ] || die "no Proton at $proton (set PROTON)"
  export STEAM_COMPAT_DATA_PATH="$here/build/proton" STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.local/share/Steam}"
  unset SteamAppId SteamGameId WINEPREFIX
  mkdir -p "$STEAM_COMPAT_DATA_PATH"
  "$proton" run 'C:\windows\system32\cmd.exe' /c exit >/dev/null 2>&1 || true
  w() { printf 'Z:%s' "${1//\//\\}"; }
  # Each case in a process of its own (the DLL keeps static state); its full output is kept in build/wine/<case>.log.
  local passed=0 failed=0 name status stubs
  for name in no-host host-api3 host-api4 host-api5 no-tick; do
    case $name in
      no-host) stubs=() ;;
      no-tick) stubs=("$(w "$out/overlay-api4/goose_overlay.dll")") ;;
      host-api5) stubs=("$(w "$out/overlay-api5/goose_overlay.dll")" "$(w "$out/modloader/hellforge_modloader.dll")") ;;
      *) stubs=("$(w "$out/overlay-api${name#host-api}/goose_overlay.dll")") ;;
    esac
    status=0
    WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx" WINEDEBUG=-all timeout 300 "$(dirname "$proton")/files/bin/wine" \
        "$(w "$out/wine_host.exe")" "$(w "$mod/$dllName")" "$name" ${stubs[@]+"${stubs[@]}"} > "$out/$name.log" 2>&1 || status=$?
    sed -i 's/\r$//' "$out/$name.log" # a Windows program's text-mode stdout ends its lines with CR LF
    grep -E '^(==|PASS|FAIL)' "$out/$name.log" || true
    # A case passes when the host exits 0 and printed its last line (a crash in the DLL never gets there).
    if [ "$status" = 0 ] && grep -qx "== $name: 0 failure(s)" "$out/$name.log"; then echo "PASS $name"; passed=$((passed + 1))
    else echo "FAIL $name (exit $status; log $out/$name.log)"; failed=$((failed + 1)); fi
  done
  echo "wine-test: $passed passed, $failed failed"
  [ "$failed" -eq 0 ]
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
