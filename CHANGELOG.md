# Changelog

## R29 - Completion Wait

- Wait for the native menu to finish after a matched code before restoring Hold behavior, instead of restoring one frame later.
- Keep the latch during the native equip transition, with a two-second completion timeout.
- Log native menu/count/matched/queued state to distinguish code match from completion.
- Skip further pointing/context preparation during completion to tolerate native menu/HUD close timing.
- Regression tests pass; the reported post-code cancellation still requires in-game retesting.

## R28 - Release Latch

- Replace R27's overwritten evaluated-button hold with a temporary Press trigger for Display Stratagem List in the native live binding map.
- Keep configured input pacing, then restore the original trigger after completion or cancellation; no key/button reassignment.
- Guard exact mapping restoration, partial setup rollback, user edits, relocated maps and owner changes.
- R27 logs confirmed early native menu closure. R28 fixtures pass; in-game validation is still required.

## R27 - Release Hold

- Replace the same-frame release burst with a paced job that temporarily holds the native menu action through completion.
- Apply Input interval to release sequences as well as Confirm; keep the hold until the update after the final match.
- Freeze the selected item and native wheel page during release input. Clear held actions on cancellation, timeout, focus loss or errors.
- Report premature native closure explicitly. This is a test candidate; in-game hold persistence is not established by fixtures.

## R26 - Polish

- Rename options and bindings sections to Diver's Best Friend and simplify setting descriptions.
- Rename new logs to DiversBestFriend.log and DiversBestFriend-native.log; expose DiversBestFriend as a runtime alias.
- Preserve the mod GUID, resource identity, existing runtime alias, saved settings and binding IDs.
- Refresh installation instructions and package metadata. Select on Release stays off by default and still needs live validation.

## R25 - Select on Release

- Configurable Confirm input interval: 0-250 ms, default 70 ms, fixed per sequence with a scaled timeout. Release sequences remain immediate.
- Optional, default-off release selection for all radial layouts using the native Hold menu action.
- Default controls and list behavior remain unchanged; explicit Confirm suppresses duplicate release.
- Guards stale frames, UI overlays, ownership changes and manual input. Native opener resumes closed input sessions and rejection closes reopened menus.
- Isolated tests pass; native reopening and controller timing await in-game validation.

## r24 - Cooldown Indicators

- Gray/dim Native wheel and Expanded wedge icons while the native HUD reports cooldown or incoming delivery.
- Reuse the owned wheel hint for a selected-item minute/second countdown beneath the name; restore colors at expiry.
- Preserve selection, paging, native availability checks, and existing list/card timers.
- Validate native cached-kind identity, timer state, finite bounded seconds, and stale-data clearing.
- Add guarded native formatted-label setters and regression tests for gray palettes, raw-mode restoration, minute rollover, and expiry. In-game visual validation remains pending.

## r23 — Wedge Appearance

- Add independent Expanded wedge darkness and opacity sliders, each 0–100% in 5% steps.
- Darker defaults: 70% darkness, 75% opacity; old appearance available at 0% / 30%.
- Preserve yellow selection, icon visibility, and fainter empty sectors. Other layouts are unchanged.
- Investigate native row-card blur: its material has no wedge-mask texture binding, so a direct material swap is unsuitable. No nonfunctional blur toggle is exposed.
- Regression checks cover appearance endpoints, setting updates, invalid values, and selection preservation. In-game appearance still needs validation.

## r22 — Viewport Centering

- Correct native GUI matrix projection from X/Y to X/Z for automatic vertical centering across radial layouts.
- Default vertical adjustment to zero while preserving saved values.
- Add centering telemetry and adapter regression coverage for both axes, HUD scales, viewport heights, and singular transforms.
- Initial publication as DiversBestFriend, with installation/development docs, credits, MIT license, and banner.
- Validation: isolated suite and deterministic packaging pass. In-game validation of the specific r22 placement correction remains pending.

## r21 — Experimental Layouts

- Three selection modes: Native wheel, Keybindings — list, and Experimental.
- Experimental layout switches between copied Cards and Expanded wedges.
- Legacy fourth-mode selection migrates to Experimental / Expanded wedges.
- Author confirmed expected behavior in-game.

## Earlier development

- r19–r20: optional native full-color icons and expanded-wedge rotation corrections.
- r17–r18: expanded-wedge prototypes; superseded alignment attempts.
- r15–r16: native emote-style wheel, native cursor tracking, and experimental layouts.
- r13–r14: keyboard list mode and consistent visual next/previous order.
- r12: Maelstrom confirmation supports four-byte-aligned native definitions.
- r5–r11: selection proofs of concept, owned native UI, pointing, and native HUD context fixes.

Earlier prototypes included crashes and broken drawing/selection. They are not presented as supported releases. The research notes preserve the development history.
