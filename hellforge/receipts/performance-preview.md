# R50-hellforge.15-preview

Prepared against `09fcf72` (.14 diagnostic). This is a local performance
preview; public release remains .11. The existing blur diagnostic is preserved.

## Changes

- Retain scalar, color and vector properties only for the expanded wheel's
  separately owned widget subtree. Unchanged properties no longer invoke the
  native setters. Cache angular geometry until the row count changes.
- Keep live parent/HUD validation, rebuilding retained state for each new
  widget generation. Changes to selection, settings, code arrows, cooldowns,
  visibility and row count still update immediately. Failed vector writes are
  retried. Original game widgets retain their existing behavior.
- Pace Lua Confirm, Hold-release/shortcut entry and the C fallback against
  scheduled deadlines. Carry sub-frame lateness instead of adding it to every
  arrow. The interval now specifies the target cadence; adjacent actual gaps
  can vary by a frame. Normal entry still sends at most one direction per
  update. A full missed interval resets pacing, so stalls do not cause bursts.
- Batch each input hash-map header into one guarded read instead of four,
  and read the entered code prefix together instead of one byte at a time.
  Ownership, membership, scramble/code, range and cleanup checks remain live.

## Evidence

The fixtures execute the actual Lua controllers and renderer, with native
functions replaced by recording callbacks. Baseline is the unmodified .14
source. These are deterministic call counts and simulated-frame latency, not
in-game FPS or measured game-thread CPU time.

| Scenario | .14 baseline | .15 preview |
| --- | ---: | ---: |
| Static 16-slot expanded wheel, 120 frames: native scalar/color/etc. calls | 13,560 | 0 |
| Same frames: backend vector setters | 6,000 | 0 |
| Nine-arrow Confirm, 60 Hz, configured 70 ms cadence | 683.3 ms | 566.7 ms |

The drawing count excludes construction and changed frames. The game still
renders the retained widgets. This is not a claim of zero total draw calls.

Validation completed:

- `hellforge/build.sh test`: 25 groups passed, 0 failed. Python portion: 59
  tests, 16 skipped for optional dumps/external fixtures not supplied.
- `test_hud_retained.lua`: static setter budget, selection-only changes,
  theme-based colors, live settings, code shortening, cooldown transitions,
  failed-set retry, hide/reopen, compaction/growth and stale/detached owners.
- `test_hud_pacing.lua` and C `test_entry`: cadence, stalls, input cleanup,
  HUD replacement and unchanged Instant final-arrow release/settle behavior.
- DLL build, pinned SDK and import checks passed. ZIP verification compares
  every member to current source, DLL and embedded Lua payload.
- Wine required execution outside the sandbox (sandbox calls ended with
  SIGSYS before the harness ran). The first unrestricted run passed 29/30
  cases; List Confirm still asserted the previous minimum-gap semantics.
  Its assertion now checks one direction per tick and no advance ahead of
  the configured cadence. Both List Confirm and no-host-entry passed on
  rerun with that assertion; all 30 cases are covered by passing results.

## Launcher correction, November 8

The first .15 archive had a 36-character version string. Its ZIP verification
passed, but HellForge skipped it during launch `aa81704236764767afca2b3cfee8bc5a`.
The installed CLI accepted 32 characters and rejected 33 in a scratch import.
The corrected manifest and DLL use `R50-hellforge.15-preview` and the packager
now enforces the limit during export and verification.

Installed `mods/divers-best-friend-R50-hellforge.15-preview.zip` in the active
HellForge prefix. SHA-256 `e049558ba18c34f5cbfee1a434d0a6639255a13ff5da7bc5e7bd1e76df577aee`.
HellForge's live `mods` catalog returned one enabled `DBF Reforged` entry with
the corrected version. In a scratch installation HellForge staged its DLL and
the pinned game VM attached the HUD. A Wine test using both DLLs from the
installed ZIP registered the F7 panel with bundled NEST. The rejected archive
was moved to `backport-backups/dbf-15-version-20261109T033044Z/`.

Rollback bundle (.14 diagnostic), configuration backup and install receipt:
`~/.local/share/hellforge-prefix/pfx/drive_c/users/steamuser/Documents/HellForge/backport-backups/dbf-performance-20261106T033506Z/`.
Activation requires a new HellForge game launch; no loaded DLL was replaced.

No in-game performance measurement or appearance verification was performed.
In a mission, check repeated open/close, mouse/controller selection, normal
and Instant calls, shortcuts, cooldown expiry, and return-to-ship cleanup
before promoting this preview.

## Dock timer previews .16 and .17, November 16

The "above" cooldown timer was drawn over its icon. `.16-preview` (1c813c1)
placed timers from each tile's measured rectangle and logged it: the tile sat
exactly at the dock point, yet the label still overlapped. Measured against
the user's screenshots, every screen-GUI drawing at a HUD widget's world
position lands 36 px (18 HUD units at 4K) below the widget: timers drawn at
323 and 333 sat 36 low, and the inside backdrop sat under its tile.
`.17-preview` (5911f4f) lifts dock drawings by 18 units. Its log reads
`GUI 3840x2160, viewport 1920x1080 matrix 2 0 0 2 0 0; parent none`, so the
lift is not the viewport's translation; its engine source is still unknown.

Installed `mods/divers-best-friend-R50-hellforge.17-preview.zip`, SHA-256
`8d9c3dbaf0b45eda39cb2fd3114afd3aea3be7b07970bf2ea2b9863abf400033`. Backups
and receipts: `backport-backups/dbf-16-dock-timer-20261116T050218Z/` and
`backport-backups/dbf-17-dock-lift-*/`. Accepted in game the same day: both
timers sit centred about 14 px above their icons.
