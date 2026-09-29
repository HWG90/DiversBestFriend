# DiversBestFriendCanary R34 - PageCue

- Add a native UI sound cue when the native wheel changes pages with more than eight stratagems. The cue respects the Sound feedback option, shares the existing move-cue throttle, and is suppressed while an input sequence runs.
- Share one input-interval validation helper between Confirm and Select on Release. Pacing behavior is unchanged.
- Add build-time checks that keep the runtime log headers, INSTALL.txt and the manifest description aligned with the packaged revision.
- Preserve R33 sounds, size presets and opacity controls, R31 scrambling recovery, optional Select on Release and canary metadata/naming.

Install `DiversBestFriendCanary-R34-PageCue.zip` with the game closed; enable only one revision.

Regression tests pass. Please check the page-flip cue in-game together with the R33 sound cues and wheel sizing, including cursor alignment and mode switching. The confirmation cue still means a sequence was accepted, not that the beacon is already equipped.
