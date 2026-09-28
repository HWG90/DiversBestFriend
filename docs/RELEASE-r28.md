# R28 - Release Latch

R27 logs confirmed that the native menu closed before the queued code could begin: its evaluated-button hold did not survive the next update.

R28 instead temporarily gives **Display Stratagem List** native **Press** behavior while entering the release-selected code. This is intended to keep the menu open through the configured input interval. The original trigger is restored after completion or cancellation. Key/button assignments and existing Press bindings are preserved; the addon does not write binding files or call Apply.

Includes exact-value restoration, rollback after partial setup failure, detection of changed bindings, and owner checks during cleanup. Select on Release remains optional and off by default.

Install `DiversBestFriend-R28-ReleaseLatch.zip` through Arsenal with the game closed. Enable Select on Release, set Input interval to **70 ms**, hold the menu, point to Resupply, and release. Check whether the code completes and equips the beacon, and that normal Hold behavior returns afterward.

**Test release:** package and isolated Lua tests pass. The live mapping format was verified through read-only inspection, but successful latching/equipping still needs this in-game test.
