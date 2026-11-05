#!/usr/bin/env bash
# Usage: check_hud_discovery.sh PACKAGE.zip [HF-LLL source checkout] [expected addon name]
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
package=${1:?expected HellForge mod zip}
loader=${2:-"$here/../../../HF-LLL"}
patch=9ba626afa44a3aa3.patch_0
unzip -p "$package" "data/$patch" |
  luajit "$here/check_hud_discovery.lua" "$loader" "$patch" "${@:3}"
