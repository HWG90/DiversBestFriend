#!/usr/bin/env bash
# Fails unless the vendored HellForge mod SDK (hellforge/sdk) is the one this port is built against: HF_MOD_SDK_VERSION 15
# in hellforge_mod.h, SOURCE.md listing exactly the files in the folder, and every file's SHA-256 as SOURCE.md says. A
# header that was edited by hand, replaced by another SDK or left out of SOURCE.md is named and fails the build.
# SOURCE.md lists the files as `sha256sum` writes them (64 hex digits, two spaces, the name), one per line.
# Usage: check_sdk.sh [<sdk folder>]     default: hellforge/sdk beside this script's folder. build.sh dll and build.sh test
# run it on the vendored folder even when HF_SDK points the build somewhere else.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
sdk=${1:-$here/../sdk}
want_version=15
bad=0

fail() { echo "check_sdk: $*" >&2; bad=1; }

[ -d "$sdk" ] || { echo "check_sdk: $sdk is not a folder" >&2; exit 1; }
[ -f "$sdk/SOURCE.md" ] || { echo "check_sdk: $sdk/SOURCE.md is missing (it names the source and each file's SHA-256)" >&2; exit 1; }

# The SDK version the headers declare.
version=
if [ -f "$sdk/hellforge_mod.h" ]; then
  version=$(sed -n 's/^#define HF_MOD_SDK_VERSION[[:space:]][[:space:]]*\([0-9][0-9]*\)\([[:space:]].*\)\{0,1\}$/\1/p' "$sdk/hellforge_mod.h" | head -n 1)
fi
if [ "$version" != "$want_version" ]; then
  fail "hellforge_mod.h declares HF_MOD_SDK_VERSION ${version:-nothing}, this port needs $want_version"
fi

# The files SOURCE.md lists and their hashes.
listed=$(sed -n 's/^\([0-9a-f]\{64\}\)  \([A-Za-z0-9._-][A-Za-z0-9._-]*\)$/\1  \2/p' "$sdk/SOURCE.md")
if [ -z "$listed" ]; then
  fail "SOURCE.md lists no file (expected lines like \`<64 hex digits>  hellforge_mod.h\`)"
fi
while IFS= read -r line; do
  [ -n "$line" ] || continue
  hash=${line%%  *}
  name=${line#*  }
  if [ ! -f "$sdk/$name" ]; then
    fail "SOURCE.md lists $name, which is not in the folder"
    continue
  fi
  actual=$(sha256sum "$sdk/$name" | cut -d' ' -f1)
  if [ "$actual" != "$hash" ]; then
    fail "$name does not match SOURCE.md (SHA-256 $actual, SOURCE.md says $hash)"
  fi
done <<<"$listed"

# Every file of the folder must be listed, SOURCE.md aside, and each file once.
for path in "$sdk"/*; do
  name=${path##*/}
  [ "$name" != SOURCE.md ] || continue
  if ! grep -q "^[0-9a-f]\{64\}  $name\$" <<<"$listed"; then fail "$name is in the folder but SOURCE.md does not list it"; fi
done
dups=$(cut -d' ' -f3 <<<"$listed" | sort | uniq -d)
if [ -n "$dups" ]; then fail "SOURCE.md lists these more than once: $(echo $dups)"; fi
for name in hellforge_mod.h hellforge_lua.h hellforge_content.h hellforge_components.h LICENSE-SDK; do
  if ! grep -q "^[0-9a-f]\{64\}  $name\$" <<<"$listed"; then fail "SOURCE.md does not list $name"; fi
done

if [ "$bad" != 0 ]; then echo "check_sdk: the vendored SDK in $sdk is not the pinned SDK $want_version" >&2; exit 1; fi
echo "check_sdk: ok (SDK $version, $(wc -l <<<"$listed") files match SOURCE.md)"
