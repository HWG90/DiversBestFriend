# DBF Reforged R50-hellforge.11 direct-import candidate

Built 2026-11-05 from the current DBF bootstrap source, including
`src/nest_bootstrap_win.c`, with NEST commit `4cd4bd0` (0.8.2).
Packaging commits: `96c33fa`, `e7cbd3c`.

Artifact: `divers-best-friend-R50-hellforge.11.zip`.
Immutable copy lives under `build/exports/<ZIP SHA256>/`.

| Component | SHA256 |
| --- | --- |
| Direct ZIP | `73640d764eca072748e08631ab941f25615a413bcacf8a8d9cdccae7ff540891` |
| DBF DLL | `881d0899f33e177f2f8c95b494cc36e79cd4a939b4ba4f94a5bec32e691e80a3` |
| Included NEST DLL | `ec20c2c31f9f803cb53f92517a5e177c1f2c48272cd8eb389810eb1243da47e8` |
| NEST input ZIP | `564f658308283a8f08fda6e8bf20908ddffb70903d5ce2afa29d5f2252afa20a` |

Verified 75 members, exactly one root `hellforge-mod.json`, zero inner ZIPs,
zero font assets. Manifest ID remains `goose.divers-best-friend`, name is
DBF Reforged, version R50-hellforge.11, entry point `divers_best_friend.dll`.
Bundled `goose_overlay.dll`, `goose_overlay.h` and `imgui-LICENSE.txt` exactly
match the NEST input. Bootstrap source matches the build tree, and the compiled
DLL contains its bundled-host connection message. Full package/source comparison passed.

## Executed packaging and integration checks

- 25 portable test groups passed, including 58 Python tests with real Lua,
  mapped-image and BSL inputs.
- HellForge CLI 0.4.0-beta / d8a8b46 imported the direct ZIP and reimported it
  without duplicate DBF entries. Separate scratch lanes passed with no standalone
  NEST, standalone 0.8.2, and standalone 0.8.1. Both ancillary and standalone
  DLLs were compared byte-for-byte. No game patches staged.
- R50-hellforge.10 to .11 update replaced the stable DBF ID, retained all bundled
  host files, and left one DBF launcher entry and zero archive patches.
- The staged production DBF DLL passed two real game-VM lifetimes and six chained
  updates. This isolated HUD fixture intentionally omits the companion host;
  it verifies private HUD ownership, not bundled-host startup.
- BSL coexistence exercised the staged production DLL with a separate registered
  addon and preserved loader data. Fixture versions/digests are provenance only,
  not a user-facing BSL version requirement. Game memory target remains 25480438.
- NEST owner reports ASAN/UBSAN, six Wine rendering modes, both distinct-path
  shared-host load orders and clean local font extraction passing. See host
  `test/NEST-0.8.2-font-receipt.md` and `test/NEST-0.8.2-coexist-receipt.md`.
  Regular body/Medium headings come from installed game data; no Editor folder
  or font redistribution is needed.

Pasteur reports five production bootstrap cases passing against the exact DLL
digests above: bundled alone, active 0.8.2 reuse without loading the bundle,
later distinct-path 0.8.2 sharing, 0.8.1 migration without loading the bundle, and
deferral for an unresolved planned standalone host. Logs: `/tmp/dbf-nest-production11/*.log`.
The original Wine API4 compatibility suite is still running; earlier pre-bootstrap
Wine results are not substituted for that final regression.
Native Windows CI and publication belong to Main. No live game installation,
mission acceptance or native Windows visual acceptance was performed here.
All earlier nested-bundle artifacts and hashes are superseded.
