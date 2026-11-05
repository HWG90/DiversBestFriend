#!/usr/bin/env bash
# Builds, tests and installs Diver's Best Friend for HellForge (the native C port in hellforge/divers-best-friend).
# Usage: ./build.sh dll                          the mod's DLL, built exactly as HellForge builds a source mod, after the check
#                                                of the vendored SDK (tests/check_sdk.sh), then its import check
#                                                (tests/check_imports.sh)
#        ./build.sh test                         the SDK check, the Linux unit tests (tests/test_*.c with the portable units
#                                                of src/) and the Python tests (tools/test_*.py)
#        ./build.sh test-c                       Linux C tests only (no Lua inputs or Python packaging tests)
#        ./build.sh package [zip]                rebuild the DLL and write the combined root-manifest HellForge zip
#        ./build.sh verify-package [zip]         compare every zip member against the DLL, sources and rebuilt archive
#        ./build.sh verify-stage [zip]           test launcher import, DLL plan, patch staging and HF-LLL discovery in a scratch root
#                                                (uses HF_INSTALL, HF_LLL_ROOT or adjacent HF-LLL, and luajit)
#        ./build.sh wine-test                    the DLL (as dll does), then the real DLL under Proton's Wine: tests/wine_host.c
#                                                loads it with a stand-in HfApi over the synthetic image of tests/synthetic.c,
#                                                once per case, with the stub Overlay Hosts and loader built here and a stub
#                                                at each game function DBF calls (the code-entry cases press keys in a window
#                                                of the host's own); then the real BindPort of src/platform_win.c
#                                                (tests/wine_bind.c) in a program of its own
#        ./build.sh install <HellForge installation>
#                                                copies the mod into <installation>/mods/divers-best-friend, after
#                                                backing up what was there into <installation>/backport-backups/<UTC>/
# Zig is the native Linux 0.17.0, HellForge's pinned version (Wine cannot run zig.exe: its cache locking calls NtLockFile
# in a way Wine does not implement). The mod is built against the SDK vendored in hellforge/sdk (SDK 15; SOURCE.md names
# its source and each file's SHA-256), so a HellForge update changes nothing here until the copy is replaced on purpose.
# Settings: HF_INSTALL (the HellForge installation the Zig toolchain comes from; default HellForge 0.4's Linux install,
# ~/.local/share/hellforge-prefix/pfx/drive_c/users/steamuser/Documents/HellForge), HF_ZIG (default the installation's
# tools/zig-linux Zig), HF_SDK (the mod SDK headers; default hellforge/sdk. The vendored copy is checked whatever HF_SDK
# says, and an install receipt records the SHA-256 of the headers that were used), HF_PGREP (the pgrep install asks
# whether the game or HellForge runs; default pgrep), PROTON (wine-test: default Steam's Proton - Experimental; its prefix
# is build/proton).
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo="$(dirname "$here")"
mod="$here/divers-best-friend"
dllName=divers_best_friend.dll
gameBuild=25480438
hf="${HF_INSTALL:-$HOME/.local/share/hellforge-prefix/pfx/drive_c/users/steamuser/Documents/HellForge}"
zig="${HF_ZIG:-$hf/tools/zig-linux/zig}"
vendored_sdk="$here/sdk"
sdk="${HF_SDK:-$vendored_sdk}"
export ZIG_GLOBAL_CACHE_DIR="$here/build/zig-cache" ZIG_LOCAL_CACHE_DIR="$here/build/zig-cache"

die() { echo "$*" >&2; exit 1; }
toolchain() {
  [ -x "$zig" ] && [ "$("$zig" version)" = 0.17.0 ] || die "no Zig 0.17.0 at $zig (set HF_ZIG)"
  "$here/tests/check_sdk.sh" "$vendored_sdk" || die "The vendored SDK in hellforge/sdk is not the pinned one."
  [ -f "$sdk/hellforge_mod.h" ] || die "no mod SDK at $sdk (set HF_SDK)"
  if [ "$sdk" != "$vendored_sdk" ]; then echo "note: HF_SDK builds against $sdk, not the vendored SDK in hellforge/sdk"; fi
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

# The Python tests of tools/ (tools/test_*.py, as the repository's root runs them), with the vendored SDK for the ones that
# read it. A skipped test is fine; its reason is printed. Prints PASS or FAIL for the whole suite; fails when it does.
run_python_tests() {
  command -v python3 >/dev/null 2>&1 || { echo "FAIL python tests (no python3)"; return 1; }
  local out status=0
  out=$(cd "$repo" && HF_SDK="$sdk" HF_ZIG="$zig" python3 -I -m unittest discover -v -s hellforge/tools -p 'test_*.py' 2>&1) || status=$?
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$out"
    echo "FAIL python tests (exit $status)"
    return 1
  fi
  printf '%s\n' "$out" | sed -n 's/.* \.\.\. skipped //p' | sort | uniq -c | while read -r count reason; do
    echo "  $count python test(s) skipped: $reason"
  done
  echo "PASS python tests ($(printf '%s\n' "$out" | grep -E '^(Ran [0-9]+ tests?|OK)' | tr '\n' ' ' | sed 's/ *$//'))"
}

run_tests() {
  shopt -s nullglob
  local tests=("$here"/tests/test_*.c) sources=() helpers=() file
  shopt -u nullglob
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
  if [ ${#tests[@]} -eq 0 ]; then echo "no C tests yet (tests/test_*.c)"; fi
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
  if [[ ${1:-} != c-only ]]; then
    if run_python_tests; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
  fi
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
  for api in 3 4 5 8; do
    mkdir -p "$out/overlay-api$api"
    "$zig" cc "${flags[@]}" -shared -DSTUB_API=$api -I "$mod/src" -I "$here/tests" "$here/tests/wine_overlay_stub.c" \
        "$here/tests/fake_ov.c" -o "$out/overlay-api$api/goose_overlay.dll" || die "The API $api stub Overlay Host did not compile."
  done
  mkdir -p "$out/modloader"
  # The stub is compiled against the SDK's own declaration of hellforge_lua_rewrites, with HF_LUA_API as the loader's
  # dllexport, so the compiler checks the prototype the stub defines.
  "$zig" cc "${flags[@]}" -shared "-DHF_LUA_API=__declspec(dllexport)" -I "$sdk" "$here/tests/wine_modloader_stub.c" \
      -o "$out/modloader/hellforge_modloader.dll" || die "The stub loader did not compile."
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
  local passed=0 failed=0 skipped=0 name status stubs
  # The code-entry cases (Plan 2, Task 12) drive the real DLL end to end: a stub at each game function, settings.ini,
  # keys pressed in a window of the host's own; use the API 8 stub host and the stub loader (old-host-input with API 5, no-host-entry with
  # the loader alone).
  for name in no-host host-api3 host-api4 host-api5 no-tick retry on-at-once late-module second-loaded null-panel on-fails \
              masked-log list-confirm instant menu-close mission-end shortcut shortcut-hud mod-stratagem scramble \
              no-entry-admission old-host-input no-host-entry release-retry card-gone shortcut-blocked latch-retry; do
    case $name in
      no-host) stubs=() ;;
      host-api5|old-host-input) stubs=("$(w "$out/overlay-api5/goose_overlay.dll")" "$(w "$out/modloader/hellforge_modloader.dll")") ;;
      list-confirm|instant|menu-close|mission-end|shortcut|shortcut-hud|mod-stratagem|scramble|no-entry-admission|\
      release-retry|card-gone|latch-retry|shortcut-blocked)
        stubs=("$(w "$out/overlay-api8/goose_overlay.dll")" "$(w "$out/modloader/hellforge_modloader.dll")") ;;
      no-host-entry) stubs=("$(w "$out/modloader/hellforge_modloader.dll")") ;;
      masked-log) stubs=("$(w "$out/overlay-api4/goose_overlay.dll")" "$(w "$out/modloader/hellforge_modloader.dll")") ;;
      host-api3|host-api4) stubs=("$(w "$out/overlay-api${name#host-api}/goose_overlay.dll")") ;;
      *) stubs=("$(w "$out/overlay-api4/goose_overlay.dll")") ;; # the cases of the API 4 stub alone
    esac
    status=0
    WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx" WINEDEBUG=-all timeout 300 "$(dirname "$proton")/files/bin/wine" \
        "$(w "$out/wine_host.exe")" "$(w "$mod/$dllName")" "$name" ${stubs[@]+"${stubs[@]}"} > "$out/$name.log" 2>&1 || status=$?
    sed -i 's/\r$//' "$out/$name.log" # a Windows program's text-mode stdout ends its lines with CR LF
    grep -E '^(==|PASS|FAIL|SKIP)' "$out/$name.log" || true
    # A case passes when the host exits 0 and printed its last line (a crash in the DLL never gets there). A code-entry
    # case that finds no desktop where its window can take the foreground and keys reach the key state is skipped.
    if [ "$status" = 0 ] && grep -qx "== $name: 0 failure(s)" "$out/$name.log"; then echo "PASS $name"; passed=$((passed + 1))
    elif [ "$status" = 0 ] && grep -qx "== $name: skipped" "$out/$name.log"; then
      echo "SKIP $name (no focusable desktop for its keys; log $out/$name.log)"; skipped=$((skipped + 1))
    else echo "FAIL $name (exit $status; log $out/$name.log)"; failed=$((failed + 1)); fi
  done
  # The real BindPort (src/platform_win.c) in a program of its own: it needs no game and no stub host, so it runs once,
  # after the cases.
  "$zig" cc "${flags[@]}" -I "$mod/src" -I "$here/tests" -I "$sdk" "$here/tests/wine_bind.c" "$mod/src/platform_win.c" \
      -o "$out/wine_bind.exe" || die "The BindPort probe did not compile."
  status=0
  WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx" WINEDEBUG=-all timeout 300 "$(dirname "$proton")/files/bin/wine" \
      "$(w "$out/wine_bind.exe")" > "$out/bind-port.log" 2>&1 || status=$?
  sed -i 's/\r$//' "$out/bind-port.log"
  grep -E '^(==|PASS|FAIL|SKIP)' "$out/bind-port.log" || true
  if [ "$status" = 0 ] && grep -qx "== bind-port: 0 failure(s)" "$out/bind-port.log"; then echo "PASS bind-port"; passed=$((passed + 1))
  else echo "FAIL bind-port (exit $status; log $out/bind-port.log)"; failed=$((failed + 1)); fi
  if [ "$skipped" -gt 0 ]; then echo "wine-test: $passed passed, $failed failed, $skipped skipped"
  else echo "wine-test: $passed passed, $failed failed"; fi
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
  if [ -n "$(find "$mod/src" "$mod/hellforge-mod.json" "$sdk" -newer "$mod/$dllName" -print -quit)" ]; then
    die "The sources, the manifest or the SDK headers are newer than $dllName (./build.sh dll)."
  fi
  "$here/tests/check_imports.sh" "$mod/$dllName" >/dev/null || die "$dllName fails its import check (./build.sh dll shows why)."
  # The receipt records the SDK headers by hash: they must be the pinned ones (or, with HF_SDK, at least be there).
  "$here/tests/check_sdk.sh" "$vendored_sdk" >/dev/null || die "The vendored SDK in hellforge/sdk is not the pinned one (tests/check_sdk.sh shows why)."
  for header in hellforge_mod.h hellforge_lua.h hellforge_content.h hellforge_components.h; do
    [ -f "$sdk/$header" ] || die "no $header in $sdk (set HF_SDK)."
  done

  # Serialize competing installs through this script, even when UTC seconds differ.
  local lock_fd
  exec {lock_fd}<"$install/mods"
  flock --nonblock "$lock_fd" || die "Another mod install is in progress."
  local stamp backup dest="$install/mods/divers-best-friend" commit dirty=false
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  backup="$install/backport-backups/$stamp"
  mkdir -p "$install/backport-backups"
  mkdir "$backup" || die "$backup already exists."
  # Build and verify the whole import before moving the installed mod. Stage on the same
  # filesystem as dest so activation and rollback are directory renames.
  local staged
  staged=$(mktemp -d -- "$install/mods/.dbf-install.XXXXXXXX")
  trap 'rm -rf -- "$staged"' EXIT
  python3 -I "$here/tools/hud_pack.py" package "$staged/mod.zip"
  mkdir "$staged/new"
  unzip -q "$staged/mod.zip" -d "$staged/new"
  if [ -f "$install/mods/hellforge-mods.json" ]; then cp -a "$install/mods/hellforge-mods.json" "$backup/"; fi

  commit=$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo unknown)
  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then dirty=true; fi
  # The receipt records the SDK headers the DLL was built against: their version and each header's SHA-256 (the vendored
  # ones unless HF_SDK points elsewhere, which "vendored" says).
  python3 -I - "$dest" "$staged/receipt.json" "$stamp" "$commit" "$dirty" "$repo" "$gameBuild" "$sdk" \
      "$([ "$sdk" = "$vendored_sdk" ] && echo true || echo false)" "$staged/new" <<'PY'
import datetime, hashlib, json, os, re, sys
dest, receipt, stamp, commit, dirty, repo, game, sdk, vendored, staged = sys.argv[1:]
HEADERS = ("hellforge_mod.h", "hellforge_lua.h", "hellforge_content.h", "hellforge_components.h")
sdk_headers = {}
for name in HEADERS:
    with open(os.path.join(sdk, name), "rb") as f:
        sdk_headers[name] = hashlib.sha256(f.read()).hexdigest()
with open(os.path.join(sdk, "hellforge_mod.h"), encoding="utf-8") as f:
    sdk_version = int(re.search(r"^#define HF_MOD_SDK_VERSION\s+(\d+)", f.read(), re.M).group(1))
files = {}
for folder, _, names in os.walk(staged):
    for name in names:
        path = os.path.join(folder, name)
        with open(path, "rb") as f:
            files[os.path.relpath(path, staged).replace(os.sep, "/")] = hashlib.sha256(f.read()).hexdigest()
manifest = json.load(open(os.path.join(staged, "hellforge-mod.json"), encoding="utf-8"))
with open(receipt, "w", encoding="utf-8", newline="\n") as f:
    json.dump({
        "installed_at_utc": datetime.datetime.strptime(stamp, "%Y%m%dT%H%M%SZ").strftime("%Y-%m-%dT%H:%M:%SZ"),
        "mod_id": manifest["id"],
        "version": manifest["version"],
        "game_build": game,
        "source": {"repo": repo, "commit": commit, "tree_dirty": dirty == "true"},
        "destination": dest,
        "sdk": {"hf_mod_sdk_version": sdk_version, "vendored": vendored == "true", "headers_sha256": sdk_headers},
        "files_sha256": dict(sorted(files.items())),
    }, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  if [ -e "$dest" ]; then mv -- "$dest" "$backup/previous"; fi
  if ! mv -- "$staged/new" "$dest"; then
    if [ -e "$backup/previous" ]; then mv -- "$backup/previous" "$dest"; fi
    die "Could not activate the staged mod."
  fi
  mv -- "$staged/receipt.json" "$backup/receipt.json"
  rm -rf -- "$staged"
  trap - EXIT
  echo "Installed $dest"
  echo "Backup and receipt: $backup"
}

case ${1:-} in
  dll) build_dll ;;
  test) run_tests ;;
  test-c) run_tests c-only ;;
  package) shift; build_dll; python3 -I "$here/tools/hud_pack.py" package "$@" ;;
  verify-package) shift; python3 -I "$here/tools/hud_pack.py" verify "$@" ;;
  verify-stage)
    shift
    package=$(python3 -I "$here/tools/hud_pack.py" verify "$@")
    python3 "$here/tools/check_hud_pack_stage.py" "$package" "$hf" "${HF_LLL_ROOT:-$repo/../HF-LLL}" ;;
  wine-test) run_wine_tests ;;
  install) shift; install_mod "$@" ;;
  *) echo "usage: $0 dll | test | test-c | package [zip] | verify-package [zip] | verify-stage [zip] | wine-test | install <HellForge installation>" >&2; exit 2 ;;
esac
