# Diver's Best Friend for HellForge

This build targets Helldivers 2 build 25480438 on HellForge 0.4. Import the entire DBF ZIP in HellForge and enable DBF and NEST 0.8.1 or later. DBF starts its own game HUD. Existing Bingus Shared Loader installations can keep running their other addons. Importing this ZIP updates the same HellForge DBF mod ID.

Press **F7** to open the DBF menu directly. **Page Down** opens the NEST panel list. If a custom NEST configuration assigns F7 to that list, change its launcher shortcut to free F7 for DBF.

In **Settings**, choose the wedge wheel, native wheel or list, adjust the wheel and icon sizes, choose the cooldown layout, and toggle the weapon strip. Select a category to edit its settings in place, or use **Ctrl+F** to search across categories. Use **Ctrl+E** to review staged changes and **F9** to apply them. **Discard** drops staged edits. **Restore defaults** in **Review** stages the default settings for review. The strip reflects the changeable controls on the equipped weapon. The Diagnostics tab shows build checks, HUD ownership and the latest message from the engine addon.

Auto Terminal Complete enters the arrows by default. To use instant completion when hosting, choose **Terminals → Terminal input → Instant**. An existing terminal input selection takes precedence over the default.

In **Key bindings**, select the action, capture an input or type its INI spelling, then choose **Apply**. **Clear** and **Apply** unbind the action. In **Exclusions**, check the stratagems to exclude and choose **Apply** to save the group. A successful replacement keeps the previous settings file as `settings.ini.bak`.

With DBF-MCM enabled, press **Delete** and select **Diver’s Best Friend** to edit settings, bindings, or stratagem exclusions. Both menus share DBF’s settings file.

With the default bindings, scroll down for Next, scroll up for Previous and press the left mouse button to confirm. Slot shortcuts start unbound. To use Select on Release, choose a Hold menu binding in the game. Point at the centre before releasing to cancel.

## In-mission verification

* Open the stratagem menu with keyboard and controller. Check wedge layout and background blur over a detailed scene, then check game icons, highlighting, selection, cancel and release against Lua DBF.
* Call a stratagem and check the countdown, charges and ready transition in each cooldown layout. Hide and restore the game HUD.
* Switch between weapons with different adjustable fire modes, rates, ammunition and zoom. Change a setting and check its icon. Switch back and check that stale icons disappear.
* Close the settings overlay, cycle the menu and return to the ship. Check that the normal HUD and camera recover.

Run this comparison on Proton and native Windows before promoting the candidate to a public release.
