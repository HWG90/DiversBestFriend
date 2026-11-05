/* logic: the decisions behind List Select, as pure functions of what was read: each card's timer, which rows the list
 * shows and may choose, the Next, Previous and Confirm moves with their rising edges, and the pacing of the code entry.
 * Ported from R46 (the Lua DBF for build 25480438): input.lua:8-14 (the interval), input.lua:20-36 (the timer decode),
 * selection.lua:8-93 (List Select) and blacklist.lua:16-32 (the filter). Nothing here reads game memory, calls game code,
 * draws or enters a code: a caller feeds it a GameView (game.h), the settings and the levels of bind_poll (bindings.h),
 * and acts on what it answers.
 *
 * Timers. A card's timer block (DbfRow.timer, 0x44 bytes at card + 0x3718) is the one the game's own HUD renders. It
 * counts for the card only when its u32 at +0x34 is the row's kind (R46 input.lua:26): a block of another kind, or one the
 * game has not filled yet, says nothing. The u32 at +0x40 is the state: 5 the stratagem is unavailable, 3 a timer runs
 * before it comes in (incoming; float seconds at +0), 4 a cooldown runs (float seconds at +8); other states are neither.
 * Seconds count only when they are a number in (0, 86400]; they are rounded up. A state of 3 or 4 whose seconds are NaN,
 * infinite, zero, negative or over a day has no timer, as in R46 (unknown, and an unknown timer does not block a row).
 *
 * Which rows the list shows and which it may choose (logic_list_rows). Every row of the GameView is shown, in R46's order:
 * list_y from the top (descending), then the payload entry, then the card's address (selection.lua:23-33; the settled
 * row positions, not the payload's order). A row may be chosen ("eligible") when its kind is not 0, its kind is not
 * blacklisted (logic_blacklisted), no timer runs for it (incoming or cooldown) and it is not unavailable (selection.lua:
 * 19-22). A blacklisted or timed row is still drawn by a caller (R46's keep_visible); it only cannot be chosen. Rows with a
 * kind of 150 or more (HellForge mod stratagems, which codes.h gives codes to) are chosen like any other.
 *
 * List Select (logic_list_step), once per tick with the levels bind_poll gave:
 *   - The list is open while GameView.menu_open. The tick it goes from closed to open, the first eligible row in list
 *     order is chosen (none: nothing is chosen), and a Confirm held at that moment does nothing until it has been let go
 *     (confirm_armed; R46 selection.lua:34-39). Closing the menu forgets everything: the choice, the arming, was_open.
 *   - Next and Previous act on a rising edge of their level (R46 selection.lua:8-11), one row per press, among the
 *     eligible rows in list order, wrapping around. With nothing chosen, Next chooses the first and Previous the last. If
 *     both rise in the same tick, neither moves (selection.lua:76). A press on a tick in which the caller is `busy`
 *     (a code entry is under way) is lost, not saved for later (selection.lua:48-59 returned before the edges were used).
 *     The answer is LIST_MOVED only when the chosen card changed (R46 plays its move cue on a changed target only,
 *     feedback.lua:25): with one eligible row a press moves nothing and the answer is LIST_NONE.
 *   - Confirm acts on a rising edge too, when it is armed, a row is chosen (and eligible) and the caller is not busy: the
 *     answer is LIST_CONFIRM and *row is the chosen row's index in GameView.rows. A Next or Previous that moved the choice
 *     in the same tick counts: Confirm is for the row chosen after the move (R46 does the same).
 *   - The choice is pinned to the card, not to a position: it keeps the card's address and its kind, and on every tick
 *     finds that card again (the list reorders as cooldowns start and end). When the card is gone, shows another kind, or
 *     is no longer eligible, the choice is cleared (chosen -1); a later Next or Previous chooses by the rule for nothing
 *     chosen. R46 chose the first row again instead; the HellForge port clears (Plan 2, Task 8's decisions).
 *
 * Edges. The levels are trusted as they come: bind_poll keeps a key held while nothing could fire from counting as
 * pressed (the release rule in bindings.h), so the first level of such a key is already a real press. ListState.prev keeps
 * the levels of the last call, which is made every tick the module runs, open or closed, so a key held while the list
 * was closed (or while the previous tick was busy) is not an edge when it is seen later. A wheel notch is a level of one
 * poll, and bind_poll puts a poll without it between two notches (bindings.h), so every notch is an edge of its own: three
 * notches turned between two ticks are three moves over the next ticks, not one.
 *
 * Pacing (logic_interval, logic_deadline): the milliseconds between two directions of a code entry. A setting of 0 to 250
 * is used as it is (0: one direction per frame, which the caller's loop decides); randomize_input_delay draws from 70 to 240
 * once for each entry (input.lua:12-14), the caller calling logic_interval once per job. The job's deadline is R46's
 * (selection.lua:92): at least 3000 ms, or the length of the code times the interval plus 1500 ms when that is more.
 *
 * Portable C11: standard headers, game.h, settings.h and bindings.h. Not thread-safe: the game thread's tick calls it. */
#ifndef DBF_LOGIC_H
#define DBF_LOGIC_H

#include <stdbool.h>
#include <stdint.h>
#include "bindings.h"
#include "game.h"
#include "settings.h"

typedef struct DbfTimer {
    bool valid;       /* the block belongs to the row: its u32 at +0x34 is the row's kind */
    bool unavailable; /* valid, and the state is 5 */
    bool incoming;    /* valid, state 3, and the seconds are a timer */
    bool cooldown;    /* valid, state 4, and the seconds are a timer */
    uint32_t seconds; /* of incoming or cooldown, rounded up, 1 to 86400; 0 otherwise */
} DbfTimer;

/* Decodes row->timer (see Timers above). *out is all zero when `row` is NULL or the block is not the row's. NULL `out` is
 * ignored. */
void logic_timer(const DbfRow* row, DbfTimer* out);

/* Whether the player hid this stratagem: settings->blacklist_kind[kind] (kinds below DBF_BLACKLIST_SLOTS), or the SOS
 * Beacon (DBF_VAL_HIDE_SOS_KIND) with hide_sos, or the Eagle Rearm (DBF_VAL_HIDE_EAGLE_REARM_KIND) with hide_eagle_rearm
 * (R46 blacklist.lua:4, mission_blacklist.lua:51). A kind of 200 or more, or no settings (NULL), is not blacklisted. */
bool logic_blacklisted(uint32_t kind, const DbfSettings* s);

/* The state of List Select between ticks. All zero is a valid start (or after any logic_list_step); `chosen` and the pinned
 * card mean something only while was_open. */
typedef struct ListState {
    int chosen;            /* the chosen row's index in GameView.rows as of the last step; -1: nothing is chosen */
    uint32_t chosen_kind;  /* the kind of the chosen row, kept with the card to pin the choice */
    uintptr_t chosen_card; /* the address of the chosen row's card */
    bool was_open;         /* the list was open at the last step */
    bool confirm_armed;    /* a Confirm edge may confirm: Confirm was up since the list opened */
    bool prev[BIND_COUNT]; /* the levels of the last step */
} ListState;

typedef enum { LIST_NONE, LIST_MOVED, LIST_CONFIRM } ListEvent;

/* The most rows logic_list_rows serves, and how many entries it writes into each of order[] and eligible[]: one per card
 * of the HUD list (logic.c asserts it equals DBF_VAL_CARD_COUNT). */
#define LOGIC_LIST_ROWS 16

/* The rows of the GameView in list order, with whether each may be chosen. Returns the number of rows (GameView.row_count
 * limited to LOGIC_LIST_ROWS, 0 for a NULL view or a negative count): order[0..n) are indices into v->rows from the top
 * of the list down (order[k] = -1 for k >= n), and eligible[i] is whether v->rows[i] may be chosen (indexed by the row,
 * not by its place in the order; false for i >= n). Both arrays get all LOGIC_LIST_ROWS entries; either may be NULL. */
int logic_list_rows(const GameView* v, const DbfSettings* s, int order[LOGIC_LIST_ROWS], bool eligible[LOGIC_LIST_ROWS]);

/* One tick of List Select (see above). `levels` are bind_poll's (NULL: all up); `busy` is whether a code entry is under
 * way; `row` (NULL allowed) is set to -1, and on LIST_CONFIRM to the chosen row's index in v->rows. LIST_MOVED: a Next or
 * Previous press changed the chosen card (also from nothing chosen to a row), which is when the move cue plays in R46
 * (feedback.lua:25); with a single eligible row the press changes nothing and the answer is LIST_NONE. st->chosen says
 * what is highlighted. A NULL `st` answers LIST_NONE; a NULL `v` counts as a closed menu. */
ListEvent logic_list_step(ListState* st, const GameView* v, const DbfSettings* s, const bool levels[BIND_COUNT], bool busy,
                          int* row);

/* The pause between directions of one code entry, in ms: 70 to 240 from `random` when randomize_input_delay is set (70 +
 * random() % 171, `random` called once), else input_interval_ms limited to 0 to 250. A NULL `random` uses the setting. */
uint32_t logic_interval(const DbfSettings* s, uint32_t (*random)(void));

/* When a code entry of `len` directions at `interval_ms` gives up, from `now` (ms): now + max(3000, len * interval_ms +
 * 1500), R46 selection.lua:92. */
uint64_t logic_deadline(uint32_t len, uint32_t interval_ms, uint64_t now);

#endif
