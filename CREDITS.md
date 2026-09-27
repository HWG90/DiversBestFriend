# Credits and acknowledgements

## CowboyBingus

**[CowboyBingus](https://github.com/CowboyBingus) deserves the foundation credit.** Their loader, native settings/bindings infrastructure, public interfaces, documentation, and wider HELLDIVERS 2 modding work made this project practical.

Required, separately installed dependencies:

- **[Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader)** — addon discovery/loading, coexistence in the game's LuaJIT runtime, and shared logging. Use v18 / API 1 for the documented build.
- **[Mod Bindings Menu](https://github.com/CowboyBingus/ModBindingsMenu/releases/tag/v2.0)** — native bindings, automatic action allocation, and activation state for Next/Previous/Confirm. This addon needs v2.0, not the older two-slot v1 release.
- **[Mod Options Menu](https://github.com/CowboyBingus/ModOptionsMenu)** — native option rows and saved settings. Documented dependency: v1.0.1 / API 1.

Their wider [mod collection](https://github.com/CowboyBingus?tab=repositories), including [Vanilla Plus Megapack](https://github.com/CowboyBingus/VanillaPlusMegapack), deserves recognition too. Those gameplay mods are optional and are not dependencies of DiversBestFriend. Installing this project does not install or enable them.

DiversBestFriend is a separate project by HWG90. These credits acknowledge the tools and groundwork; they do not imply CowboyBingus authored, reviewed, endorsed, or supports this addon. Dependencies are linked rather than redistributed, and the MIT license here does not relicense them.

## Project origin and development

- **HWG90 / David** — concept, direction, hands-on game testing, screenshots, feedback, and iterative design. The goal came from frustration with unreliable OCR in the original external Stratagem Wheel helper.
- **GPT-6 Astra** — AI-assisted research, implementation, debugging, tests, and documentation. Put plainly: this project was vibe-coded with Astra, then iterated through actual game testing. AI involvement is disclosed rather than hidden.
- **Earlier Stratagem Wheel and Equipped Stratagems work** — the project's starting point. The native addon replaces the external OCR/input workflow; neither earlier component is required at runtime.
- **DiverKit alpha 8.10.1** — historical layout evidence used during the earlier Equipped Stratagems exporter work. It is not bundled and is not a runtime dependency of this native addon.
- **Arrowhead / the HELLDIVERS 2 team** — the game, its native UI/wheel widgets, and the assets referenced from the installed game. No full game binaries, extracted texture packs, or game DLLs are distributed here.

The simple banner is original project artwork made for this repository, using text and a schematic wheel. It is not an official HELLDIVERS logo or an in-game screenshot.
