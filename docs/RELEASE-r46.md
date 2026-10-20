# R46 — The Homecoming Update

We're back, baby!

Celebrating coming back to Nexus.

**Diver's Best Friend — Automated Stratagem System (ASS)**

The original native auto-stratagem system. Accept no imitations. Unless they’re compatible.

**Your stratagems. In the game. No OCR. No Python. No AutoHotkey. Just a nice ASS.**

A new home for your cooldowns, a clearer Wedge Wheel, and more control over how ASS looks and plays.

**“Know what you need to know, and when you need to know it.”**

![Cooldown overview and status display](https://i.imgur.com/j2QMCFL.gif)

**“Fast - but still fair.”**

![Stratagem selection and input pacing](https://i.imgur.com/0kZXJqm.gif)

## What it does

Diver's Best Friend puts stratagem selection inside HELLDIVERS 2. Open the normal stratagem menu, choose an entry through a wheel or list, and ASS enters the code through the game's normal input path. You still equip and throw the beacon normally.

It reads live game data rather than trying to read the screen. There is no separate OCR program or external input helper to keep running while you play.

[R46 downloads and full release notes](https://github.com/HWG90/DiversBestFriend/releases/tag/r46) | [Installation and controls](https://github.com/HWG90/DiversBestFriend/blob/r46/docs/INSTALLATION.md) | [Report an issue](https://github.com/HWG90/DiversBestFriend/issues)

## Pick your layout

- **Wedge Wheel:** the default selection mode. Choose Expanded wedges for up to sixteen entries on one wheel, or Cards for native stratagem cards arranged in a circle.
- **List Select:** Next/Previous and Confirm follow list order and wrap at either end. Camera control remains available.
- **Native wheel:** eight slots, mouse or stick pointing, and Next/Previous paging.

Radial layouts retain the original top-left stratagem list. Camera control returns when the menu closes. Delivery, cooldown and exhausted states follow native game availability. Scrambled-code handling follows the currently required sequence.

**Select on Release** supports Hold menu bindings. Its Automatic setting enables release selection for controller input; On also enables it for mouse. Point at an available entry and release to select, or return to center before releasing to cancel. List Select uses Confirm.

**Input interval** controls the delay between code directions: 0–250 ms, default 70 ms. It applies to Confirm and Select on Release. Homecoming also adds optional randomized per-use delay.

## R46 — The Homecoming Update

## Cooldowns at a glance

- A cooldown dock above the stamina bar, with native stratagem backgrounds and quick fade-in.
- An optional compact overview if you prefer a list to the dock.
- Game-font countdowns above, below or inside icons, with shadows. Short inbound, impact and between-run countdowns can use large numbers inside the icon.
- Native game status and remaining time keep displays synchronized across reloads. No independent cooldown clocks.
- Separate short statuses left, right or below the stamina bar. Left/right layouts have a divider; **Center Cooldown Separator** controls whether the complete bar stays centered.
- Full Eagle rearm cooldowns stay with ordinary cooldowns. Charge counts sit opposite the timer without their old box.
- Optional tracking of unavailable/ineligible stratagems. No countdown is fabricated when the game provides none.
- Toggle the display, timers and closed-menu top-left status notices independently.

## Selection and controls

- Wedge Wheel is the default, with 50% default wedge opacity. List Select and Native wheel remain available.
- Four equipped-stratagem hotkeys work from normal gameplay and are unbound by default.
- Configure Next as mouse wheel down, Previous as mouse wheel up, and Confirm as mouse button 1 in MBM. Existing bindings are retained. The native MBM API does not currently apply author-defined mouse defaults.
- Optional random input delay chooses 70–240 ms once per stratagem use. The fixed slider is disabled while randomization is enabled; changing the fixed delay disables randomization.
- Toggle text dimming for unselected list entries while keeping the blurred backing intact.
- Independently hide blacklisted or cooldown entries from the list, with compacted layout to prevent crowding. Blacklisted entries remain unselectable and are omitted from wheels.
- Missing-binding warning and clearer selection feedback.

## Settings and blacklist

Appearance and Blacklist use two columns with related options grouped together. Gold headers and black text keep sections easy to find. Customize wheel size, opacity, timer placement, dock spacing and status visibility.

DBF declares which controls apply to the current mode; **MCM 0.1.72 or newer** handles graying them out, draft changes, Confirm and Discard. Wedge Wheel layout is available only in Wedge Wheel mode; Expanded wedge controls depend on that layout. Core selection works without MCM.

**Blacklist SOS Beacon** and **Blacklist Eagle Rearm** prevent ASS from selecting those entries. MCM adds mission-provided entries, grouped by type, with confirmation. Equipped loadout stratagems remain protected. Filtering affects ASS selection, not the game's actual availability.

Blacklisting and hiding are separate: blacklisted entries can remain visible but unselectable in List Select, or be hidden with **Hide blacklisted stratagems**. Wheels omit them. **Hide stratagems on cooldown** is a separate list option.

MCM also offers Reset One and Reset Page. Page resets stage defaults for Confirm or Discard and leave keybindings unchanged.

## Compatibility

Includes R45's HUD Plus 0.2.8 / 0.2.9, Custom Stratagem Compendium 0.4.1 / HD2Runtime 0.40.0 and Foliage Pass-Through 1.0 compatibility. HUD Plus handoff uses validated cleanup contracts rather than a single version string.

- **HUD Plus 0.2.8 / 0.2.9:** its competing stratagem list and picker yield while ASS controls selection. Other HUD Plus features remain active; its own list resumes when ASS is disabled or recovering.
- **Custom Stratagem Compendium 0.4.1 / HD2Runtime 0.40.0:** custom codes work with Confirm and Select on Release, retaining ownership and code checks.
- **Single-use availability:** exhausted entries such as Shredder cannot be selected again. Becoming unavailable after arming cancels release selection.
- **Foliage Pass-Through 1.0:** recognizes its exact projectile-template change so Runtime can validate custom gas-barrage and cluster-launcher donors. Other changes remain checked.
- Recognized temporary HUD failures cancel pending input and restore UI/camera control. Close and reopen the stratagem menu to recover; held inputs are not replayed.

These compatibility mods are optional. You do not need them to use ASS. Foliage can be on or off; restart after changing it.

## Requirements

Install dependencies separately; they are not bundled.

- One compatible loader: [Bingus Shared Loader / API 1](https://github.com/CowboyBingus/BingusSharedLoader/releases/latest), MDL API 2, or [LLL R30+](https://github.com/HWG90/LLL/releases).
- [Mod Bindings Menu](https://github.com/CowboyBingus/ModBindingsMenu/releases/latest) v2 or newer / API 1.
- [Mod Options Menu](https://github.com/CowboyBingus/ModOptionsMenu), through the chosen loader's shared-addon compatibility route.
- HELLDIVERS 2 on Windows/Steam, supported build 25480438.

[Mod Configuration Menu](https://www.nexusmods.com/helldivers2/mods/17157) is optional for core selection. Use 0.1.72 or newer for the updated conditional controls and page layout. Neither the old external Stratagem Wheel app nor the Equipped Stratagems exporter is required.

## Downloads and installation

Choose **one** loader variant:

| File | Install |
| --- | --- |
| DiversBestFriend-R46-BSL.zip | Import into Arsenal and deploy with Bingus Shared Loader. |
| DiversBestFriend-R46-MDL.zip | Extract into `%LOCALAPPDATA%/MDL/Helldivers2/Mods`; MDL API 2. |
| DiversBestFriend-R46-LLL.zip | Extract into `%LOCALAPPDATA%/LLL/Helldivers2/Mods`; LLL R30+. |

Close the game before installation, remove/disable the previous provider, and restart. Keep Mod Bindings Menu v2+ / API 1 and Mod Options Menu installed through your loader's compatibility route. Optional compatibility mods and dependencies are not bundled. Saved option and binding IDs are retained. Defaults apply to new settings, not overrides of existing preferences.

BSL now uses a small bootstrap with separately compiled, cached modules, following War Journalism’s packaging approach. Readable modules are included under `Source/`; there is no runtime filesystem dependency.

LLL supports live reload after successful owned-UI teardown. BSL and MDL remain restart-only. Target: Windows/Steam build 25480438, game.dll timestamp 1790161983.

## First launch

1. Open MODS > Diver's Best Friend, choose a selection mode and Apply/Confirm. Wedge Wheel is the new-user default.
2. Configure Next stratagem, Previous stratagem and Confirm stratagem in the native bindings menu's MODS tab. Suggested bindings: Wheel Down, Wheel Up and Mouse 1. Native MBM does not currently apply author-defined mouse defaults; existing bindings are retained.
3. In a mission, open the normal stratagem menu and choose an available entry. Keep the menu open until code entry finishes, then throw the beacon normally.
4. For release selection, use a Hold stratagem-menu binding. Return to center before releasing to cancel.
5. Optionally bind the four equipped-stratagem hotkeys. They are unbound by default and work from normal gameplay.

## Troubleshooting

- **Custom stratagems are missing entirely:** verify the Compendium pack is installed, enabled and registered with HD2Runtime. ASS does not install it. Deploy with the game closed, restart and start a fresh mission after a compatibility update.
- **A control stays enabled when it should be gray:** use MCM 0.1.72 or newer and the updated DBF build. BSL requires a fresh deployment and restart to register its new rules.
- **Bindings stop responding:** check the native MODS page and MBM's log. Old reservations from inactive mods can exhaust native action slots. Back up assignments before reclaiming reservations you no longer need.
- **Temporary HUD failure:** close and reopen the stratagem menu. If it persists, preserve DiversBestFriend.log and include your revision, loader, mode and layout in the report.
- **A code is rejected:** check cooldowns, remaining uses, jamming and normal game restrictions. Reopen the menu after manual or interrupted input.
- **A game update breaks startup:** ASS uses build-specific native UI functions and signatures. Install a compatible release.

## Videos

[Original native-selection demo (R24)](https://www.youtube.com/watch?v=u5LjI8qUi7E) | [Select on Release and controller demo (R30)](https://www.youtube.com/watch?v=BcMtszGqTgw)

These demonstrate earlier revisions; the Homecoming notes above describe current behavior.

## Credits and feedback

Thank you to [CowboyBingus](https://github.com/CowboyBingus) for the shared loader, bindings/settings infrastructure and wider modding groundwork that made this possible. This is a separate project by Goose / HWG90. Report ASS-specific problems on this mod page or through [GitHub Issues](https://github.com/HWG90/DiversBestFriend/issues), with the revision, loader, game build, mode/layout and reproduction steps.

This project was developed with AI-assisted coding and hands-on game testing.

[Full credits](https://github.com/HWG90/DiversBestFriend/blob/r46/CREDITS.md) | [Source code](https://github.com/HWG90/DiversBestFriend) | [MIT license for the project code](https://github.com/HWG90/DiversBestFriend/blob/r46/LICENSE)

The game and separately installed dependencies retain their own ownership and licenses.
