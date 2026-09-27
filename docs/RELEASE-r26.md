# R26 - Polish

- Options and bindings now appear under **Diver's Best Friend**.
- Clearer, shorter setting descriptions, including the optional release-selection behavior.
- Logs are now `DiversBestFriend.log` and `DiversBestFriend-native.log` in the usual Shared Loader logs folder.
- Updated installation instructions and Arsenal revision metadata. The Arsenal display name remains **Diver's Best Friend - Automated Stratagem System (ASS)**.

Existing settings and bindings are preserved. Close the game, replace the previous addon with `DiversBestFriend-R26-Polish.zip` in Arsenal, deploy, and restart.

Includes R25's optional **Select on Release**, still off by default, and **Input interval (ms)**, default 70 ms for Confirm-driven sequences. Release selection remains immediate and does not use that interval.

Package and isolated Lua tests pass. This remains a test release because native release selection/controller timing needs in-game validation.
