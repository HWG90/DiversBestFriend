# Install DBF Reforged R50

The current release is **R50-hellforge.11**, with NEST 0.8.2 included.

1. In HellForge’s Mods page, import **divers-best-friend-R50-hellforge.11.zip** directly. Keep the ZIP intact.
2. Enable **DBF Reforged**. The package includes its settings host; no separate NEST import is needed. An active compatible standalone NEST is reused.
3. In the game, press **F7** to open DBF settings. **Page Down** opens NEST’s shared panel list by default. If a customized host assigns F7 to that list, change its list shortcut to free F7 for DBF.

NEST (Native Extension and Settings Toolkit) provides shared panel rendering, input capture and hotkeys, and game-thread scheduling. DBF uses it for settings and diagnostics. DBF draws its wheel, cooldown display and weapon strip on the native game HUD. Future HellForge mods can reuse the active host.

NEST reads FS Sinclair Regular for body text and Medium for headings from your installed game data. The extractor is included in its DLL; the package does not redistribute game fonts or require an installed Editor mod.

This ZIP has one root manifest: `goose.divers-best-friend`, with `divers_best_friend.dll` as its launcher entry point. `goose_overlay.dll`, its API header and ImGui license are ancillary files. The standalone NEST ID remains `goose.overlay-host`.

To update, import this ZIP over the existing DBF mod. Its stable ID prevents a duplicate DBF entry. If standalone NEST 0.8.1 is enabled, disable it in HellForge and restart the game so bundled 0.8.2 supplies the corrected fonts, or update the standalone host to 0.8.2. DBF reports this migration instead of opening its normal editor on the older host. Compatible standalone NEST 0.8.2 installations can remain enabled. DBF keeps preferences in `%LOCALAPPDATA%\DBF\HellForge\settings.ini` in the game’s Windows environment; keep any customized standalone `overlay-host.ini` and `imgui.ini`.

Existing Bingus Shared Loader (BSL) installations can keep running other addons alongside DBF. No BSL version is required. The game memory-build check remains build **25480438**. DBF-MCM is optional.
