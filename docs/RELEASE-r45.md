# R45 - Plays Nicely With Others

HUD Plus moves the stratagem display, custom stratagems use their own codes,
and single-use stratagems need to stay unavailable after use. R45 handles all
three, including the Foliage Pass-Through conflict that stopped some custom
barrages and launchers from working.

## Changes

- **HUD Plus 0.2.8:** its competing stratagem list and picker yield while ASS
  controls selection. Other HUD Plus features remain active. HUD Plus resumes
  its own list behavior when ASS is disabled or recovering.
- **Custom Stratagem Compendium 0.4.1 / HD2Runtime 0.40.0:** Confirm and Select
  on Release accept custom call-in codes from recognized Runtime-owned arrays.
  Ownership, contents and the required sequence are rechecked during input.
- **Single-use availability:** exhausted entries such as Shredder dim on the
  native and expanded wheels. Unavailable entries cannot Confirm or arm Select
  on Release; becoming unavailable after arming cancels release selection.
- **Foliage Pass-Through 1.0:** recognize its exact projectile collision-template
  change so HD2Runtime can validate custom gas-barrage and cluster-launcher
  donors. Every other donor byte remains checked; unrelated changes are refused.
- Includes R42's bounded recovery for recognized transient HUD failures. Close
  and reopen the stratagem menu to recover. Pending input is cancelled, camera
  control is restored and held inputs are not replayed. Fatal guards remain.

These compatibility mods are optional. ASS still works without them. Foliage
Pass-Through can be on or off. Restart after changing it so the game starts with
consistent projectile data. Required selection/menu dependencies remain listed
below; optional compatibility does not remove those requirements.

## Choose one download

| Package | Installation |
| --- | --- |
| `DiversBestFriend-R45-BSL.zip` | Import into Arsenal and deploy with Bingus Shared Loader. |
| `DiversBestFriend-R45-MDL.zip` | Extract `divers_best_friend` into `%LOCALAPPDATA%/MDL/Helldivers2/Mods`; MDL API 2. |
| `DiversBestFriend-R45-LLL.zip` | Extract `divers_best_friend` into `%LOCALAPPDATA%/LLL/Helldivers2/Mods`; LLL R30+. |

Install **one ASS revision and one loader variant**. Close the game before
replacing files, disable/remove the old archive provider when switching to a
loose package, and restart. ASS retains its startup/UI owners until game exit;
hot-reload and live provider switching are not supported. Begin a fresh mission
for custom stratagems: Runtime does not retry slots it already refused.

All variants require Mod Bindings Menu v2+ / API 1 and Mod Options Menu through
the chosen loader's shared-addon compatibility route. They are not bundled.
MCM is optional for additional blacklist entries. Existing addon identity,
binding IDs and saved options are retained. Supported Windows/Steam build:
25480438 (game.dll timestamp 1790161983).

## Validation

- The R42 compatibility predecessor was tested on LLL in-game. HUD Plus layout
  coexistence was captured; Shredder's unavailable-state fix was confirmed and
  the final combination was reported working after restart. This is user-reported
  gameplay acceptance, not an individually recorded test of every custom family.
- All eleven Compendium call-in codes pass isolated Confirm and Select on
  Release tests using the shipped Runtime owner. HUD Plus tests use the actual
  0.2.8 feature and update wrappers. Recovery, blacklist, ownership, mutation,
  timer and selection regression tests pass.
- Live read-only tests on copied schemas found 14 exact foliage variants. The
  original Runtime gas/cluster guards failed before registration and passed
  afterward. Unrelated byte changes still failed. Registration measured about
  1-2 ms CPU once; 10,000 idle fixture updates made no further memory reads.
- R45 BSL/MDL/LLL packages share the same core. BSL package checks and MDL API 2
  startup/duplicate/retained-cleanup tests are isolated; the MDL adapter has not
  been gameplay-tested. Revision relabeling does not add new live proof.

See [installation and controls](https://github.com/HWG90/DiversBestFriend/blob/r45/docs/INSTALLATION.md), [HUD Plus compatibility](https://github.com/HWG90/DiversBestFriend/blob/r45/native-selection-poc/HUD-PLUS-COMPATIBILITY.md)
and [custom stratagem details](https://github.com/HWG90/DiversBestFriend/blob/r45/native-selection-poc/CUSTOM-STRATAGEM-COMPATIBILITY.md).
