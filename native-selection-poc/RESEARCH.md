# Native Stratagem Radial: selection and pointing

This candidate extends Drawing POC4 without replacing the exporter. Same addon
resource and manager GUID means users replace their drawing addon. Source is
kept separately to preserve the last drawing-only package and test results.

Native input evidence comes from the supported captured game image and
`stratagem-input-probe/captures/five-stratagems-v2.log`. Releases through r8
supported only kinds 3, 136, 4, 25 and 33 validated by that capture. r9 expands
to mission-owned cards with valid native definitions, as documented below.

## Input mechanism

The POC invokes `0xA900D0` as `void(uintptr_t component)` on the normal Lua
update thread. That function takes the stratagem input component in RCX,
reads evaluated direction actions, appends a direction and invokes the native
matcher `0x66D8C0`, then runs its normal input feedback path. The return value
is unused by its existing caller at `0xA8EE93`.

One direction action byte is set to 1 during the call, then restored to 0
synchronously. All four directions must already be zero. The local avatar
component is +0x8D0 in its 0x1238-byte record. Direction bytes are at
manager+slot*0xA7AEC+0x4118+32*action; left=1, right=2, up=3, down=4.
Directions are supplied 70ms apart. There are no OS-generated key events,
executable hooks, direct matched-ID assignments, or calls to throw/spawn paths.

The subsequent ordinary game update handles the matched component and normal
beacon equip transition. This is deliberately not a claim that calling the
matcher alone equips a beacon. The candidate must be tested in-game.

## Ownership and guards

- PE timestamp 1790161983, signatures for drawing, input handler, append/match
  call site, local avatar mapping, card payload index and context-to-peer code.
- Mirrors native FD9BA0 local-network-index lookup; confirms the avatar hash
  lookup agrees with the local unit and input-component owner.
- Native gameplay mode, native menu flag, validated HUD tree, menu-active bit
  from A8E780, and foreground game window required.
- Context-to-peer lookup mirrors 606C90 and must match the local session and
  an existing mission payload, avoiding the native matcher's missing-record
  dereference. Payload membership is checked before starting.
- Rejects code scrambling (avatar+0x11B8), partial/manual input, changed owner,
  changed card, closed menu, unavailable bindings, and sequences over 3 seconds.
- Live code definitions are bounds-checked inside the settings allocation.
  Native matcher remains responsible for code and availability rejection.
- Input prefix/count and final matched kind are checked after every native
  handler call. Matching is logged separately from actual successful equip.

## Card mapping correction

Card+0x36F8 is cached entered-arrow progress, NOT a stratagem kind. The earlier
drawing notes inferred its meaning incorrectly. 0x1837B14 sets RSI to the
input component, and 0x183856B copies its count into +0x36F8.

The card's +0x3748 index (read at 0x1836582) identifies its local mission
payload entry. This POC reads the kind from payload+0x188+entry*0x30.

## Controls and validation

Mod Bindings Menu v2 registers Next, Previous, Confirm as native saved actions.
Documentation checked at https://github.com/CowboyBingus/ModBindingsMenu .
The raw README endpoint returned stale v1 docs; the repository page exposed
the v2 API, arbitrary labels, automatic slots, and native action evaluation.

Highlight is a card-scale change from 0.8 to 1.0. Release cancels, rather than
confirming. Existing POC4 layout/vertical calibration is retained.

## r9: independent cards and native pointing

r8's activation path has now been confirmed in game by the user, including
Autocannon. r9 retains that path and the alignment-4 fixes. Its new rendering
and pointing are candidates for live validation, not yet verified in game.

- `18358D0(card, vec2 position, vec2 anchor, vec2 pivot, uint32 style,
  uint32 index)` constructs each independent card. The vanilla call at
  `1833440` supplies style `226` and sixteen indices. Storage is zeroed,
  aligned FFI memory, retained by the update closure. No live widgets are copied.
- `1446840` constructs the new list root; `144C5C0` attaches it under the
  same content container as the original. Scalar root geometry is mirrored
  so the existing centering and saved vertical offset remain applicable.
- `1836510(card, float dt, uint32 context, payload, float width, float fade)`
  updates the new cards' content. The list updater is deliberately not called;
  it also performs native list-specific layout/state operations.
- Only the duplicate addresses reach the radial layout controller. The
  original top-left list continues its normal native update and draw path.
  Closed/disabled menus hide the duplicate root. Reopening reuses its storage.
  A changed HUD invalidates old pointers. Uncertain detached generations are
  retained, bounded to eight, rather than freed while native links may exist.
- `182B5C0(state, localInputOwner, float dt)` is the native wheel's direction
  integrator, called at `182A8E0`. Local input owner is avatar manager + `150`
  + local index * `A7AEC`. It resolves group 3 actions 6/7/8/9 through `585B80`,
  not by assuming the action IDs are the evaluated-array indices.
- The native helper handles device-dependent integration, clamping and
  sensitivity. An owned `1D00`-byte buffer holds its state. One disabled wedge
  lets it integrate direction without selecting any native wheel item.
  Binding readiness is checked before its internal dereference. The helper
  sets the normal radial-input flag at `*(346D560)+1A9`; native code clears
  that flag at `127A353`. No OS cursor movement or controller API is used.
- Lua maps this vector to actual ellipse card angles, with a 20% dead zone
  and three-degree hysteresis. Stick-center clears a pointing highlight.
  Discrete navigation persists until pointing changes. The selected code is
  pinned while entering; pointing cannot retarget an active sequence.
- The five-kind allowlist is removed. Mission membership, bounded descriptor
  addresses, matching descriptor ID, and direction-array validation still
  gate activation. Scrambled codes remain unsupported; game matching decides
  readiness and availability. No direct selected-ID or throw write is added.

New fixtures cover all 1–16 card angle layouts, dead zones, hysteresis, dynamic
descriptors, pointer/confirm arbitration, constructor arguments, duplicate
ownership, reopening and stale HUD rejection. Native calls are mocked in the
fixtures; actual input delivery, camera behavior and drawing need live tests.

## r9 crash and r10 correction

User reported a CTD on opening the stratagem menu. The r9 log retained
`status=native menu closed`, `pointing=nil`, and no first-open observation.
Windows Application events on 2026-09-27 at 16:21 recorded helldivers2.exe,
exception C0000026, ntdll.dll offset 1D3DF. That event is not a native call
stack and does not identify which r9 call failed. No readable crash dump was
available. Do not describe the crash location as established.

Inspection found r9 omitted the native widget resource-context scope:

- `1446975` reads the current context stack from `*(347CE90)+2C5BC`, defaults
  to index zero if empty, then assigns widget+F8 to manager+index*3698.
- Native HUD initialization at `12F0974` explicitly pushes context five.
  r9 called constructors from a Lua callback without supplying a scope.
- r10 derives the required context from the original list's +F8 pointer,
  validates it against the thirteen native contexts and its renderer pointer,
  then uses `12EF4B0(manager,index)` and `12EF4D0()` to bracket construction
  and update. It checks stack capacity, active context, new widget +F8 values,
  and restoration after both successful callbacks and Lua errors.
- FFI widget storage is explicitly aligned to sixteen bytes and surrounded
  by canaries. r9 guaranteed only eight-byte alignment.
- `NativeStratagemRadial-native.log` records first-pass call boundaries and
  closes the file before entering each new native stage. It distinguishes
  root construction, each card constructor/update, root attachment, pointing
  binding lookup, the pointing reader, and layout.

The missing scope is a confirmed implementation defect; its responsibility
for the reported CTD remains a hypothesis until a live retest. r10 is a fix
candidate with diagnostics. r8 remains the last user-confirmed working build.

## r10 disabled / r11 address correction

The live r10 log reported `UI context manager unavailable`, immediately after
`first open snapshot accepted`. No constructor or pointing call was reached.
The context-manager RVA was transcribed incorrectly as 348CE90. Both captured
instructions independently resolve to 347CE90:

- Constructor: 1446853 + 7 + 2036636 = 347CE90.
- Context pop: 12EF4D0 + 7 + 218D9B9 = 347CE90.

r11 corrects this single runtime address. The duplicate fixture now derives
its pointer slot from the native instruction bytes instead of repeating the
adapter's constant. The previous fixture repeated the typo and missed it.
Arsenal GUID/schema remain stable; release name, runtime and ZIP are r11.
This resolves the observed early guard failure; live rendering/pointing and
the earlier crash correction remain unverified until retested.

Run build_poc.py, then use run_lua.py on test_selection.lua and tests/*.lua.
Run tests/test_package.py for archive/resource/source validation. Fixtures use
isolated LuaJIT and simulated native memory/callbacks; they cannot establish
native ABI safety, engine thread timing, or actual in-game beacon equip.

## r12: Maelstrom descriptor alignment

User confirmed r11 drawing, pointing, confirmation and original list working.
A later Maelstrom attempt (kind 50, captured code 432343142) logged a pointer
rejection at its definition table slot, value 0x25841092EA4, alignment 8. This
is 4 mod 8. r12 accepts alignment 4 for the packed definition record only;
object pointers remain alignment 8 and all definition bounds/ID/code guards
remain. The fixture reproduces this alignment and all nine direction pulses,
plus rejects misaligned, out-of-bounds and wrong-ID descriptors before input.
The fix needs a live Maelstrom retest.

## r13: mouse radial / keybinding list

Mod Options choice `native_stratagem_radial.selection_mode` uses index 1 for
Mouse - radial (default) and 2 for Keybindings - list. The existing enabled,
offset and binding IDs are preserved. In mouse mode only pointing and Confirm
select a card; no default card is armed before pointing. In list mode the
original rows remain positioned by the game and the selected row is scaled
by 1.10 relative to its native scale, with conditional restoration. The
duplicate radial and pointing reader are not used in list mode.

The native radial reader already sets `*(346D560)+1A9`. Captured camera input
code tests this flag at 1286756 (substituting the native neutral input vector)
and 1289912 (skipping the regular look-input path). r13 explicitly acquires
this native gate while focused mouse selection is active. The game resets it
each frame at 127A353; the addon reasserts it while capturing. Closing, losing
focus, switching modes, disabling or failing releases only a gate it acquired,
and only if its owner pointer remains current. An existing native capture is
not claimed/released by the addon. No executable code is patched.

Mode changes restore both displays and cancel selection before the new mode
runs, suppressing confirmation held across the switch. Fixture checks cover
mode registration, input/display separation, switching during code entry,
held-confirm suppression, focus/close/disable cleanup, native gate ownership
and native list-scale restoration. Live camera timing and the new mode UI
still require in-game validation; isolated mocks cannot establish those.

## r14: list navigation follows native display order

User confirmed mode selection works and reported navigation jumping between
rows. The snapshot enumerated cards by storage/payload index; selection used
that enumeration directly. Those indices do not encode the displayed order.

Snapshots now read each original card's settled Y position from animation_b
(+3740/+3744). List mode sorts a separate eligible array by descending native
Y (top to bottom), with deterministic ties. Next advances one row and wraps;
Previous reverses and wraps. Tracking the selected widget address preserves
the selected item if native layout reorders, and confirmation still uses its
actual kind. Radial slot order remains unchanged. Using the target position
avoids sorting on transient opening animation or highlight scale.

Fixtures cover deliberately scrambled slots, gaps, both wrap directions,
native reorder, confirmation identity, one/zero rows, and radial separation.
Native adapter, mode integration, selection and package checks pass. The new
navigation order still needs a live retest.


## r15 native emote-style wheel

Implemented shared wheel presentation, native cursor/sector state and eight-slot
paging. See EMOTE-WHEEL.md for RVAs, ownership and current validation limits.


## r16 experimental mode and old rows

r15 was user-confirmed working. Added Experimental as mode 3, preserving mode
1/2 values and the stable addon GUID. Experimental layout selects the old
copied-row radial or native eight-slot baseline. Expanded wedges were explicitly
deferred. See INSTALL.txt and EMOTE-WHEEL.md for behavior and validation.


## r17 expanded wedge mode

Implemented mode 4 with independently allocated native sprite/transform slots,
up to sixteen entries, angular selection, cursor and center-caption reuse.
See EMOTE-WHEEL.md for allocation, geometry evidence and validation limits.


## r22: viewport centering on the native GUI plane

The inherited 4x4 matrix begins at widget +0x64. Native GUI coordinates
use X/Z, with Y reserved for depth. The old adjacent-pair extraction read
X/Y; observed vertical scale 1 and translation 0 were depth values, hiding
the real inherited vertical placement. Project float indices 0,2,8,10,12,14
into the existing 2D affine centering calculation. This applies the same
viewport-midpoint/inverse-list-transform calculation to both screen axes.

Captured transform routine 0x144A3E0 stores local vertical scale (+0x18)
at rsp+0x20 (0x144A4D3/0x144A5B6), then applies it to the third basis
(rbp+0x70 at 0x144B60A/0x144B60F). The composed matrix is stored to widget
+0x64/+0x74/+0x84/+0x94. See research/transform-r22.txt.

The isolated native adapter fixture now stores complete X/Z matrices with
a distinct depth axis and checks both screen coordinates over viewport
heights, scales, translations and mixed bases, plus a singular screen plane.
Offset defaults to zero; the existing option ID and saved preferences remain.
The user already reset their offset to zero. Live rendering remains to test.


## r23: expanded-wedge contrast and blur investigation

Expanded backgrounds previously used RGB (0.5,0.55,0.6), alpha 0.3. Two
independent percent sliders now control RGB darkening and alpha, defaulting
to darkness 70 / opacity 75. Selected yellow stays at least 0.95 opaque,
icons are unchanged, and empty-sector alpha retains the 0.08/0.3 ratio.
Original appearance is darkness 0 / opacity 30. No extra native calls or
widget allocations are introduced.

Row constructor 0x1835BB9 invokes background constructor 0x18166C0 with
flag 1. It selects material 0x597EC34016C4F4BE (alternative
0x2391483ABBDA5A58). Local material metadata has zero texture bindings for
both. Expanded sector material 0x9C16BF1BB2D8DE88 has one binding,
0x3AA8B87E, referring to the same-hash texture. Shader identifiers differ:
row 0x6830E3B8 / alternative 0x05A4CA9E, sector 0xBA25DE35. The row
material cannot accept the existing sector mask through its texture table;
applying it directly is not a demonstrated wedge-clipped blur solution.
Blur is deferred until a suitable native masked material or clipping path
is established, instead of exposing a speculative toggle.

Local read-only DSAR inspection followed the public format descriptions in
https://github.com/xypwn/filediver/blob/master/patterns/dsar.hexpat and
https://github.com/xypwn/filediver/blob/master/stingray/slim_edition.go .
No extractor, game resource, capture, or new dependency is shipped.


## r24: cooldown/delivery presentation

Read a bounded 0x44-byte block from original card+0x3718 after matching its
cached kind (+0x374C) to the local mission entry. Native state +0x3758 == 3
selects incoming seconds +0x3718; state 4 selects cooldown +0x3720. The
native update computes special cases itself, including shared Reinforce
(18368CC..1836908). Reject unknown kinds, other states, unreadable blocks,
nonfinite, expired, or over-one-day values. Round positive seconds up for
display; this is not a generic readiness or charges test.

Native and expanded icon caches include timer kind, not seconds, so the
material changes only when its presentation state changes. Decode the native
channel-mask material and desaturate A,R,G,B vectors' RGB components while
preserving alpha, even if the user's normal icon mode is raw. Dim timed
icons to 0.30 (0.55 selected); preserve the yellow selected wedge. Do not
remove timed entries, reorder them, reset paging, or bypass the matcher.

The owned wheel's +0xF50 hint is type 7, constructed by 143AFA0 at 182A1EE.
Reuse that existing object; do not run native emote gameplay activation.
Set the native row timer template 0xA851371B with 143BF90 and minute/second
parameters 0x51D1E697 / 0x4583B0D3 through 143C9D0 (uint32 parameter,
int32 value, uint32 formatting flags 0x3020). Native row evidence is
18360F2..18360FA and 18377E2..1837832. Position the hint at local (0,-75)
under the center name; keep it hidden when no timed item is selected, or in
copied-row mode. New call signatures and layout witnesses have byte guards.

Tests cover both timer states, shared-Reinforce cached state, invalid/expired
values, stale kinds, grayscale alpha preservation, raw-mode restoration,
minute rollover, expiry, expanded selection preservation, and entry routing.
Mocks do not establish native renderer safety or visual placement; live
verification of the hint text and positioning remains pending.

## R25: optional release selection

A8ED4E..A8EDAC reads native action 5:0 and trigger types 2/9; A8EDA9 permits a matched component to survive release. A8E850 is the guarded native opener (A8E780 active test, A8E8C0 eligibility, A8F570 open). Release detection uses a sampled falling edge with a 250 ms freshness limit, unchanged HUD/local avatar, clean component, and no native UI stack. Closed sessions are resumed through this opener. Existing begin/advance validation and direction restoration are reused, completing at most 12 directions synchronously so the ordinary update can equip the match. A8FB50 closes a reopened session on failure. No matched ID or avatar flag is directly written. This new native call path and same-frame input timing require live testing; fixtures alone cannot verify renderer/gameplay safety. The option defaults off.

## R27: paced native Hold candidate

R26 live logs reported full matches (kind 3) without successful equip, so a match alone did not validate the one-frame release path. R27 queues one direction per interval and temporarily asserts the evaluated native action 5:0 in both the controls owner's action array (+808+32*(97*5)) and the peer-owned local avatar copy. The frame job revalidates menu/owner/UI before continuing; premature native closure cancels rather than reopening/replaying a partial code. Tracked held bytes are cleared on the next update after a final match and on cancellation, rechecking owners before cached addresses are used. These are transient native action bytes, not saved bindings. Game evaluation may overwrite them before gameplay consumes them; live verification of frame ordering and hold persistence is required. Logs explicitly distinguish early closure, code progress and cleanup. No claim of successful equip follows solely from a matched kind.

## R28: native Press-mode latch

R27 live logs consistently cancel before the first queued direction with "Native menu closed before release code completed". Evaluated-byte writes did not persist through native updates. Read-only inspection of the running supported build confirmed live map key 0x50000 (Display Stratagem List), three 20-byte records, with Hold triggers in two records and a pre-existing Press trigger in the third. Format/offsets follow CowboyBingus ModBindingsMenu v2: controls owner 347CF18, live binding map +686800, 256 buckets of 328 bytes, {code,count,16 mappings}; trigger in flag bits 16..19 and dword +8. Only button Hold/LongHold 2/9 records are temporarily converted to Press 0. Pre-existing Press mappings are untouched. The native updater A8ED4E..A8EDAC compares Hold-ness with action activation; Press plus released action keeps its menu session active. R28 also updates the two cached trigger fields for the transition frame.

A lease restores exact original records by current bucket/index only when they still equal the installed values. Config edits cancel the job; already restored or changed records are not overwritten. Defaults maps and binding files are not written; the addon never calls Apply. Partial acquisition rolls back, and cleanup re-resolves owners before restoring cached fields. Native action key/button assignments do not change. Tests cover these mechanics, but live menu latching and native equip remain unverified until the user tests R28.

## R29: completion handshake

R28 logs show all directions and a matched kind followed by unconditional restoration on the next addon update. This did not prove native equip completion; the user reports cancellation. Native A8F126..A8F39D can defer final consumption while weapon state changes, eventually calling A8FB50 through its native branches. R29 retains the latch until the local menu-active flag clears, logging count/matched/queued (+0/+14/+2C) while waiting. It rejects a lost match while the menu remains active. A two-second post-match deadline prevents indefinite latching. No equip function or matched ID is forced. Native close is a lifecycle acknowledgement, not proof a beacon was equipped; live verification is still needed.


## R30: pending weapon request on release

Read-only comparison of working Confirm and failing release showed avatar+0x424
remaining at requested slot 5 for Confirm, but changing to slot 1 at physical
menu release. The actual weapon was still slot 5. Native opener A8F570 checks
the actual weapon at A8F828 and skips its slot request if already 5. Thus the
pending primary request survived reopening and cancelled the briefly active beacon.

R30 validates the owner at avatar+0x420 and calls native A93E90 with that
component and slot 5 only if the requested slot differs. This is the same call
made by the opener at A8F88F; it is not a weapon-ID write or a spawn operation.
Signatures guard both the function and these opener sites. The comparison
explains the failure; the patched behavior still requires a live test.


## R31: native scrambled-code resolution

The old activation guard rejected any nonzero avatar+0x11B8. That field is a
seed, not per-kind effect membership. Matcher 66D8C0 calls A10820 with the
manager at game+33264B0, a uint32 output, local avatar key, original kind, and
two null optional outputs. A result other than UINT32_MAX selects definition
(((kind + seed) modulo 2^32) modulo 149) + 1; otherwise it uses the original
definition. See 66DCF0..66DDF4 and 66E08A..66E161. A10820 checks the kind's
category and effect volume membership using the local position.

The adapter validates the original definition and local position-map lookup
at game+3326508 (table+40, records+68, stride308, position+2E0) before calling.
The selected identity remains unchanged; only its input sequence is resolved.
Every input rechecks the resolved sequence, so changed effects cancel without
sending another stale direction. No seed, effect, availability or matched-kind
field is written. Release cancellation restores its latch through existing
cleanup. Native availability rejection remains authoritative.

Fixtures cover nonzero seeds without active effects, shifted code lengths,
entering/leaving effects, both selection paths and release cleanup/recovery.
The reported spire and scrambler encounters still need live verification.


## Canary R32: native detail feedback

Reuse the existing independently constructed sixteen-card duplicate container.
For native/expanded wheel feedback, update it with the original full snapshot
and validated current input context, then show only the row matching selected
entry and kind. The existing 1836510 native updater supplies status text,
countdown and input arrows; no availability enums or translated text are guessed.
Place both animation endpoints and position at the same projected wheel center,
with centered anchor/pivot and scale capped at 0.85 / 360-unit width. Restore
card visibility during normal prepare so switching back to Cards works.

Suppress the separate wheel caption/timer only when detail preparation succeeds.
Detail guard failure hides the copy and preserves the old caption/timer, without
disabling selection. Tests cover selection/empty selection, centered transforms,
mode switching, options and original-widget isolation. Live rendering is pending.
