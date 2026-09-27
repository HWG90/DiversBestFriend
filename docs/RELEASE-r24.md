# r24 - Cooldown Indicators

Native wheel and Expanded wedges now indicate timed-out stratagems:

- **Gray/dim icons** during cooldown or incoming delivery.
- **Remaining time below the selected name**, using the native minute/second text widget.
- **Automatic color restoration** when the native timer expires, including raw-icon mode.

List and copied Cards retain their built-in native status/countdown display. Timed entries remain selectable for inspection; Confirm still uses the game's normal availability checks. This does not claim to identify every restriction such as charges or jamming.

Reads the original HUD's cached timer/state, so native special cases such as Reinforce are retained. No new external application, dependency, or text widget is required.

Close the game, replace the previous addon ZIP in Arsenal, deploy, and restart. Stable GUID/settings/bindings retained. Requirements remain CowboyBingus' **Bingus Shared Loader v18 / API 1**, **Mod Bindings Menu v2.0**, and **Mod Options Menu v1.0.1 / API 1**, for Windows/Steam build **25480438**.

Validation: isolated tests cover countdown expiry, minute rollover, incoming delivery, Reinforce, stale/invalid data, palette restoration, and unchanged selection. Native text rendering and placement still need an in-game check.
