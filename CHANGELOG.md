# Changelog

All documented changes to **Diver's Best Friend / DiversBestFriend** through **Canary R39**.

R32, R33 and R34 are canary revisions, published under `canary-r32`, `canary-r33` and `canary-r34`. R22 is the first public release. Earlier entries are reconstructed from the repository's retained research notes; no individual release history is available for R1–R8. Dates below are GitHub publication dates in UTC. Validation statements describe what was recorded for that revision, not a new verification of the game or mod.

## Canary R36 — Blacklist — 2026-10-02

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/canary-r36)

- Add a persistent SOS Beacon exclusion toggle and eight extra native-kind ID slots, empty by default.
- Filter all DBF selection layouts before navigation and geometry; preserve native gameplay availability. Hide excluded copied cards and temporarily hide excluded stock rows in DBF list mode, restoring their scale on close/disable/mode change.
- Cancel queued/armed input when applied exclusions change. Empty filtered lists release camera capture and cannot confirm. Guard against reused card addresses changing kind.
- Prerelease; in-game verification remains pending. See [release notes](docs/RELEASE-canary-r36.md).

## R35 — Bindings Compatibility — 2026-10-01

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r35)

- Accept numeric Mod Bindings Menu interface versions 2 and newer with API 1, restoring compatibility with the updated megapack. Reject invalid/missing versions safely.
- Promote the R34 canary implementation, including R33 appearance/settings improvements and native sound cues, into the normal release package. Stable identity and binding IDs are preserved.
- Full isolated LuaJIT and package checks pass. In-game verification of this build remains pending. See [release notes](docs/RELEASE-r35.md).

## Canary R34 — PageCue — 2026-09-29

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/canary-r34) · [Changes from R33](https://github.com/HWG90/DiversBestFriend/compare/canary-r33...canary-r34)

### Added

- A native UI sound cue when the native wheel changes pages with more than eight stratagems. The cue respects the Sound feedback option, shares the existing move-cue throttle, and is suppressed while an input sequence runs.

### Changed

- Confirm and Select on Release now share one input-interval validation helper; pacing behavior is unchanged.
- Build-time checks keep the runtime log headers, package install text and manifest description aligned with the packaged revision, so a future revision bump cannot ship mismatched metadata.

### Validation and upgrade notes

- Regression coverage includes the page-cue lifecycle (one cue per flip, silent reopen and single-page presses, no cue during jobs or when sounds are off) and invalid-interval fallback.
- The page-flip cue needs in-game verification together with the R33 sound and sizing checks.
- Package: `DiversBestFriendCanary-R34-PageCue.zip`. Install with the game closed and enable only one revision.

## Canary R33 — Polish — 2026-09-28

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/canary-r33) · [Changes from R32](https://github.com/HWG90/DiversBestFriend/compare/canary-r32...canary-r33)

### Changed

- Removed R32's centered native detail card and restored the earlier wheel caption and selected-item countdown presentation.
- Grouped options into **Selection**, **Appearance**, **Controller**, and **Advanced**, retaining stable saved setting IDs.
- Used native row spacing and layout descriptions to organize settings; the documented options API does not support conditional hiding.
- Preserved R31 scrambled-code resolution and recovery, optional Select on Release, and canary naming and metadata.

### Added

- Optional native UI sound feedback when the selected entry changes and when an input job is accepted. Sound feedback defaults on and can be disabled.
- Repeat throttling and isolated audio-error handling. A failed UI sound does not disable selection, and normal gameplay input sounds remain in place.
- **Custom**, **Compact**, **Standard**, and **Large** size presets, preserving custom slider values when using a preset.
- Independent wheel, icon, and center-label sizing, plus native background opacity controls.
- Scaling of native/expanded wheels and their cursor together; Cards uses the size control for radial spacing.
- An illustrated installation guide, mouse/controller examples, and a status-message troubleshooting table.

### Validation and upgrade notes

- Regression coverage includes sound-cue lifecycle, setting bounds and grouping, presets, and native transform routing.
- Native sounds, visual sizing, cursor alignment, and mode switching still require in-game checks.
- The confirmation sound means an input sequence was accepted, not that the beacon is already equipped.
- Package: `DiversBestFriendCanary-R33-Polish.zip`. Install with the game closed and enable only one revision. Start with Custom at 100%, or try Compact.

## Canary R32 — Wheel Feedback — 2026-09-28

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/canary-r32) · [Changes from R31](https://github.com/HWG90/DiversBestFriend/compare/r31...canary-r32)

### Added

- Independently constructed native-row feedback in the center of Native wheel and Experimental / Expanded wedges for the highlighted stratagem.
- Native availability text, countdowns, arrow-entry progress, and the game's scrambled-code presentation through the existing native row renderer.
- **Wheel status and input progress**, enabled by default. Disabling it restored the previous center caption and timer.
- Center fitting, saved vertical-offset handling, and hiding when no item is highlighted.
- Guard-failure fallback to the previous caption/timer without disabling selection.

### Changed

- Restored copied-card visibility when switching layouts; retained the original top-left list, List mode, and Cards layout.
- Published as **DiversBestFriendCanary**, with canary package names, Arsenal metadata, and diagnostic filenames.
- Retained the same addon identity as the stable build: only one revision should be enabled.

### Validation and later outcome

- Automated tests covered selection, empty selection, centering, mode switching, options, and isolation from original widgets.
- Native appearance, blocked/jammed status, and progress timing still needed live verification.
- The centered detail-card presentation was subsequently removed in R33 after visual feedback.
- Package: `DiversBestFriendCanary-R32-WheelFeedback.zip`.

## R31 — Scrambled Codes — 2026-09-28

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r31) · [Changes from R30](https://github.com/HWG90/DiversBestFriend/compare/r30...r31)

- Replaced blanket rejection of scrambled codes with the native per-stratagem effect query and definition remapping used by the game matcher.
- Applied resolved sequences to Confirm and Select on Release, including sequences with different lengths, while preserving the selected stratagem identity.
- Rechecked the required code before every direction. A mid-sequence change stops input; close and reopen the menu to retry.
- Restored temporary release bindings on interruption so a later clean selection can proceed without reloading the mod.
- Validated original/resolved definitions, local position ownership, and native function signatures.
- Preserved native availability restrictions; scrambling support does not bypass jamming.
- Added regression coverage for nonzero seeds without active effects, changed code lengths, entering/leaving effects, both selection paths, and cleanup/recovery.
- Automated tests passed; live verification of reported spire/scrambler encounters remained pending.
- Package: `DiversBestFriend-R31-ScrambledCodes.zip`.

## R30 — Beacon Handoff — 2026-09-28

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r30) · [Changes from R29](https://github.com/HWG90/DiversBestFriend/compare/r29...r30)

- Addressed a stale return-to-primary weapon request created by physical menu release. The native opener could see the beacon still equipped and leave that earlier request pending, cancelling the beacon after the code matched.
- Reissued the native beacon-slot request after reopening when necessary, using the same request path as the native opener.
- Added weapon-request ownership validation and supported-build guards for the native function and opener call sites.
- Preserved input pacing, completion waiting, binding restoration, default-off Select on Release, and existing Confirm behavior.
- Added regression coverage for stale requests, already-requested beacon slots, and failure cleanup.
- Automated tests passed; live beacon-handoff verification remained pending. Release notes requested testing at 70–100 ms and checking normal Hold behavior afterward.
- Package: `DiversBestFriend-R30-BeaconHandoff.zip`.

## R29 — Completion Wait — 2026-09-28

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r29) · [Changes from R28](https://github.com/HWG90/DiversBestFriend/compare/r28...r29)

- Kept the temporary Press-mode latch until the native menu finished processing the selection, instead of restoring Hold on the next update after a code match.
- Added a two-second completion timeout after the final direction.
- Rejected a lost match while the menu remained active, retaining normal cancellation and restoration paths.
- Logged native menu state, entered-direction count, matched kind, and queued kind to distinguish a matched code from completion.
- Skipped further pointing/context preparation during completion to tolerate native menu/HUD closing order.
- Package and isolated tests passed, including delayed completion and cleanup; the reported post-code cancellation still required live retesting.
- No settings reset was required. Package: `DiversBestFriend-R29-CompletionWait.zip`.

## R28 — Release Latch — 2026-09-28

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r28) · [Changes from R27](https://github.com/HWG90/DiversBestFriend/compare/r27...r28)

- Replaced R27's overwritten evaluated-button hold with temporary native **Press** behavior for **Display Stratagem List** during release-selected code entry.
- Preserved configured direction pacing, then restored the original trigger on completion or cancellation.
- Left key/button assignments and pre-existing Press bindings unchanged; did not write binding files or invoke Apply.
- Added exact-value restoration, partial-setup rollback, detection of user binding edits, relocated-map handling, and owner checks during cleanup.
- Included the intervening master-toggle rename to **Enable Mod** in the tagged source history.
- R27 live logs had confirmed early menu closure before queued input. R28 package and isolated tests passed, and the live mapping format was inspected; successful latching/equipping still needed an in-game test.
- Package: `DiversBestFriend-R28-ReleaseLatch.zip`.

## R27 — Release Hold — 2026-09-28

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r27) · [Changes from R26](https://github.com/HWG90/DiversBestFriend/compare/r26...r27)

- Replaced same-frame Select on Release input with a paced job that temporarily asserted the native menu Hold action.
- Applied **Input interval (ms)** to release sequences as well as Confirm.
- Pinned the selected entry and wheel page during release code entry.
- Cleared temporary held actions on the update after the final matched direction, or on cancellation, timeout, focus loss, and errors.
- Cancelled and logged premature native menu closure instead of reopening and replaying a partial sequence.
- Retained saved settings, bindings, Arsenal identity, default-off release selection, and manual beacon throwing.
- Isolated tests covered pacing and cleanup. Subsequent live logs showed that the evaluated-button hold did not persist across native updates; R28 replaced this approach.
- Package: `DiversBestFriend-R27-ReleaseHold.zip`.

## R26 — Polish — 2026-09-27

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r26) · [Changes from R25](https://github.com/HWG90/DiversBestFriend/compare/r25...r26)

- Renamed options and bindings sections to **Diver's Best Friend** and shortened setting descriptions.
- Renamed logs to `DiversBestFriend.log` and `DiversBestFriend-native.log`.
- Exposed `DiversBestFriend` as a runtime alias while retaining the existing alias and resource identity.
- Preserved the mod GUID, saved settings, and binding IDs.
- Refreshed installation instructions and Arsenal revision metadata. Arsenal's display name remained **Diver's Best Friend - Automated Stratagem System (ASS)**.
- Retained R25's default-off Select on Release and default 70 ms Confirm interval. Release selection was still immediate in this revision.
- Package and isolated tests passed; native release selection/controller timing still needed live validation.
- Package: `DiversBestFriend-R26-Polish.zip`.

## R25 — Select on Release — 2026-09-27

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r25) · [Changes from R24](https://github.com/HWG90/DiversBestFriend/compare/r24...r25)

- Added optional **Select on Release**, disabled by default, for Native wheel and both Experimental radial layouts using a Hold menu binding.
- Added center-to-cancel behavior. List mode retained Confirm; explicit Confirm suppressed duplicate release selection.
- Added **Input interval (ms)** for Confirm: 0–250 ms in 5 ms steps, default 70 ms. At zero, one direction is sent per frame.
- Fixed the interval for each running sequence and scaled the timeout for longer codes at maximum delay.
- Kept release-selected codes immediate in this revision; release pacing arrived in R27.
- Guarded release selection against stale frames, lost focus, UI overlays, manual input, ownership changes, and invalid mission membership.
- Used a guarded native opener to resume a closed input session and closed reopened sessions on rejection. Normal gameplay handled equipping; no automatic throw or direct matched-ID assignment was added.
- Included intervening Arsenal branding and standardized `DiversBestFriend-R#-RecentFeature.zip` package naming in the tagged source history.
- Isolated tests passed for cancellation, single-fire behavior, rejection cleanup, and default-off integration. Native reopening/controller timing remained unverified in-game.
- Package: `DiversBestFriend-R25-SelectOnRelease.zip`.

## R24 — Cooldown Indicators — 2026-09-27

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r24) · [Changes from R23](https://github.com/HWG90/DiversBestFriend/compare/r23...r24)

- Grayed and dimmed Native wheel and Expanded wedge icons during native cooldown or incoming-delivery states.
- Added a selected-item minute/second countdown beneath the center name using an owned native text widget.
- Restored normal icon appearance automatically at timer expiry, including when full-color icons were disabled.
- Read native HUD cached state to retain special cases such as shared Reinforce, with kind-identity checks and finite, bounded timer validation.
- Rounded positive countdown seconds up and cleared stale/invalid timer data.
- Preserved selection, paging, native availability checks, and the built-in timers in List and copied Cards.
- Timed entries remained selectable for inspection. Indicators did not claim to identify all restrictions, including charges or jamming.
- Added tests for incoming delivery, Reinforce, minute rollover, expiry, stale data, grayscale palettes, and raw-icon restoration. Native text rendering/placement still needed live verification.

## R23 — Wedge Appearance — 2026-09-27

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r23) · [Changes from R22](https://github.com/HWG90/DiversBestFriend/compare/r22...r23)

- Added independent Expanded wedge darkness and opacity sliders, each 0–100% in 5% steps.
- Set defaults to **70% darkness / 75% opacity**. **0% / 30%** restored the previous appearance.
- Preserved yellow selected wedges at at least 95% opacity, visible icons, and fainter empty sectors.
- Applied appearance changes through the normal Apply control while preserving selection; other layouts retained their appearance.
- Investigated row-card blur but deferred it because the native material lacked a wedge-mask texture binding.
- Added tests for endpoints, invalid settings, live updates, and selection preservation. In-game appearance verification remained pending.

## R22 — Viewport Centering / First Public Release — 2026-09-27

[Release and download](https://github.com/HWG90/DiversBestFriend/releases/tag/r22)

- Published DiversBestFriend with installation/development documentation, credits, MIT license, and PNG/SVG banners.
- Shipped the native eight-slot wheel with paging, keyboard list mode, and Experimental Cards/Expanded wedges with up to 16 entries.
- Included native mouse/stick tracking, explicit Confirm, optional full-color icons, and operation without an external helper application.
- Corrected vertical centering by projecting the native GUI matrix on its X/Z plane instead of X/Y.
- Applied viewport-midpoint/inverse-transform centering to both screen axes.
- Defaulted vertical adjustment to zero while preserving saved values; users with the earlier 575-unit workaround needed to reset it manually.
- Added centering telemetry and tests for HUD scales, viewport heights, both axes, and singular transforms.
- Documented Windows/Steam build **25480438**, game.dll PE timestamp **1790161983**, and separately installed dependencies: Bingus Shared Loader v18 / API 1, Mod Bindings Menu v2.0, and Mod Options Menu v1.0.1 / API 1.
- Isolated tests and deterministic packaging passed. R21 layouts had been author-tested; R22's specific placement correction still needed a live check.

## R21 — Experimental Layout Consolidation — Pre-public

- Consolidated selection into **Native wheel**, **Keybindings — list**, and **Experimental**.
- Made Experimental layout choose between copied **Cards** and **Expanded wedges**, removing its duplicate native-wheel choice.
- Migrated legacy mode 4 to Experimental / Expanded wedges while retaining rendering and input behavior.
- Read the legacy saved mode before option registration and persisted migration through the documented options API, without editing the settings file directly or overriding later user changes.
- Author confirmed the modes/layouts worked as expected in-game.

## R20 — Expanded-Wedge Rotation Correction — Pre-public

- Corrected native rotation handedness and artwork phase after screenshots disproved R18's orientation model.
- Used a +67.5-degree local native rotation and the negative mathematical icon angle for the outer parent.
- Matched highlighted wedges to cardinal and diagonal icon positions for 8–16 sectors.
- Preserved input vectors, icon positions, selected names, Confirm, and R19 full-color icons.
- Added tests reproducing both earlier incorrect screenshots and checking corrected transforms. Live retesting was pending in the revision notes.

## R19 — Native Full-Color Icons — Pre-public

- Added **Full-color stratagem icons**, enabled by default, using the native stratagem material and channel-color uniforms instead of exposing red/green texture masks.
- Validated category palette bounds and color values before assignment.
- Invalidated both wheel-renderer caches when toggling the option.
- Retained white vertex tint for full-color icons while keeping yellow wedge highlights; disabling the option restored the earlier generic material.
- Left List and copied Cards under their native renderer.
- Added material, parameter, toggle-restoration, invalid-palette, and routing tests. Live color verification remained pending.

## R18 — Artwork Orientation Attempt — Pre-public

- Changed expanded-wedge local rotation after R17 showed the selected wedge opposite the correct cursor/name selection.
- Left pointer integration, icon coordinates, angular selection, and Confirm unchanged.
- Added art-ray transform checks.
- Later screenshots disproved the orientation model. R20 superseded this correction.

## R17 — Expanded Wedges Prototype — Pre-public

- Added Expanded wedges as a fourth selection mode, retaining earlier mode values.
- Displayed up to 16 mission entries without paging using independently allocated native sprites and transforms; did not extend the native wheel's fixed eight-slot arrays.
- Added angular selection with a center dead zone, center captions, and reuse of the native cursor.
- Reset selection and gated held Confirm on membership changes; cancelled active jobs when required.
- Added geometry, constructor, ownership, slot-16 selection, membership-change, and mode-switching tests.
- Live screenshots subsequently exposed artwork alignment errors addressed in R18 and R20.

## R16 — Experimental Mode Integration — Pre-public

- Added Experimental as mode 3 while preserving Native wheel and List mode values and the addon GUID.
- Offered copied native row Cards or the eight-slot wheel baseline as Experimental layouts at this stage.
- Reused the native wheel cursor while suppressing its ring, wedges, names, and icons for copied-row presentation.
- Restored normal wheel drawing when switching back; layout changes cancelled active sequences and gated held Confirm.
- Recorded user confirmation that R15 worked in-game. New R16 routing/cursor transitions were fixture-tested; live testing remained pending.

## R15 — Native Emote-Style Wheel — Pre-public

- Constructed an independently owned shared native wheel in the validated HUD context, leaving the original list/cards intact.
- Populated eight slots from active mission entries ordered by native displayed row position.
- Added wrapped Next/Previous paging, including partial final pages; membership changes reset paging and active sequences blocked page changes.
- Used native mouse/stick integration, sector selection, cursor movement, highlights, stratagem icons, and localized center names.
- Cleared selection on empty sectors and gated held Confirm across page changes.
- Preserved explicit stratagem Confirm and camera capture without invoking emote gameplay activation.
- Added aligned storage, ownership checks, native signature guards, and call-boundary diagnostics.
- Later R16 notes record successful user validation of R15 in-game.

## R14 — Native List Navigation Order — Pre-public

- Fixed Next/Previous jumping between rows by sorting eligible list entries by settled native Y position rather than storage/payload order.
- Made Next move top-to-bottom and Previous reverse, with wrapping in both directions and deterministic ties.
- Tracked selected widget identity across native reordering and retained the correct stratagem identity for Confirm.
- Used target positions to avoid ordering changes during opening animation or highlight scaling; radial slot order was unchanged.
- Added scrambled-slot, gap, wrap, reorder, identity, empty-list, and single-row tests. Live navigation retesting was pending.

## R13 — Radial and Keyboard List Modes — Pre-public

- Added separate Mouse — radial and Keybindings — list options while preserving existing settings and bindings.
- Required pointing before radial selection; retained Confirm as the activation action.
- Kept original native row placement in List mode and highlighted the selected row at 1.10 times its native scale.
- Added explicit ownership-aware native camera-input capture during focused radial selection, with cleanup on close, focus loss, mode change, disable, or failure.
- Restored displays and cancelled input on mode changes, suppressing Confirm held across a switch.
- Added mode-routing, camera-ownership, cleanup, highlight-restoration, and held-confirm tests. Subsequent notes confirmed mode selection worked in-game.

## R12 — Maelstrom Definition Alignment — Pre-public

- Accepted four-byte alignment for packed native stratagem definitions after a Maelstrom definition was incorrectly rejected by the eight-byte check.
- Retained eight-byte alignment for object pointers and all definition bounds, identity, and direction guards.
- Added a fixture reproducing Maelstrom's nine-direction sequence and rejection tests for invalid alignment, bounds, and identity.
- Recorded user confirmation that R11 drawing, pointing, Confirm, and the original list worked. The Maelstrom fix itself still required live retesting.

## R11 — UI Context Address Correction — Pre-public

- Corrected the UI context-manager address from `0x348CE90` to `0x347CE90`, resolving R10's early “UI context manager unavailable” guard failure.
- Changed the fixture to derive the pointer slot from native instruction bytes instead of repeating the same constant and masking the typo.
- Preserved Arsenal GUID/schema and updated revision/package identity.
- Subsequent R12 notes recorded successful in-game drawing, pointing, confirmation, and original-list behavior.

## R10 — Native HUD Resource Context — Pre-public

- Added the native widget resource-context scope omitted in R9, deriving and validating it from the original list.
- Scoped native construction/update calls and checked context-stack capacity, widget context, and restoration after success or Lua errors.
- Added explicit 16-byte FFI storage alignment and surrounding canaries.
- Added persisted native-call boundary diagnostics for construction, attachment, updates, pointing, and layout.
- Investigated an R9 crash on menu opening. Missing context scope was a confirmed defect, but the crash cause was not established by a native stack trace.
- A mistyped context-manager address prevented the new path from running; R11 corrected it. R8 remained the last confirmed working build at that point.

## R9 — Independent Cards and Native Pointing — Pre-public

- Constructed an owned duplicate root and native cards instead of moving the original top-left list or copying live widgets.
- Reused duplicate storage across openings, invalidated stale HUD pointers, and retained uncertain linked generations within a bound.
- Added native mouse/stick direction integration with ellipse-based card selection, a 20% center dead zone, and three-degree hysteresis.
- Pinned selection during code entry and arbitrated pointing against discrete navigation.
- Removed the earlier five-kind allowlist in favor of validated mission-owned entries and native definitions.
- Retained native availability handling; scrambled codes were still unsupported at this stage.
- Added 1–16-entry layout, ownership, constructor, pointing, and descriptor tests. A live crash on opening prompted the R10/R11 corrections.

## R5–R8 — Early Selection Prototypes — Pre-public, partial history

- The retained changelog groups early work as selection proofs of concept, owned native UI, pointing, and native HUD-context fixes; individual R5–R7 changes are not preserved sufficiently to assign them to exact revisions.
- Through R8, activation was limited to five captured/validated stratagem kinds: 3, 136, 4, 25, and 33.
- R9 notes record that R8's activation path had been confirmed in-game, including Autocannon, and that its alignment fixes were retained.
- These were development prototypes, not public supported releases.

## R1–R4 — Early Drawing Work — History unavailable

- The retained research refers to a preceding **Drawing POC4**, from which the selection candidate inherited layout/vertical calibration and addon identity.
- The available repository does not establish a reliable per-revision R1–R4 change list or prove that the drawing-POC numbering maps directly to these release numbers. No individual changes or dates are asserted here.

## Sources and scope

- [Published releases](https://github.com/HWG90/DiversBestFriend/releases) and their UTC publication metadata.
- [Existing changelog at Canary R33](https://github.com/HWG90/DiversBestFriend/blob/canary-r33/CHANGELOG.md).
- [Native selection research at Canary R33](https://github.com/HWG90/DiversBestFriend/blob/canary-r33/native-selection-poc/RESEARCH.md).
- [Native wheel development notes at Canary R33](https://github.com/HWG90/DiversBestFriend/blob/canary-r33/native-selection-poc/EMOTE-WHEEL.md).
- [Commit history through Canary R33](https://github.com/HWG90/DiversBestFriend/commits/canary-r33/).

Historical failures and superseded approaches are retained to explain why later revisions changed. Unrecorded early revision details have not been invented. This changelog covers documented user-facing behavior, fixes, packaging/documentation changes, and material validation limits through R33; it does not claim new live-game validation.
