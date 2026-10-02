# Canary R39 - Animation Card Validation

R39 fixes the R38 list-compaction regression that could disable both DBF layout and inputs with `Invalid animation card` when blacklist entries were hidden. Original list cards and owned copied cards now pass independent validation paths; original-card range, alignment and parent checks are retained.

This prerelease also includes the previously tested R37 native input/sound/icon function-pointer caching fix for LuaJIT `table overflow`, and R38 blacklist gap compaction. Remaining list entries move into consecutive positions with both native animation endpoints updated. Clearing exclusions, closing/disabling DBF or switching modes restores geometry only while DBF still owns those values. Native stratagem IDs and Confirm mapping are preserved.

Validation: full isolated game-LuaJIT suite and deterministic package checks pass. New integration coverage exercises the actual native backend, duplicate initialization and blacklist compaction/restoration, plus constructed copied cards and address/ownership rejection. The integration regression reproduces `Invalid animation card` with the verified R38 guard and passes with R39. All four layouts have first/middle/last/multiple/all-removal and selection mapping coverage. FFI stress coverage includes 120,000 input/sound helper calls and 10,000 icon repaints. The final ZIP payload is verified to contain all three changes.

**In-game verification remains pending.** Test Hide SOS in list mode, packed navigation and Confirm, switching layouts, clearing exclusions and optional Select on Release in a fresh session.

Install `DiversBestFriendCanary-R39-AnimationCardValidation.zip` through Arsenal with the game closed, enable only one DBF revision, deploy and restart. The stable addon identity, settings and bindings are retained. Stable/main remains R35.

Package SHA-256: `297f47bd1de3eedef711297a82995f79b73008ad6f4e7abe75951b0fbaf34774` (41,543 bytes).

[Changes since Canary R36](https://github.com/HWG90/DiversBestFriend/compare/canary-r36...canary-r39)
