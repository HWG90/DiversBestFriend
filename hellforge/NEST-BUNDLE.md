# Install Diver’s Best Friend with NEST

1. Extract the downloaded bundle ZIP to a temporary folder. Inside are two mod ZIPs and this guide.
2. In HellForge’s Mods page, import the **NEST** ZIP, then the **divers-best-friend** ZIP. Leave both inner ZIPs intact. If you already use the bundled NEST version or a newer compatible version, import just DBF. Earlier Goose Overlay Host releases use the same mod ID. If you have a customized unpacked host, use the upgrade instructions below.
3. Enable **NEST** and **Diver’s Best Friend**. DBF starts its HUD from its own DLL. If you use Bingus Shared Loader (BSL) for other addons on this game build, keep it enabled. DBF and BSL can run together. DBF-MCM is optional.
4. In the game, press **F7** to open DBF settings. **Page Down** opens NEST’s shared panel list by default.

NEST (Native Extension and Settings Toolkit) provides shared panel rendering, input capture and hotkeys, and game-thread scheduling. DBF uses it for its settings and diagnostics. DBF draws its wheel, cooldown display and weapon strip on the native game HUD. Future HellForge mods can register their own panels and reuse the same installed copy of NEST.

| HellForge mod ID | Binary |
| --- | --- |
| `goose.divers-best-friend` | `divers_best_friend.dll` |
| `goose.overlay-host` | `goose_overlay.dll` |

HellForge imports one mod per archive. Importing each inner ZIP gives both mods their own launcher entry and lets them update independently. To update an earlier HellForge DBF, import the new DBF ZIP over the same mod ID. DBF keeps preferences in `%LOCALAPPDATA%\DBF\HellForge\settings.ini` in the game’s Windows environment.

### Upgrading an unpacked Goose Overlay Host

If your existing host folder contains a customized `overlay-host.ini` or `imgui.ini`, close the game and back up those two files. Extract the four files from the inner NEST ZIP **directly beside the existing host manifest**, replacing the shipped files. This keeps your hotkeys and window positions in place. Then import just the DBF ZIP. If your custom list hotkey is F7, move it to Page Down to free F7 for DBF.
