# Diver's Best Friend for HellForge

This build targets Helldivers 2 build 25480438 on HellForge 0.4. Import the entire DBF ZIP in HellForge and enable DBF, HF-LLL and Goose Overlay Host. The ZIP contains the native input DLL and the companion archive that draws inside the game HUD.

Use the DBF settings window to choose the wedge wheel, native wheel or list, adjust the wheel and icon sizes, choose the cooldown layout, and toggle the weapon strip. The strip reflects the changeable controls on the equipped weapon. Open diagnostics in the overlay to inspect build admission and input ownership.

## In-mission verification

* Open the stratagem menu with keyboard and controller. Check wedge layout, game icons, highlighting, selection, cancel and release against Lua DBF.
* Call a stratagem and check the countdown, charges and ready transition in each cooldown layout. Hide and restore the game HUD.
* Switch between weapons with different adjustable fire modes, rates, ammunition and zoom. Change a setting and check its icon. Switch back and check that stale icons disappear.
* Close the settings overlay, cycle the menu and return to the ship. Check that the normal HUD and camera recover.

Run this comparison on Proton and native Windows before promoting the candidate to a public release.
