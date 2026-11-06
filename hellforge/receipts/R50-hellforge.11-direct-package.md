# DBF Reforged R50-hellforge.11 direct-import candidate

Built 2026-11-05 from the DBF bootstrap commit `8f7f8fe`, including
`src/nest_bootstrap_win.c`, with NEST commit `4cd4bd0` (0.8.2).
Packaging commits: `96c33fa`, `e7cbd3c`.

Artifact: `divers-best-friend-R50-hellforge.11.zip`.
Immutable copy lives under `build/exports/<ZIP SHA256>/`.

| Component | SHA256 |
| --- | --- |
| Direct ZIP | `30d8041303939e3f37fea64658aafd3a980f50145cf484eb6e944d28fca87af4` |
| DBF DLL | `beefb554831633b2d96843a5f2aa0b01c16f4ce1fc0cb08dc6a64adaac9fa6ec` |
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

Six production bootstrap cases passed against these exact DLL digests: bundled
alone, active 0.8.2 reuse without loading the bundle, later distinct-path 0.8.2
sharing, 0.8.1 migration without loading the bundle, and deferral for both pending
and listed-but-inactive standalone hosts. Logs: `/tmp/dbf-nest-production11-final/*.log`.
The runtime owner reports the prior Wine suite passed 29/30 with a foreground-loss
scramble failure; scramble and API4 compatibility were rerun successfully against
the final DLL in an isolated headless session. Those final logs were read and
confirmed to report zero failures. No blanket claim of a clean single-run 30/30
final Wine suite is made.
Native Windows CI and publication belong to Main. No live game installation,
mission acceptance or native Windows visual acceptance was performed here.
All earlier nested-bundle artifacts and pre-guard direct ZIP hash 73640d76 are superseded.
