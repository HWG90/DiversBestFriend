# R45 / HUD Plus 0.2.8 compatibility

Based on the published R42 tag `r42-ui-recovery-test`, commit
`dfc7b209c6e8e496b72d89971b538185235a9c7b`. Its assembled runtime SHA-256 is
`add3fd2930c48c2337b0a15bd20fda237b51a0b439175479a25be04e2ca66a76`, matching
Arsenal's existing R42 package byte for byte before this compatibility change.
R42's UI recovery, blacklist, selection safeguards and settings are retained.

HUD Plus 0.2.8 was downloaded from Nexus mod 15298, file 69169. Original ZIP
SHA-256: `bcb2c911eadb3a016e12b915709ffba96ffa111723512105c0f9ded899d92a71`.
Its stratagem feature constructs a second list and hides the vanilla group
with opacity zero. ASS's list and wheels use that original group. The 0.2.8
feature, list implementation and update-wrapper module are identical to 0.2.7;
the picker now commits on left-mouse release. The adapter prevents that picker
from running while ASS owns selection, through the same feature boundary.

The adapter makes the recognized HUD Plus stratagem feature yield after ASS
initializes successfully. HUD Plus's normal disabled path restores vanilla
opacity, releases its duplicate list, and resets its picker. Weapon displays
and cooldown cards retain their existing code paths. Disabling ASS, a fatal
runtime failure, or entering R42's transient UI recovery returns control to
HUD Plus at its next feature update. After recovery ASS reacquires control.
Saved settings are untouched. The 3D list and picker yield for the whole time
ASS is active, including while holding a beacon.

Discovery follows at most 128 update closures, with depth 24, 64 upvalues per
closure, eight update-chain generations, and sixteen runtime owners. It runs
only when the update callback changes. Bounded runtime program identity checks
catch deferred startup and successor programs without scanning unchanged
closures; the inspected runtime exposes no generation subscription. Five
stripped LuaJIT method fingerprints gate installation. Unknown implementations
remain untouched. No native guards or parent checks have been weakened.

Build and test: set `HD2_HUD_PLUS_SOURCE` to the unmodified extracted 0.2.8
product Lua, then run `py -3 scripts/test.py`. The candidate is written to
`dist/releases/r45/DiversBestFriend-R45-BSL.zip`.
Without the external fixture, owner-specific tests explicitly report a skip.
Third-party source is never included in the candidate package.

Validation covers package contents and reproducibility; the existing R42
LuaJIT suite; the real HUD Plus 0.2.8 feature and update-wrapper code; both
update load orders; deferred startup; list takeover and restoration; picker
reset; disable/re-enable; return-value preservation; R42 recovery/fatal-failure
handoffs; and 10,000 idle frames without rediscovery.

The compatibility predecessor was deployed on LLL. HUD Plus coexistence was
captured and the final combination was reported working in-game. Per-family
beacon delivery, multiplayer and matched steady-state/transition performance
measurements are not established by the fixture suite. MDL gameplay remains
unverified.

The combined candidate also includes the custom-code reader described in
CUSTOM-STRATAGEM-COMPATIBILITY.md.

R45 publishes this adapter in BSL, MDL and LLL variants. The LLL predecessor was captured with HUD Plus and later reported working in-game. See docs/RELEASE-r45.md for current validation boundaries.
