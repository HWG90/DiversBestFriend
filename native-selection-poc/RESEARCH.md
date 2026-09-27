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
