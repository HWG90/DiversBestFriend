# R29 - Completion Wait

R28 entered and matched the code, then restored Hold behavior on the next update. That could precede the game's native completion/equip transition.

R29 keeps the temporary Press-mode latch until the native menu finishes processing the selection, with a two-second timeout after the last direction. Logs now include menu, entered-count, matched-kind and queued-kind state during the wait. Normal cancellation and binding restoration remain in place.

Install `DiversBestFriend-R29-CompletionWait.zip` through Arsenal with the game closed. Retest Select on Release with Resupply at 70-100 ms, checking both beacon equip and normal Hold behavior afterward. No settings reset is needed.

Package and isolated regression tests pass, including delayed completion and cleanup. **This is a test release: the post-code cancellation fix still needs in-game confirmation.**
