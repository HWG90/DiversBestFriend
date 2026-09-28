# Installation and controls

## Install

Windows/Steam HELLDIVERS 2 build **25480438** is the documented target. The addon checks game.dll PE timestamp **1790161983** and native signatures. It is not a universal build-independent mod.

Download and install these separately:

1. [Bingus Shared Loader v18](https://github.com/CowboyBingus/BingusSharedLoader/releases/latest), API 1.
2. [Mod Bindings Menu v2.0](https://github.com/CowboyBingus/ModBindingsMenu/releases/tag/v2.0).
3. [Mod Options Menu v1.0.1](https://github.com/CowboyBingus/ModOptionsMenu).
4. The current stable release is [R30](https://github.com/HWG90/DiversBestFriend/releases/tag/r30), `DiversBestFriend-R30-BeaconHandoff.zip`. The [R31 scrambling test build](https://github.com/HWG90/DiversBestFriend/releases/tag/r31) is `DiversBestFriend-R31-ScrambledCodes.zip`.

Close the game before changing deployed mods. Import the packages into Arsenal, enable them, and deploy. Shared Loader must win the shared startup-resource conflict: its current instructions say last in Arsenal's default order, or first when first-mod priority is enabled. Follow upstream instructions for Purge/Deploy when replacing the loader. Do not keep multiple enabled revisions of this addon or loader.

Restart the game after deployment. No separate app needs to be launched. Python and the test tools are for development only. The original Equipped Stratagems exporter, external wheel app, and CowboyBingus' gameplay megapack are not required.

## Settings

In the escape menu's **MODS** tab, select **Diver's Best Friend**. Change settings and press the native **Apply** control.

| Setting | Effect |
| --- | --- |
| Enable | Enables/disables the addon |
| Selection mode | Native wheel, Keybindings â€” list, or Experimental |
| Experimental layout | Cards â€” copied list rows, or Expanded wedges |
| Full-color stratagem icons | Uses the native channel-mask colors for wheel icons; copied rows retain their native colors |
| Expanded wedge darkness (%) | Expanded wedges only: 0 original gray to 100 black; default **70** |
| Expanded wedge opacity (%) | Expanded wedges only: 0 transparent to 100 opaque; default **75** |
| Radial vertical offset (down) | Fine adjustment after automatic centering; start at **0**. Positive moves down |

For the old expanded-wheel appearance, use darkness **0** and opacity **30**. The selected wedge remains yellow and at least 95% opaque, icons are unaffected, and empty sectors stay fainter. Changes apply through the normal Apply button without reopening the menu. Native wheel/list/copied Cards retain their existing appearance. Blur is not offered in this build: the row-card material has no texture slot for the wedge mask.

An older saved fourth mode migrates to Experimental / Expanded wedges. Mode changes cancel pending code entry and require a fresh Confirm press. r22 preserves saved offsets; if you previously used 575 to compensate for placement, reset it to zero.

## Bindings and selection

Open the game's keyboard or controller bindings and its **MODS** tab. Under **Diver's Best Friend**, assign:

- **Next stratagem**
- **Previous stratagem**
- **Confirm stratagem**

Use bindings that do not interfere with your other controls. Configure the controller mappings separately if you use a controller.

Open the regular stratagem menu with your normal game binding:

- **Native wheel:** point with mouse/stick and press Confirm. There are eight slots per page. Next/Previous changes pages when needed.
- **Keybindings â€” list:** Next moves down the list, Previous moves up, and both wrap. Press Confirm for the highlighted entry. Camera control remains available.
- **Experimental / Cards:** point at a copied native row card and Confirm. Up to 16 cards, no pages.
- **Experimental / Expanded wedges:** point at a sector and Confirm. Up to 16 entries on one wheel, no pages.

In radial modes, pointing owns camera input while the menu is open. Closing the menu releases it. The original list remains visible at top left. Pointer selection near the center/dead zone may select nothing.

Keep the menu open while Confirm enters the code. The game then equips the beacon through its normal input path; **you still throw it yourself**. Normal cooldowns and availability restrictions apply. The addon does not assign a matched stratagem ID or invoke throw/spawn functions.

## Cooldown indicators

Native wheel and Expanded wedges automatically display cooldown and incoming/delivery state from the original HUD:

- A timed-out icon turns grayscale and dim, including when full-color icons are switched off.
- Pointing at it shows the remaining minutes/seconds below the center name. The selected wedge remains highlighted so you can inspect it.
- At expiry, the timer hides and the icon restores its normal appearance automatically.
- Native list and copied Cards keep their built-in status/countdown rows.

No separate setting is needed. Countdown seconds are rounded up to avoid showing zero while time remains. The native HUD handles special cases such as Reinforce; the addon reads its displayed timer rather than assuming a fixed cooldown duration. An unreadable or stale card produces no timer, not a claim that it is ready. Other restrictions (charges, jamming, etc.) are still decided by the game on Confirm.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No settings or binding rows | Verify all three dependency versions, enable/deploy them, and restart |
| Highlight moves but Confirm does nothing | Assign Confirm, use a fresh press, choose an available entry, and keep the menu open for the sequence |
| Pending/partial code after a mode change | Close/reopen the stratagem menu before retrying |
| Menu is too high/low | Reset the saved vertical offset to **0** on r22; report the viewport size and HUD scale if still wrong |
| Nothing loads after a game update | Check the supported build and logs; native addresses/signatures need revalidation |
| Crash when opening the menu | Disable this addon, retain its logs, and report the exact build/mode/layout and other UI mods |
| Input bindings disappear or conflict | Check Mod Bindings Menu deployment; it owns a build-specific input resource and has a finite shared action capacity |

Logs live in `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/`:

- `DiversBestFriend.log` â€” status, selected mode/layout, last confirmation, centering, and offset.
- `DiversBestFriend-native.log` â€” native-call checkpoints, useful after a crash.
- `BingusSharedLoader.log` â€” loading/dependency diagnostics.

Review logs before attaching them publicly. Include the release revision, game build, resolution, HUD scale, mode/layout, and steps to reproduce. r21 modes were author-tested in-game; r22's centering change is regression-tested but awaits a specific live placement check.

## Remove

Close the game, disable/remove the Diver's Best Friend addon in your manager, and redeploy. Keep shared dependencies installed if other mods use them. Follow your manager's documented purge process if deployed files remain.

## Optional Select on Release

Install the [R31 test release](https://github.com/HWG90/DiversBestFriend/releases/tag/r31), `DiversBestFriend-R31-ScrambledCodes.zip`. In MODS > Diver's Best Friend, enable **Select on Release** and Apply. It is off by default. Use a **Hold** stratagem-menu binding: hold, point, release, then throw normally. Center the pointer before releasing to cancel. Applies to all radial layouts; list mode still requires Confirm. Native reopening and controller timing need in-game validation.

### Input interval (ms)

Set the minimum delay between directions for Confirm and release sequences: 0-250 ms in 5 ms steps, default 70 ms. At 0, one direction is sent per frame. Actual spacing is frame-limited. A running sequence keeps its starting value. Select on Release uses this interval while temporarily using native Press behavior for Display Stratagem List. The original trigger is restored when the native menu finishes processing the selection, or on cancellation. A two-second timeout bounds the wait after the last direction. Key/button assignments are unchanged.

R26 names the options and bindings section **Diver's Best Friend**. Older builds show **Native Stratagem Radial** and write `NativeStratagemRadial*.log`. Saved setting and binding IDs are unchanged.
