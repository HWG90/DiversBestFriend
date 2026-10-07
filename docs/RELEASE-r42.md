# R42 - UI Recovery (test build)

- Recognized transient HUD failures now pause the UI until a valid snapshot confirms that the stratagem menu has closed. Reopen it to resume.
- Cancel queued Confirm and Select on Release input, restore the original UI and release camera control before recovery.
- Keep settings responsive while waiting, suppress held-input replay, and preserve the last runtime error in the log after recovery.
- Keep unsupported-build, memory-integrity, unknown-error and failed-cleanup failures fatal. Limit consecutive unsuccessful recoveries to three.

This is a candidate fix for reports of the radial disappearing permanently after leaving jammer range. The reporting user's error log is not yet available, so the original trigger is not confirmed. Automated tests simulate transient HUD failures; an affected-session log and in-game jammer test are still needed.

Close the game and import `DiversBestFriend-R42-UIRecovery.zip` through Arsenal for testing. Do not enable multiple revisions. If the problem persists, collect `DiversBestFriend.log` before restarting, along with the mode/layout and Select on Release setting. No game files or saved settings are deployed by the build process.
