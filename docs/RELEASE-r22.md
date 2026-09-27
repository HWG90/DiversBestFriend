# DiversBestFriend — r22

First public release of this personal native stratagem-menu project, vibe-coded with GPT-6 Astra. It began because inconsistent OCR in the original external helper was frustrating; the addon now reads live game data and draws inside the game.

- Native eight-slot wheel with paging, keyboard list mode, and experimental copied Cards or Expanded wedges (up to 16 entries).
- Native mouse/stick cursor tracking, explicit Confirm, and optional full-color icons.
- r22 fixes vertical centering; use offset **0**, removing any older 575-unit workaround.
- No external helper application needs to run while playing.

**Required separately:** [Bingus Shared Loader v18 / API 1](https://github.com/CowboyBingus/BingusSharedLoader/releases/latest), [Mod Bindings Menu v2.0](https://github.com/CowboyBingus/ModBindingsMenu/releases/tag/v2.0), and [Mod Options Menu v1.0.1 / API 1](https://github.com/CowboyBingus/ModOptionsMenu). Huge credit to CowboyBingus for the infrastructure that makes this possible.

**Target:** Windows/Steam build 25480438, game.dll PE timestamp 1790161983. This is an independent community mod, not an officially endorsed implementation.

Close the game, import the addon ZIP and dependencies into Arsenal, enable/deploy, and restart. Configure Native Stratagem Radial in the MODS options/bindings tabs. Keep only one enabled addon revision. The development package name and stable GUID remain unchanged for existing users.

**Validation:** r21 modes/layouts were author-tested in-game. r22 passes isolated logic/adapter tests and deterministic package checks; its new vertical placement still needs a specific in-game check.

See the repository README and installation guide for controls, credits, and troubleshooting. The PNG and SVG assets below are reusable project banners, not installation packages.
