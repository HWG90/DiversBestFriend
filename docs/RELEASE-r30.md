# R30 - Beacon Handoff

A comparison trace showed that physical menu release queues a return to the primary weapon. The native opener sees the beacon still equipped and skips requesting its slot again, leaving that earlier switch pending. The code matches, then the pending switch cancels the beacon.

R30 reissues the same native beacon-slot request after reopening when necessary, with owner checks and supported-build signatures. It preserves the input interval, completion wait, and binding restoration. Select on Release remains off by default; Confirm behavior is unchanged.

Install `DiversBestFriend-R30-BeaconHandoff.zip` through Arsenal with the game closed. Enable Select on Release and test a ready stratagem at 70-100 ms. Check that the beacon stays equipped and normal Hold behavior returns afterward. Automated regression tests pass; this fix still needs in-game verification.
