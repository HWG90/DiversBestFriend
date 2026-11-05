# Diver's Best Friend for HellForge

This build targets Helldivers 2 build 25480438 on HellForge 0.4. Import the entire DBF ZIP in HellForge and enable DBF, HF-LLL 0.1.0 and Goose Overlay Host 0.6.0. The ZIP contains the native input DLL and the companion archive that draws inside the game HUD.

Press F7, select **Diver’s Best Friend**, and open **Settings** to choose the wedge wheel, native wheel or list, adjust the wheel and icon sizes, choose the cooldown layout, and toggle the weapon strip. The strip reflects the changeable controls on the equipped weapon. The Status tab shows build checks, HUD ownership and the latest message from the engine addon.

With the default bindings, scroll down for Next, scroll up for Previous and press the left mouse button to confirm. Slot shortcuts start unbound. To use Select on Release, choose a Hold menu binding in the game. Point at the centre before releasing to cancel.

## In-mission verification

* Open the stratagem menu with keyboard and controller. Check wedge layout, game icons, highlighting, selection, cancel and release against Lua DBF.
* Call a stratagem and check the countdown, charges and ready transition in each cooldown layout. Hide and restore the game HUD.
* Switch between weapons with different adjustable fire modes, rates, ammunition and zoom. Change a setting and check its icon. Switch back and check that stale icons disappear.
* Close the settings overlay, cycle the menu and return to the ship. Check that the normal HUD and camera recover.

Run this comparison on Proton and native Windows before promoting the candidate to a public release.
