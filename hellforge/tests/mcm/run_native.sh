#!/usr/bin/env bash
# Run the bridge against the sibling dbf-mcm checkout. All registry storage is in memory.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dbf="$here/../../divers-best-friend/src"
mcm=${1:-"$here/../../../../dbf-mcm/hellforge"}
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
"${CC:-cc}" -std=c11 -Wall -Wextra -Wno-unused-parameter -DDBF_TEST_NATIVE_MCM \
    -I"$dbf" -I"$here/.." -I"$mcm/mcm/src" -I"$mcm/tests" \
    "$here/../test_mcm_bridge.c" "$mcm/tests/mem_fs.c" \
    "$mcm"/mcm/src/{api,registry,schema,prefs,store,queue,json,num}.c \
    "$dbf"/{dbf_mcm,dbf_mcm_schema,hud_options,settings,bindings,admission,logic}.c \
    -I"$here/../../sdk" -lm -pthread -o "$build/test_mcm_bridge"
"$build/test_mcm_bridge"
