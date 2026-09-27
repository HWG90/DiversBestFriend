# r15 shared native wheel implementation

The mouse mode now constructs an independently owned native shared wheel
(18298F0) in the original list's validated HUD resource context. It attaches
the new widget to that list; none of the original cards are moved or replaced.
The eight slots are populated from the active mission cards, ordered by native
settled row Y. Next/Previous wrap across pages of eight, including a partial
last page. Membership changes reset the page; page changes gate held Confirm.
Paging is blocked during a running stratagem code sequence.

## Presentation and input evidence

- Constructor's mode 1 and emote mode 2 use the same ring  AA25349FCE5D3EB3,
  sector 9C16BF1BB2D8DE88, highlight B90233362AED21CC and -22.5 degree rotation
  (182CC1C / 182CD23). Mode 1 initializes static content (182BC6A), avoiding
  the mode-2 loadout lookup during construction. Both have eight slots.
- Stratagem definition +B0 provides the icon texture (183A1E5); +28 provides
  the base localized name (66D554). Reads use the same bounded settings range
  and 4-byte definition alignment as the proven input adapter.
- Slots at +1208+i*158 use the native wheel sprite material and texture setter
  1450230. No live widget/resource pointers are copied.
- Native direction reader 182B5C0 now consumes the actual owned wheel's state:
  eight enabled-slot bytes +1CC8, count +1CD4, angle offset +52C, cursor +1CE8,
  and selected sector +1CD8. The reader retains native mouse integration,
  stick direction and native sector mapping. Empty sectors clear selection.
- Native cursor sprite +B40 moves by (vector.x*240, vector.y*240), exactly as
  182ADB8..182ADEF. Selected wedge +5E0/+890 rotates by slot*45-22.5 degrees,
  matching 182A932. Center label +C98 uses the selected stratagem name.
- Full wheel update/activation is NOT called: those dispatch other gameplay
  actions. Existing explicit stratagem Confirm, native validation and camera
  capture remain in use. List mode remains independently selectable.

Storage is 16-byte aligned with 16-byte canaries around 1D00 bytes, pinned
while linked. HUD identity and parent are checked before updates; uncertain
old linked generations remain pinned. Resource scope unwinds on Lua errors.
New native entry points/layout witnesses have captured signature guards.
Native-call checkpoints are persisted before first constructor, attach,
texture, highlight and label calls for diagnosing a possible game crash.

## Validation and limits

Isolated LuaJIT fixtures cover construction ABI/scope, paging (16 and 9 items),
held buttons, busy paging, empty slots, native cursor-state plumbing, wedge
rotation, original-widget write exclusion, offset, reuse and stale ownership.
Existing selection/mode/camera/list-order tests also pass. These fixtures mock
native functions and do not establish renderer compatibility or CTD safety.
The first in-game test is still required.

Eight slots are a native presentation constraint; there is no sixteen-sector
write. Pages are switched with existing Next/Previous bindings. Page number
is currently exposed in addon status/logs, not an on-screen page counter.
Names use base definitions; mission-specific name substitutions are not yet
mirrored. The original list remains available for cooldowns and detailed data.
Saved vertical offset retains the earlier wheel center adjustment.


## r16 mode integration

User confirmed r15 working perfectly in-game. Its eight-slot behavior remains
mode 1; the keybinding list remains mode 2, preserving saved numeric values.
Mode 3 is Experimental, with a separate experimental_layout choice: copied
native row radial (default 1) or the eight-slot baseline (2). Expanded sectors
are deferred at the user's request.

Copied-row mode uses the established duplicate_cards and radial.controller
paths. It samples the native reader's independent integration state and uses
the prior ellipse pointing logic, so all sixteen rows remain reachable. The
shared wheel is prepared only to reuse its native cursor marker; ring, wedge,
name and wheel icons are suppressed by cursor-only drawing. Its normal drawing
restores those properties when returning to native wedges. Experimental layout
changes cancel active sequences, restore previous widgets and gate held Confirm.
Tests cover routing and cursor-only/normal transitions; live r16 test pending.


## r17 fourth mode: expanded wedges

Expanded wedges is saved mode 4. Modes 1-3 and the r16 Experimental layout
setting retain their numeric values. Expanded mode does not page: it shows
all active mission rows (up to 16), using max(8, entry count) sectors.

`expanded.lua` owns 4F10 bytes plus alignment/canaries. A 110-byte root is
followed by 16 slots, each padded to 4E0 bytes: turn container (+0), stretch
container (+110), wedge sprite (+220), icon sprite (+380). Containers use
1446840; 158-byte sprites use 143EAB0. Every child is constructed under the
validated HUD resource scope; links/context and outer canaries are checked.
The native wheel's fixed arrays are neither extended nor indexed above 7.

The existing native 45-degree sector resource 9C16BF1BB2D8DE88 is assigned with
144F800. Each wedge is pre-rotated -22.5 degrees about its zero pivot, narrowed
by Y scale tan(pi/N * .97)/tan(pi/8) in a separate centered parent, and rotated
by its outer parent to 90-(slot-1)*360/N. The .97 factor leaves a small gap.
Native rotation-pivot setter 14481A0 writes +34/+38; the captured transform
144A514 onward uses those fields and composes with the parent matrix at
144A5E9 onward. Icons remain unscaled siblings at radius 185. Sprite order
uses 14491F0; tint uses 1448690; selected wedges/icons brighten.

This tangential scaling keeps the angular boundaries correct but can make
outer arcs differ from a perfect circle. It is deliberately a separate
experimental rendering path; it does not replace the confirmed stock ring.

The proven native reader integrates mouse/stick into its independent bounded
state. Lua maps its vector into the same N angular sectors (20% dead zone).
The shared wheel supplies only its cursor at radius 240 and center caption;
its fixed ring, icons and selected-sector graphics are hidden. Caption accepts
a selected kind directly, so slots 9-16 do not index native wheel arrays.
Confirmation stays with the proven stratagem controller. Count/membership
changes reset pointer selection and gate held Confirm; active jobs cancel.

Isolated tests include 172 geometric/selection checks over 0-16 entries,
33 container / 32 sprite constructors, resource scope/ownership, transformed
width, selection and confirmation of slot 16, shrinking membership, empty
sectors, reuse, stale HUD rejection and switching all four modes. Native calls
are mocked; rendering/CTD safety still require an in-game check. First-pass
constructor, texture and highlight boundaries are persisted in native logs.


## r18 artwork orientation correction

Live r17 screenshot shows the cursor at NW Autocannon and the center caption
correctly saying AUTOCANNON, while its highlighted wedge is SE. This isolates
the half-turn error to the native sector artwork, not vector/slot selection.
The wedge's local rotation is now 157.5 degrees instead of -22.5, centering the
art's 202.5-degree bisector on +X before tangential scaling and slot rotation.
Icon coordinates, native pointer integration, angular selection and Confirm
are unchanged. Adapter tests independently transform the calibrated art ray
through the recorded native rotations/scales and check it faces each icon.
Live verification of the correction is pending.


## r19 native stratagem icon channel colors

The generic emote material exposed the icon texture's red/green mask channels.
Full-color stratagem icons (default on) now selects material AF73E09D6D725398,
used by the original list's icon sprite constructor at 18398CC. It applies the
same channel uniforms as 183A1FB..183A25E: 28723F4D from live category palette
3318040 + descriptor.B8*16; 851FD4FD from 21E2D30; 10C353AF from 21E2D60.
Reads are bounded (category <16, 16-byte finite 0..1 colors) before assignment.
The widget/material functions 144F6E0 and 14498C0 have signature guards.

Both wedge renderers invalidate their content cache when the toggle changes.
Full-color icons retain white vertex tint even when selected; wedge highlights
still turn yellow. Off restores the previous generic emote material. Copied
rows/list remain under the native card renderer. New material integration
requires an in-game color check; isolated tests cover material/parameters,
off/on restoration, invalid palettes and option routing.


## r20 correction: native rotation handedness, not just a half-turn

The r18 screenshot disproves the r18 orientation model: selecting W Gatling
shows the highlighted wedge N. Together with r17 selecting NW Autocannon and
showing the wedge SE, the observations establish clockwise native rotation
and an unrotated sector bisector at +67.5 degrees. Stock pre-rotation -22.5
points UP; the r17 implementation incorrectly assumed it pointed RIGHT.

The local wedge rotation is now +67.5 native degrees, centering it on +X before
Y compression. The outer parent rotates by NEGATIVE mathematical icon angle.
This corrects both handedness and phase, including cardinal and diagonal slots.
Input vectors, icon positions, selected names and confirmation are unchanged.
Tests independently reproduce BOTH previous screenshots, then test corrected
native transforms against icon positions for all 8-16 sector counts. This
supersedes the r18 notes above. Live retest is still required. r19's full-color
option is retained; the inspected runtime log still identified the r18 build.


## r21 menu consolidation

Three selection modes remain: Native wheel (1), Keybindings/list (2),
Experimental (3). Experimental layout 1 is copied Cards; layout 2 is Expanded
wedges. The former mode 4 routes through the same expanded renderer after
migration; its rendering and input math are unchanged. The duplicate native
wheel choice in Experimental is removed. Old experimental layout 2 now means
expanded wedges, as labeled in the new options.

Mod Options Menu's saved choice decoding would discard a saved 4 after reducing
the choice count. The addon reads only the legacy selection value from its
existing ModOptionsMenu.values file before registering, then uses the documented
menu.set API to persist mode 3/layout 2 after registration. It does not edit the
settings file itself. Migration is one-time and does not override later edits.
