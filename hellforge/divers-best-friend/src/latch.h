/* latch: the Hold->Press lease of the stratagem menu's binding (R46 menu_latch.lua:1-87) and the slot hotkeys that use it
 * (R46 input.lua:283-364, and release.lua:13-55 for the shortcut's life).
 *
 * The lease. The player's menu binding (Display Stratagem List) is a Hold or LongHold: the game keeps the menu open only
 * while the key is held. A slot hotkey opens the menu itself, so while its code goes in the binding must act as a Press
 * (a toggle), or the game closes the menu on the next frame. Only the live binding map changes; the defaults and the
 * saved bindings are untouched (menu_latch.lua:1-3). latch_acquire:
 *   - the map is at controls + 0xa7ad0 (686800): a pointer to its bucket table, and at + 8 a u32 capacity that must be
 *     256; bucket i is at table + i * 328; Display Stratagem List's is the first whose u32 key (+0) is 0x50000, with a
 *     u32 record count (+4) of at most 16 and the records, 20 bytes each, from + 8 (menu_latch.lua:9-22);
 *   - every record whose u32 trigger (+8) is Hold (2) or LongHold (9) must be in the format R46 knows: (flags / 16) % 16
 *     == 4 and (flags / 65536) % 16 == the trigger, flags the u32 at +0. It becomes flags - trigger * 65536 with the
 *     trigger 0 (Press), its other twelve bytes kept (menu_latch.lua:64-74); other records are left alone. At least one
 *     record must qualify ("no Hold mapping", menu_latch.lua:76);
 *   - the two evaluated trigger dwords, the controls' (controls + 808 + 32 * 485 + 24) and the local player's menu
 *     action's (actions + 24), must read 0, 2 or 9; one that is not 0 is zeroed, so the frame in flight matches the Press
 *     mapping (menu_latch.lua:51-60).
 * Nothing is written until every check holds: no latch held; LATCH admitted ("Select on Release: <admission's
 * reason>"); `l` given ("local player unavailable"), its controls readable (GameLocal.controls != 0, and the pointer at
 * game.dll + DBF_RVA_CONTROLS readable with latch_init's base: "controls unreadable") and still that object ("controls
 * changed", R46 menu_latch.lua:10), the UI unobstructed (GameLocal.unobstructed, "UI obstructed"); the controls' menu
 * action byte (controls + 808 + 32 * 485) 0 or 1 (input.lua:314-315); the map, the bucket, every record's format and
 * both dwords. Each record is then swapped as its 20 bytes and each dword as its 4, with mem_swap under
 * MEM_OWNER_LATCH; when a swap fails, what was swapped is put back (latch_release(true)) and acquire fails.
 * Entries an earlier release could not write back are retried first (latch_release, valid when `l` is the player that
 * latch was taken for); when some stay, acquire fails ("the last menu latch is not restored yet").
 *
 * latch_refresh, every tick while the latch is held (R46's refresh, menu_latch.lua:45-61): the latch held with exactly
 * the journal entries it made (a mem_restore_all elsewhere, even one that left some, ends it: "menu latch restored
 * elsewhere"; the latch is no longer held and what is left is latch_release's), LATCH admitted, the same controls
 * object ("controls changed"), the same bucket table with the bucket's key still 0x50000 and each patched record's
 * index below its count ("menu binding changed"). Each patched record is re-asserted (memory's re-assert: the latch's
 * bytes stay, or are written again where the original came back; anything else is "menu binding changed", a write that
 * fails "menu binding could not be latched"); each dword must read 0, 2 or 9 and is zeroed again where it holds its
 * original; a dword that reads 2 or 9 for the first time is zeroed and journaled as at acquire (R46 does the same). A
 * record or dword the latch already holds gets no second journal entry. False with the reason when something fails: the
 * latch stays held as it is, and the caller ends it with latch_release.
 *
 * latch_release(avatar_valid) gives the lease back with R46's owner checks (menu_latch.lua:26-44), made again on every
 * call, so a retry honours them too:
 *   - when the pointer at game.dll + DBF_RVA_CONTROLS is no longer the latched controls object (or cannot be read),
 *     every LATCH entry is dropped without writing (mem_forget_all; R46 restores nothing then), with one log line;
 *   - otherwise, when avatar_valid is false (the player is not the one the latch was taken for), the actions + 24
 *     dword's entry is dropped without writing (mem_forget, one log line), and the rest restored;
 *   - otherwise everything is restored: mem_restore(MEM_OWNER_LATCH) (memory.h): each record and dword gets its original
 *     back while it still holds the latch's bytes; one the game already put back counts as restored; one someone else
 *     changed meanwhile is left alone and counted; one whose write failed stays journaled and counts, for the next
 *     latch_release (or acquire) to retry.
 * It returns how many entries were not put back, the dropped ones included. The latch is no longer held afterwards; what
 * it remembers (the objects and the player) stays until its last entry is gone.
 *
 * Slot hotkeys (R46 input.lua:355-364 with begin_latched, 298-353) live here rather than in entry.c because the lease
 * outlives the code entry: it is taken before the job and given back only once the game has closed the menu after the
 * code. entry.c runs the job itself (the job is `latched`; entry treats it like any other).
 *
 * entry_begin_shortcut refuses (false; the job ENTRY_FAILED with the reason, which is also copied to `reason`; nothing
 * written, no game function called) unless: no job is running and no shortcut is active ("a code is being entered"; the
 * job is then left as it is); slot is 1..4 ("invalid equipped slot"); ENTRY is admitted ("Code entry: <admission's
 * reason>"); the code-entry chain holds (GameView.local_ok; "local player unavailable"; the menu may be closed); the
 * local menu action is not down (the u8 at actions + 0, input.lua:289-291: 1 is "menu key held", neither 0 nor 1
 * "invalid menu action"); the UI is unobstructed ("UI obstructed"); the input component is clean ("close and reopen the
 * menu") and the four direction actions idle ("manual direction input"); the payload has 8 to 32 entries ("equipped
 * stratagems unavailable", input.lua:358); the slot's kind, the u32 of payload entry slot + 3 (input.lua:359-361), is
 * not 0 ("equipped slot is empty"; codes decides which other kinds have a code); and codes_read gives its code.
 * Then, in R46's order: latch_acquire (its reason); when the menu is not active, nat_open_input(component) must run ("the
 * menu could not be opened") and answer nonzero ("the game did not open the menu"); the view is read again with
 * game_read (the one passed in is stale once the menu opened, and stays so for the caller) and must show the same player
 * (manager, key and component: "player changed"; no chain: "local player unavailable"), the menu open ("menu closed")
 * and active ("menu inactive"); the weapon block (avatar + 0x420) must carry the local key ("weapon owner mismatch") and
 * a requested slot (u32 at + 4) of 1 to 7 ("invalid weapon slot", "weapon unreadable"); when that is not the stratagem
 * slot 5, nat_request_slot(weapon, 5) runs ("stratagem slot could not be requested") and the slot must read 5 after it
 * ("the game did not select the stratagem slot"). The slot request is never undone (R46). Last, entry_begin(job, the
 * fresh view, kind, interval_ms, instant, latched = true, now) (its reasons). Any failure after the latch was taken
 * calls latch_release and then, when DBF opened the menu, nat_close_input(component) (R46 begin_latched, 342-345);
 * when the view read again no longer shows the same player and component, release gets avatar_valid false and the
 * menu is not closed (a log line says so), where R46 restores and closes either way.
 * True: the job is ENTRY_RUNNING and the shortcut active.
 *
 * entry_step_shortcut runs a tick of the active shortcut in place of entry_step (it calls entry_step); with no shortcut
 * active it does nothing. While the job runs:
 *   - confirm_down (Confirm's level this tick: R46 release.lua:28 cancels on it) cancels it: "Confirm pressed";
 *   - for the same player, R46's hold_release (input.lua:365-373): the UI unobstructed ("UI obstructed"), the menu action
 *     not down ("menu key pressed"), latch_refresh (its reason); a failure cancels the job;
 *   - entry_step; a job that fails ends the shortcut.
 * Once the job is ENTRY_DONE the shortcut waits for the game to close the menu (R46 release.lua:28-43 with
 * release_complete, input.lua:380-392). Each tick, in R46's order, it is cancelled (the job turns ENTRY_FAILED with the
 * reason) when Confirm is down ("Confirm pressed"), when more than SHORTCUT_FINISH_MS (2000, R46 release.lua:51) passed
 * since the job was done ("the menu did not close"), or when the player changed ("local player unavailable", "player
 * changed"); then a menu no longer active ends it, done: the latch is released and the job stays ENTRY_DONE. While the
 * menu is still active it is cancelled when the component's matched (+0x14) and queued (+0x2c) kinds are both no longer
 * the job's ("the game dropped the stratagem"; "input component unreadable") or a hold check above fails. A shortcut
 * whose job is neither running nor done (cancelled by the caller) ends as cancelled.
 * Ending a shortcut always calls latch_release, with avatar_valid when the view shows the same player; a cancelled or
 * failed one then calls nat_close_input(component) when DBF opened the menu, the view shows the same player and the
 * menu-active bit, read again then (the view is stale once entry_step ran: the game may close the menu inside a handler
 * call), is set (R46 end_release, input.lua:374-379, which closes the menu whoever opened it; here only one DBF opened).
 * A done one never closes it.
 *
 * Portable C11: standard headers, memory.h, admission.h, native.h, codes.h, game.h, entry.h and the generated header.
 * Every game number is the generated header's. Writes only through mem_swap (MEM_OWNER_LATCH), game functions only
 * through native.h (open, close and request slot, gated by LATCH there; the input handler through entry). Not
 * thread-safe: only the game thread calls it. */
#ifndef DBF_LATCH_H
#define DBF_LATCH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "entry.h"
#include "game.h"

/* Starts a session: forgets the latch and the shortcut, without restoring anything (as mem_init forgets the journal:
 * call latch_release first when the latch is held). `game_dll` is where the controls pointer is read (0: unknown, and
 * then acquire refuses); `log` gets latch's own lines (NULL: none). */
void latch_init(uintptr_t game_dll, void (*log)(const char* line));

/* Takes the lease (see the top). False with the reason (cut to `n`; `reason` may be NULL), and nothing left changed. */
bool latch_acquire(const GameLocal* l, char* reason, size_t n);

/* Keeps the lease in place this tick (see the top). False with the reason when it no longer holds. */
bool latch_refresh(const GameLocal* l, char* reason, size_t n);

/* Gives the lease back (see the top): `avatar_valid` when the player is still the one the latch was taken for. How many
 * entries were not put back. Call it again (each tick) while LATCH entries are left, as for a failed write. */
int latch_release(bool avatar_valid);

/* The lease is held (acquired, not yet released). */
bool latch_held(void);

/* Starts a slot hotkey (see the top): slot 1..4, the pacing and Instant as entry_begin takes them, `now` in ms. */
bool entry_begin_shortcut(EntryJob* job, const GameView* v, int slot, uint32_t interval_ms, bool instant, uint64_t now,
                          char* reason, size_t n);

/* One tick of the active shortcut with this tick's view (see the top); `trigger_down` is the slot binding's level (for
 * Instant), `confirm_down` Confirm's. While shortcut_active(), start no other job in `job`. */
void entry_step_shortcut(EntryJob* job, const GameView* v, uint64_t now, bool trigger_down, bool confirm_down);

/* Ends the active shortcut as cancelled (the mission ended, the HUD went away, the player changed): a running job is
 * cancelled with `reason` (NULL: "cancelled"), a done one turns ENTRY_FAILED with it; the latch is released, and the
 * menu closed when DBF opened it and `v` (may be NULL: no close) shows it active for the same player. */
void entry_cancel_shortcut(EntryJob* job, const GameView* v, const char* reason);

/* A shortcut is active: from a true entry_begin_shortcut until its end (it holds the latch all that time). */
bool shortcut_active(void);

#endif
