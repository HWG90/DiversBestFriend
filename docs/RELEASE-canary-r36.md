# Canary R36 - Blacklist

- Add a persistent **Blacklist / Hide SOS Beacon** toggle and **eight additional stratagem ID exclusion slots** to the existing settings menu. Nothing is excluded by default; `0` clears an extra slot. Settings follow native stratagem IDs and remain stable across loadout changes. The ZIP includes `docs/BLACKLIST.md` with the ID reference.
- Apply exclusions before navigation and layout in **Native wheel**, **Keybindings list**, **Experimental Cards**, and **Expanded wedges**. Excluded copied cards are hidden; DBF list mode temporarily hides excluded stock rows and restores their scale on close, disable or mode changes. Vanilla availability and manual stratagem input remain unchanged.
- Cancel queued/armed DBF input when exclusions change. Close and reopen the stratagem menu before using Select on Release after an edit. Empty filtered lists clear selection and release camera capture; reused card addresses cannot immediately confirm a different kind.
- Retain R35's Mod Bindings Menu compatibility fix and the existing appearance, sound, pacing and optional Select on Release features. Stable/main remains R35.

Install `DiversBestFriendCanary-R36-Blacklist.zip` through Arsenal with the game closed, enable only one DBF revision, deploy and restart. Stable and canary share the same addon identity, settings and bindings. Requires the existing dependencies and supported Steam build 25480438.

Package checks and the full isolated LuaJIT suite pass, including blacklist defaults/persistence, all four layouts, loadout changes, empty lists, copied-card visibility, stock-row restoration, input cancellation and Select on Release recovery. **In-game verification remains pending.** Check SOS exclusion and restoration, an extra ID, restart persistence, all layouts and an all-excluded list before relying on this prerelease.

[Changes since stable R35](https://github.com/HWG90/DiversBestFriend/compare/r35...canary-r36)
