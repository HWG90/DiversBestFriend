# R35 - Bindings Compatibility

- Fix wheel input and missing cursor compatibility with the updated Vanilla Plus Megapack: accept numeric Mod Bindings Menu interface versions 2 and above while retaining API 1. Invalid or missing versions are safely rejected; saved binding IDs remain unchanged.
- Include R33/R34 native selection, confirmation and page-change sound cues, size presets, independent icon/label sizing, background opacity, grouped settings and the illustrated setup guide. Preserve the restored wheel caption and countdown presentation.
- Retain R31 scrambled-code recovery, all selection layouts and optional Select on Release (off by default). Confirm and release selection share interval validation; pacing is unchanged.

Install `DiversBestFriend-R35-BindingsCompatibility.zip` through Arsenal with the game closed, enable only one revision, deploy and restart. Requires Bingus Shared Loader API 1, Mod Bindings Menu v2.0 or newer with API 1, Mod Options Menu API 1 and supported Steam build 25480438. Existing addon identity, settings and binding IDs are retained.

Package checks and the full isolated LuaJIT regression suite pass, including minimum/current/future bindings versions, invalid versions, API rejection and recovery. This build has not been verified in-game. Check pointer movement, Confirm, optional Select on Release, sound cues, cursor alignment and mode switching. The confirmation sound marks an accepted sequence; normal game feedback confirms beacon equip.

[Changes since previous stable R31](https://github.com/HWG90/DiversBestFriend/compare/r31...r35)
