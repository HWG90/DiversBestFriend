# DiversBestFriendCanary R33 - Polish

- Remove R32's centered detail card and restore the prior caption/countdown presentation.
- Add optional native UI sound feedback for changed selection and accepted input jobs, with throttling and isolated audio-error handling.
- Add Custom, Compact, Standard and Large size presets, wheel size, icon size, center-label size and native background opacity.
- Group settings into Selection, Appearance, Controller and Advanced using stable IDs and native row spacing. Layout descriptions replace conditional hiding, which the documented framework API does not support.
- Add an illustrated installation guide, mouse/controller examples and a status-message troubleshooting table.
- Preserve R31 scrambling recovery, optional Select on Release and canary metadata/naming.

Install `DiversBestFriendCanary-R33-Polish.zip` with the game closed; enable only one revision. Start with Custom at 100%, or try Compact. Sound feedback defaults on and can be disabled.

Regression tests pass. Please check the native sound cues and wheel/icon/label scales in-game, including cursor alignment and mode switching. The confirmation cue means a sequence was accepted, not that the beacon is already equipped.
