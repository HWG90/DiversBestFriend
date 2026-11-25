# Publication: DBF Reforged R50-hellforge.19 (2026-11-25)

Public release for HellForge 0.5. It replaces R50-hellforge.11 as the public build. Published from the DBF release session on
the user's words "Push to git and update all release locations, including the discord post on Hellforge", then "Dock OK,
publish all" after they had seen the drafts and the dock in game.

## Decisions

- Re-versioned from `R50-hellforge.19-preview` to plain `R50-hellforge.19` (user chose "Re-version to .19").
- Published after the in-game dock check (user chose "Check in game first", then reported "Dock OK").

## Source and package

- Release commit `2ce6cb1` on `hellforge` ("Version R50-hellforge.19 for release"): version strings, READMEs, install notes,
  changelog entry. On top of `ca9cdf6` (the .19-preview: `ffea037` HellForge 0.5 keys and projectile list, `8c2f34d` dock
  labels). Pushed to origin/hellforge (`1b164b9..2ce6cb1`). Tag `r50-hellforge.19` (lightweight, as .9-.11) on `2ce6cb1`.
- `divers-best-friend-R50-hellforge.19.zip`, 1,246,555 bytes, SHA-256
  `a17fbc1ffd3191727215e1a2bfd431fae0ddbed67e2e0322f2d6e69d263b9354`; DLL
  `72b6f4a1a24d99fc054c2a6fd0f479a471707c996194dc9aeb649311e2703630`; 75 members, no machine paths.
- Against the in-game-checked .19-preview (`f30d9dc1…`): the zip differs only in `hellforge-mod.json` (version),
  `src/dbf.c` (the `DBF_VERSION` line), `README.md` and `INSTALL.md`. The README also stopped saying F9 applies settings
  (Tab has since 566ddf9). A first .19 build (`55de966a…`, same DLL, README still said F9) was installed for a minute and
  superseded; it is kept in the install backup below.

## Checks

- `hellforge/build.sh test` with `DBF_R46_DIR` (R46 reference on /mnt/Windows): 25 passed, 0 failed; Python 61 tests OK,
  3 skipped (BSL/target install, mapped game image, `DBF_WEAPON_IMAGE`).
- `DBF_WINE_CASES="host-api5 masked-log moved-keys retry" hellforge/build.sh wine-test`: 4 passed. The code-entry Wine
  cases (desktop focus and keys) were not run.
- `hellforge/build.sh verify-package`: passed.
- Live install: zip swapped into `<HellForge>/mods/` at 16:15Z/16:16Z via `.part`; .19-preview moved to
  `backport-backups/20261125T161509Z-dbf-19-release/` with `receipt.json`. `HellForge.Cli mods` lists R50-hellforge.19,
  enabled, no problems; unpacked DLL `72b6f4a1…`.
- In game: the session started 16:23Z logged `DBF Reforged R50-hellforge.19 (game 25480438)` and a dock geometry line at
  17:04Z. The user reported the dock correct ("Dock OK"). Codes and entry on HellForge 0.5 were confirmed earlier on .18,
  which has the same reading code.

## Locations

| Where | What | Check |
| --- | --- | --- |
| GitHub HWG90/DiversBestFriend | Release `r50-hellforge.19` "DBF Reforged R50 — HellForge .19", Latest, asset the zip; notes in `build/release-19/github-notes.md` (untracked) | Asset re-downloaded, SHA-256 matches; `releases/latest` = r50-hellforge.19; .11 no longer Latest |
| Ayaka mods/5899 | Update 9565 "DBF Reforged R50 .19 — works on HellForge 0.5", version R50-hellforge.19 (version id 10663, uploaded file); overview: HellForge 0.5, .19 zip name, "Q and E switch views, and Tab applies your changes" (was F9) | Hosted file fetched and hashed: matches; 6 description images kept |
| Nexus mods/17564 "(HELLFORGE) DBF Reforged" | Main file "DBF Reforged R50 - HellForge (NEST included)" updated to R50-hellforge.19 (file id 74992, .11 archived), mod version R50-hellforge.19, changelog entry; description: HellForge 0.5, .19 zip name, and "Q and E switch views. Review changes and apply with Tab." (was F9; same fix as Ayaka, not in the draft) | Uploaded from the same zip path; Nexus virus scan still in progress at 18:35Z, so the file was not downloadable yet and not hashed |
| HellForge Official Discord, #mod-showcase thread 1568086229767950486 | Starter edited: "Made for HellForge 0.5", "Current public release: R50-hellforge.19 — works on HellForge 0.5", GitHub link to .19, "the settings menu"; title unchanged. Reply 1575217674135543868 (18:32Z) announcing .19 with GitHub/Ayaka/Nexus links | Editor text compared to the approved edit before saving; rendered post re-read |

Nexus 17564 is the HellForge listing now (its R46 BSL/LLL/MDL files remain), not only the older LLL line.

## Not done / open

- Nexus virus scan for file 74992 was pending; the file becomes downloadable when it clears. The mod page already showed
  "Virus scan: Some suspicious files" at 18:31Z; whether that predates this upload was not checked.
- Player reports in the Discord thread that this release does not address: DualSense controller, sticks and wheel options
  (2026-11-09) and an instant crash on F7 (2026-11-11/12).
- The blur probe (file-controlled, off by default) still ships in the DLL.
