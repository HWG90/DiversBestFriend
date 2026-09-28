# R27 - Release Hold

Replaces Select on Release's one-frame input burst with a paced job that temporarily holds the native stratagem-menu action through code completion. **Input interval (ms)** now applies to release selections as well as Confirm. Try **70 ms** for the first test.

The highlighted selection/page is pinned while entering the code. Temporary Hold actions are cleared on the update after the final matched direction, or on cancellation, timeout, focus loss or errors. Select on Release remains optional and off by default. Throw the beacon normally.

Install `DiversBestFriend-R27-ReleaseHold.zip` in Arsenal with the game closed, deploy, and restart. Existing bindings/settings and Arsenal identity are retained.

**Test candidate:** isolated tests cover paced input and cleanup, but cannot prove that native input evaluation preserves the held action between gameplay updates. Premature closure now cancels and logs the reason rather than replaying the code. Test by holding the menu button, pointing at Resupply, and releasing. Check whether the menu stays open through the arrows and equips the beacon. Logs: `DiversBestFriend.log` and `DiversBestFriend-native.log`.
