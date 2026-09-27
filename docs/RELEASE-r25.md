# R25 - Select on Release

Adds **Select on Release**, an optional setting that is **off by default**.

Enable it in MODS > Native Stratagem Radial, then Apply. Set the game's stratagem-menu binding to Hold. Hold the menu button, point to an item, and release to select it. A separate Confirm binding is not needed. Return the pointer to the center before releasing to cancel.

Works with Native wheel and both Experimental radial layouts. The list still uses Confirm. Explicit Confirm remains available and suppresses duplicate release selection. Throw the beacon normally.

Release selection checks the native Hold action, local ownership, mission membership, focus, UI overlays, manual input and frame age. If the game has already closed the menu, its guarded native opener resumes the input session; the code is completed in that frame and normal gameplay handles equipping. No automatic throw or direct matched-ID assignment.

Install `DiversBestFriend-R25-SelectOnRelease.zip` through Arsenal with the game closed. The Arsenal name, stable GUID and existing settings/bindings are retained.

Isolated tests pass, including release cancellation, single-fire behavior, native rejection cleanup and default-off integration. **This is a test release: the new native reopening path and controller release timing need in-game validation.**
