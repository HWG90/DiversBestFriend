# HUD+ selection handoff

The adapter recognizes the selection cleanup interface, not a version number. Local, unmodified HUD+ 0.2.8 and 0.2.9 Lua were exercised in isolated LuaJIT fixtures. This does not establish live gameplay or runtime frame cost.

When ASS owns selection, it restores the original list through HUD+ vanilla(false), closes the HUD+ duplicate once, and suppresses HUD+ list/picker rendering. Shared extension arrow observation remains available. Weapon, cooldown, health and other HUD+ features are outside this handoff. When ASS releases ownership, original prepare/observe/put methods and return values resume.

The immediate-picker contract cancels the pending selection. The paced-picker contract also restores the held menu trigger, releases consumed aim, and clears selection timing and remembered selection using HUD+ reset/frame methods. Only instance methods are wrapped. Settings and shared classes are not modified.

## Forward compatibility

A future HUD+ release can change observe/put presentation code without a new adapter entry if its verified lifecycle and picker cleanup contract remain compatible. prepare, vanilla, drop and close are fingerprinted; picker contracts verify reset and, when present, frame and leave, together with their Lua cleanup helpers. Missing interfaces or unfamiliar cleanup implementations are rejected without partial mutation. This is compatibility by interface, not a guarantee for every future release.

If a future release changes cleanup, inspect that source and add a behavior-named picker contract to picker_contracts in native-selection-poc/hud_plus.lua. If the lifecycle changes, introduce a separate reviewed lifecycle contract rather than weakening validation or adding a version-only exception. Exercise that owner's real feature, picker and runtime modules with the fixture below. Do not copy third-party source into a release package.

Discovery scans only changed update wrappers and is bounded to eight scans, 128 closures per scan, 64 upvalues per closure and 16 runtimes. Program and feature identity checks detect recreation without rescanning unchanged closures. An active handoff performs cleanup once per ownership transition. Unknown owners remain untouched.

## Verification

Set HD2_HUD_PLUS_SOURCE to the unmodified product Lua, then run:

    py -3 run_lua.py native-selection-poc/tests/hud_plus_test.lua

Repeat for each target. Fixtures cover disabled/resumed ownership, both update-wrapper orders, callback returns, held-trigger/aim cleanup, changed presentation with stable cleanup, unsupported contracts, program and feature recreation, no duplicate wrapping, 10000 unchanged discovery frames and 10000 active frames without repeated drop.

Before accepting deployment, verify visible list ownership, Confirm, release selection, aiming, close/reopen, disable/re-enable and mission transitions in game. Builds remain review candidates until that evidence exists.

## Inspected artifact identities

HUD+ 0.2.8 original ZIP SHA-256: bcb2c911eadb3a016e12b915709ffba96ffa111723512105c0f9ded899d92a71 (Nexus mod 15298, file 69169).

HUD+ 0.2.9 source came from the local Arsenal library. Its main Lua SHA-256 is 31af81f2942cb6c0a1aae6d4ce83b6d9e86644392082d25037c829fa63c3b34e. Those exact source bytes occur at offset 5171 in patch_0, SHA-256 f6f43e580d3d5ea64c601d921e5e12352accedd332a3a6dd07f5ec0312f56212. Library naming and metadata identify 0.2.9; source/patch agreement was independently checked. No claim about installed game bytes is made.

The earlier compatibility baseline was published R42 tag r42-ui-recovery-test, commit dfc7b209c6e8e496b72d89971b538185235a9c7b. This R45 review work retains recovery, blacklist and selection safeguards and includes the existing worktree changes. New compatibility behavior remains undeployed.

LLL cleanup now restores the exact HUD+ instance methods before a reload, leaving shared classes untouched. If another owner has replaced one of those wrappers, cleanup refuses rather than overwriting it.
