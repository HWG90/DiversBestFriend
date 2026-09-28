# DiversBestFriendCanary R32 - Wheel Feedback

- Add an independently constructed native row in the center of Native wheel and Experimental expanded wedges for the highlighted stratagem.
- Reuse native availability text, countdowns and arrow-entry progress, including the game's scrambled-code presentation.
- Add **Wheel status and input progress**, enabled by default; turn it off to restore the previous center caption and timer.
- Fit the row to the wheel center, respect the saved vertical offset, and hide it when no item is highlighted.
- Keep the original top-left list, List mode and Cards layout. Preserve R31 scrambling support and optional Select on Release.
- Use canary package names, Arsenal metadata and diagnostic filenames.

Install `DiversBestFriendCanary-R32-WheelFeedback.zip` with the game closed. Canary uses the same addon identity as stable; enable only one revision.

Automated tests pass. Please test native and expanded wheels with ready/cooldown/incoming entries and watch the arrows during Confirm and Select on Release. Also check blocked/jammed status text when available. This reuses the native row renderer rather than inventing status labels; in-game appearance and progress timing still need verification.
