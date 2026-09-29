Diver's Best Friend - hd2ui Demo Counter
=========================================

What this is
------------
A demo of hd2ui, a small framework for drawing custom HUD elements in
Helldivers 2 with the engine's own 2-D screen GUI (stingray Gui.triangle /
Gui.text), running on Bingus Shared Loader.

It draws a small counter to the RIGHT of the crosshair: a translucent backing,
a pip bar, and a number. The number is a SYNTHETIC demo value that drains from
45 to 0 every ~18 s and wraps. It is NOT your weapon's ammo. This build exists
to verify that the rendering path (material, triangles, text, scaling, y axis,
colour order, update/shutdown hooks) is correct in a live game.

Display only: no memory writes, no game function calls, no input injection.

Requirements
------------
* Bingus Shared Loader v15+ (API 1) enabled. Keep BSL at the bottom of the
  Arsenal mod list (or reversed with First-Mod Priority), as its README says.

Install
-------
1. Import this zip into Arsenal, enable "Core".
2. Purge, Deploy, launch the game, drop into a mission.
3. Expected: a white number right of the crosshair, ticking down.

Log
---
%APPDATA%\Arrowhead\Helldivers2\hd2ui_demo.log

Look for a line like:
  gui ready mode=geometry resolution=2560x1440
* mode=geometry  -> our solid material loaded; shapes + text should both show.
* mode=text      -> the material did not load; only the number shows. Please
                    report this together with the log.

If nothing shows at all, make sure the log has an "installed" line; if it does
not, BSL did not run the addon (check BSL's own log under
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\).

Uninstall
---------
Disable/remove in Arsenal, Purge, Deploy.
