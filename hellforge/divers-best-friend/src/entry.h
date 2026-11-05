/* entry: enters a stratagem's code through the game's own input path, one direction at a time, as R46 does
 * (input.lua:240-282, begin and advance; selection.lua:13-16, 48-56 and 92-93, the aborts and the timing), paced or
 * Instant (the 26251122 tree's input.lua:24-36).
 *
 * Begin (entry_begin, R46 input.lua:240-250): ENTRY must be admitted; the menu must be open (GameView.menu_open) and
 * active (GameLocal.menu_active, input.lua:118-119), the code-entry chain must hold (local_ok); the input component must
 * be clean (its u32 count at +0, its matched kind at +0x14 and its queued kind at +0x2c all 0) and the four direction
 * action bytes (actions + 0x20 * a, a = 1 left, 2 right, 3 up, 4 down) idle; the kind must be in the local payload (one
 * of its u32 kinds at +0x188 + k * 0x30, k below its u32 count at +0x788, which is at most 32); and codes_read must give
 * its code (with the scramble remap). The job then keeps the kind (the one asked for, even when the code is a scramble
 * remap's), the code, the identity (the player manager and registry key) and the input component; next_at is `now`, so
 * the first direction goes on the next entry_step; the deadline is logic_deadline(len, interval, now), with an interval
 * of 0 for Instant. Nothing is written at begin, and the only game function called is codes' scramble query (through
 * codes_read and native.h, when SCRAMBLE is admitted).
 *
 * Every entry_step of a running job first aborts (ENTRY_FAILED) when: the menu is closed or inactive, local_ok is false,
 * the identity (manager, key) or the input component is not the job's, the deadline has passed (now > deadline), or the
 * payload no longer holds the kind. Then it sends what is due:
 *   paced    one direction when now >= next_at, then next_at = now + interval (an interval of 0: one per step);
 *   Instant  every direction but the last at once; the last only once `trigger_down` (the binding that started the job)
 *            has been false for INSTANT_SETTLE_MS (100) without a break: settle_at is set when it is first seen up and
 *            cleared whenever it is down. When Confirm is also the throw, equipping while it is held would start the throw.
 *
 * One direction (input.lua:251-282), every check read fresh from the game: ENTRY still admitted; the menu-active bit
 * still set (avatar + 0xfd8, bit 9; the game may close the menu inside a call); codes_read again, and the same code
 * (length and every direction; "code changed" otherwise); the count at +0 equal to the directions sent and the matched
 * kind at +0x14 0; the direction bytes at component + 3 + i (i = 1..sent) the directions sent; the four action bytes
 * idle. Then the direction's action byte is set from 0 to 1 with mem_swap under MEM_OWNER_ENTRY, nat_input_handler
 * runs on the component, and mem_restore(MEM_OWNER_ENTRY) puts the byte back, always (when the swap failed, and when the
 * handler did not run too). The byte must then read 0: the game may release it itself inside the call, which counts as
 * released. Afterwards the count must be sent + 1 and the matched kind 0, or, after the last direction, the job's kind
 * (the one asked for, not the scramble's). The journal holds no ENTRY entry after any step, except when the release
 * could not be written ("direction could not be released"): that entry stays for a later mem_restore(MEM_OWNER_ENTRY) to
 * retry (the tick calls it while ENTRY has entries; entry_cancel does too).
 *
 * Reasons (EntryJob.reason, "" while running or done): "Code entry: <admission's reason>", "menu closed", "menu
 * inactive", "menu state unreadable", "local player unavailable", "close and reopen the menu" (the component was not
 * clean at begin), "input component unreadable", "manual direction input", "direction actions unreadable", "stratagem
 * entries unreadable", "invalid stratagem entry count", "stratagem not in the mission", codes.h's reasons (at begin),
 * "player changed", "timed out", "stratagem no longer in the mission", "code changed", "code changed: <codes.h's
 * reason>", "the game's input changed", "the game's code sequence changed", "invalid direction", "direction could not
 * be pressed", "input handler unavailable", "direction could not be released", "the game did not take the direction",
 * "the game matched another stratagem" (a match before the last direction), "the game did not accept the code", and
 * entry_cancel's ("cancelled" when it gives none).
 *
 * Every read goes through memory.h, the one write through mem_swap, every game call through native.h (the input handler
 * here, the scramble query in codes_read), and every game number is the generated header's; INSTANT_SETTLE_MS is entry.c's own (the 26251122 tree's input.lua:24). Portable C11:
 * standard headers, memory.h, admission.h, native.h, codes.h, game.h, logic.h and the generated header. Not thread-safe:
 * only the game thread calls it. */
#ifndef DBF_ENTRY_H
#define DBF_ENTRY_H

#include <stdbool.h>
#include <stdint.h>
#include "codes.h"
#include "game.h"

typedef enum { ENTRY_IDLE, ENTRY_RUNNING, ENTRY_DONE, ENTRY_FAILED } EntryState;

typedef struct EntryJob {
    EntryState state;
    uint32_t kind;                /* the stratagem asked for; the matched kind the last direction must give */
    DbfCode code;                 /* its code at begin (a scramble remap's code when one was on) */
    uint8_t sent;                 /* directions handed to the game's handler so far */
    uint32_t interval_ms;         /* between directions: the caller's, 0 for Instant */
    bool instant;
    bool latched;                 /* the job runs under the Hold->Press latch (slot hotkeys, Select on Release): kept for
                                     the latch's caller, entry treats the job like any other */
    uint64_t next_at, deadline;   /* ms, the clock of entry_begin's and entry_step's `now` */
    uint64_t settle_at;           /* Instant: when the last direction may go; 0 while the trigger has not been seen up */
    uintptr_t identity_manager;   /* GameLocal.manager at begin */
    uint32_t identity_key;        /* GameLocal.key at begin */
    uintptr_t component;          /* GameLocal.component at begin */
    char reason[DBF_REASON_SIZE]; /* why the job failed or did not start; "" otherwise */
} EntryJob;

/* Starts a job for `kind` from the view of this tick (see Begin above). `job` holds an earlier job or is all zero
 * (ENTRY_IDLE). True: the job is ENTRY_RUNNING. False: the job is ENTRY_FAILED with the reason, and nothing was written;
 * a job that is still running is left alone (false, unchanged). NULL `job` is false; NULL `v` fails with "menu
 * closed". */
bool entry_begin(EntryJob* job, const GameView* v, uint32_t kind, uint32_t interval_ms, bool instant, bool latched,
                 uint64_t now);

/* One tick of a running job with this tick's view (see above); `trigger_down` is the level of the binding that started
 * it (only Instant uses it). Ends in ENTRY_DONE or ENTRY_FAILED, or stays ENTRY_RUNNING. Does nothing for a job that is
 * not running or NULL. A NULL `v` fails the job with "menu closed". */
void entry_step(EntryJob* job, const GameView* v, uint64_t now, bool trigger_down);

/* Stops a running job: ENTRY_FAILED with `reason` (NULL: "cancelled"). Puts back anything still journaled under
 * MEM_OWNER_ENTRY (between steps, only a release that could not be written). A job that is not running is left alone. */
void entry_cancel(EntryJob* job, const char* reason);

#endif
