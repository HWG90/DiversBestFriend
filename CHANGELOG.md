# Changelog

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
