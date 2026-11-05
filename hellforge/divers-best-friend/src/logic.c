/* logic: see logic.h. */
#include <string.h>
#include "logic.h"

/* Pacing values that are R46's behaviour, not game addresses, so they are not in the generated header. */
#define LOGIC_RANDOM_MIN_MS 70u        /* randomize_input_delay draws math.random(70,240): R46 input.lua:13 */
#define LOGIC_RANDOM_MAX_MS 240u       /* (the same line) */
#define LOGIC_DEADLINE_FLOOR_MS 3000u  /* a code entry gives up after at least this long: R46 selection.lua:92 */
#define LOGIC_DEADLINE_SLACK_MS 1500u  /* plus this much on top of length * interval: R46 selection.lua:92 */


_Static_assert(DBF_VAL_CARD_COUNT == LOGIC_LIST_ROWS, "logic_list_rows takes one entry per card of the HUD list");
_Static_assert(DBF_OFF_CARD_TIMER_KIND_OFFSET + 4u <= DBF_OFF_CARD_TIMER_SIZE, "the timer block holds the kind");
_Static_assert(DBF_OFF_CARD_TIMER_STATE_OFFSET + 4u <= DBF_OFF_CARD_TIMER_SIZE, "the timer block holds the state");
_Static_assert(DBF_OFF_CARD_TIMER_INCOMING_SECONDS_OFFSET + 4u <= DBF_OFF_CARD_TIMER_SIZE, "the block holds the seconds");
_Static_assert(DBF_OFF_CARD_TIMER_COOLDOWN_SECONDS_OFFSET + 4u <= DBF_OFF_CARD_TIMER_SIZE, "the block holds the seconds");

/* --- timers ---------------------------------------------------------------------------------------------------- */

void logic_timer(const DbfRow* row, DbfTimer* out)
{
    uint32_t kind, state;
    size_t seconds_at;
    float seconds;
    uint32_t whole;

    if (out == NULL) return;
    memset(out, 0, sizeof *out);
    /* A row without a kind has no timer to be the kind's (and an all-zero block, not yet filled, would agree with it). */
    if (row == NULL || row->kind == 0) return;

    memcpy(&kind, row->timer + DBF_OFF_CARD_TIMER_KIND_OFFSET, sizeof kind);
    if (kind != row->kind) return; /* R46 input.lua:26: another kind's block, or one the game has not updated: unknown */
    out->valid = true;

    memcpy(&state, row->timer + DBF_OFF_CARD_TIMER_STATE_OFFSET, sizeof state);
    out->unavailable = state == DBF_VAL_TIMER_STATE_UNAVAILABLE; /* input.lua:28 */
    if (state == DBF_VAL_TIMER_STATE_INCOMING) seconds_at = DBF_OFF_CARD_TIMER_INCOMING_SECONDS_OFFSET;
    else if (state == DBF_VAL_TIMER_STATE_COOLDOWN) seconds_at = DBF_OFF_CARD_TIMER_COOLDOWN_SECONDS_OFFSET;
    else return; /* input.lua:29-30 */

    memcpy(&seconds, row->timer + seconds_at, sizeof seconds);
    /* A number in (0, 86400] (input.lua:33); written so that NaN fails the test. */
    if (!(seconds > 0.0f && seconds <= (float)DBF_VAL_TIMER_SECONDS_MAX)) return;
    whole = (uint32_t)seconds; /* truncates; rounded up below (math.ceil, input.lua:34) without libm */
    if ((float)whole < seconds) whole++;
    out->seconds = whole;
    out->incoming = state == DBF_VAL_TIMER_STATE_INCOMING;
    out->cooldown = state == DBF_VAL_TIMER_STATE_COOLDOWN;
}

/* --- the blacklist --------------------------------------------------------------------------------------------- */

bool logic_blacklisted(uint32_t kind, const DbfSettings* s)
{
    if (s == NULL) return false;
    if (kind < DBF_BLACKLIST_SLOTS && s->blacklist_kind[kind]) return true;
    if (s->hide_sos && kind == DBF_VAL_HIDE_SOS_KIND) return true;                /* blacklist.lua:4 */
    if (s->hide_eagle_rearm && kind == DBF_VAL_HIDE_EAGLE_REARM_KIND) return true; /* mission_blacklist.lua:51 */
    return false;
}

/* --- which rows -------------------------------------------------------------------------------------------------- */

/* Whether the row may be chosen (selection.lua:19-22): a kind, not blacklisted, no timer running, not unavailable. A timer
 * block that is not the row's, or whose seconds are unusable, is "unknown" and does not block (input.lua:24-26). */
static bool row_eligible(const DbfRow* r, const DbfSettings* s)
{
    DbfTimer t;
    if (r->kind == 0 || logic_blacklisted(r->kind, s)) return false;
    logic_timer(r, &t);
    return !t.incoming && !t.cooldown && !t.unavailable;
}

/* List order (selection.lua:27-32): list_y descending, then entry, then card address, both ascending. A list_y that is NaN
 * compares as a tie. */
static bool row_before(const DbfRow* a, const DbfRow* b)
{
    if (a->list_y > b->list_y) return true;
    if (a->list_y < b->list_y) return false;
    if (a->entry != b->entry) return a->entry < b->entry;
    return a->card < b->card;
}

int logic_list_rows(const GameView* v, const DbfSettings* s, int order[LOGIC_LIST_ROWS], bool eligible[LOGIC_LIST_ROWS])
{
    int idx[LOGIC_LIST_ROWS], n;
    bool ok[LOGIC_LIST_ROWS];

    for (int k = 0; k < LOGIC_LIST_ROWS; k++) {
        idx[k] = -1;
        ok[k] = false;
    }
    n = v == NULL ? 0 : v->row_count;
    if (n < 0) n = 0;
    if (n > LOGIC_LIST_ROWS) n = LOGIC_LIST_ROWS;

    /* A stable insertion sort of the row indices: at most 16 of them. */
    for (int i = 0; i < n; i++) {
        int pos = i;
        while (pos > 0 && row_before(&v->rows[i], &v->rows[idx[pos - 1]])) {
            idx[pos] = idx[pos - 1];
            pos--;
        }
        idx[pos] = i;
        ok[i] = row_eligible(&v->rows[i], s);
    }

    if (order != NULL) memcpy(order, idx, sizeof idx);
    if (eligible != NULL) memcpy(eligible, ok, sizeof ok);
    return n;
}

/* --- List Select ------------------------------------------------------------------------------------------------- */

static void choose(ListState* st, const GameView* v, int row)
{
    st->chosen = row;
    st->chosen_kind = v->rows[row].kind;
    st->chosen_card = v->rows[row].card;
}

static void clear_choice(ListState* st)
{
    st->chosen = -1;
    st->chosen_kind = 0;
    st->chosen_card = 0;
}

ListEvent logic_list_step(ListState* st, const GameView* v, const DbfSettings* s, const bool levels[BIND_COUNT], bool busy,
                          int* row)
{
    bool lv[BIND_COUNT], rising[BIND_COUNT];
    int order[LOGIC_LIST_ROWS], n;
    bool eligible[LOGIC_LIST_ROWS];
    ListEvent event = LIST_NONE;

    if (row != NULL) *row = -1;
    if (st == NULL) return LIST_NONE;

    /* The edges are seen on every call, open or closed, busy or not; a press that nothing could use is spent. */
    for (int i = 0; i < BIND_COUNT; i++) {
        lv[i] = levels != NULL && levels[i];
        rising[i] = lv[i] && !st->prev[i];
        st->prev[i] = lv[i];
    }

    if (v == NULL || !v->menu_open) { /* selection.lua:12-16: a closed list forgets its choice */
        clear_choice(st);
        st->was_open = false;
        st->confirm_armed = false;
        return LIST_NONE;
    }

    n = logic_list_rows(v, s, order, eligible);

    if (!st->was_open) {
        /* Opening (selection.lua:34-39): the first row of the list that may be chosen; a Confirm held now is not a press. */
        st->was_open = true;
        st->confirm_armed = !lv[BIND_CONFIRM];
        clear_choice(st);
        for (int k = 0; k < n; k++) {
            if (eligible[order[k]]) {
                choose(st, v, order[k]);
                break;
            }
        }
    } else if (st->chosen >= 0) {
        /* The choice is pinned to its card and kind, wherever the list put the card now (selection.lua:41-43). */
        int found = -1;
        for (int i = 0; i < n; i++) {
            if (v->rows[i].card == st->chosen_card && v->rows[i].kind == st->chosen_kind) {
                found = i;
                break;
            }
        }
        if (found >= 0 && eligible[found]) choose(st, v, found);
        else clear_choice(st); /* gone, another stratagem, or on cooldown, blacklisted, unavailable: not chosen any more */
    }
    if (!lv[BIND_CONFIRM]) st->confirm_armed = true;

    if (busy) return LIST_NONE; /* selection.lua:48-59: while a code is being entered the list does nothing else */

    /* Next and Previous (selection.lua:76-81): one of them rising, not both. */
    if (rising[BIND_NEXT] != rising[BIND_PREVIOUS]) {
        int ranked[LOGIC_LIST_ROWS], m = 0, at = -1;
        for (int k = 0; k < n; k++) {
            if (!eligible[order[k]]) continue;
            if (order[k] == st->chosen) at = m;
            ranked[m++] = order[k];
        }
        if (m > 0) {
            int target;
            uintptr_t before = st->chosen >= 0 ? st->chosen_card : 0;
            if (at < 0) target = rising[BIND_NEXT] ? 0 : m - 1; /* nothing chosen: Next the first, Previous the last */
            else target = rising[BIND_NEXT] ? (at + 1) % m : (at + m - 1) % m;
            choose(st, v, ranked[target]);
            /* Only a changed target is a move (R46's cue, feedback.lua:25): with one row to choose from the press changes
             * nothing. The card is the identity of a row, as for the pin. */
            if (st->chosen_card != before) event = LIST_MOVED;
        }
    }

    /* Confirm (selection.lua:87): a press, armed, with a row chosen that may be; for the row chosen after any move above. */
    if (rising[BIND_CONFIRM] && st->confirm_armed && st->chosen >= 0 && eligible[st->chosen]) {
        event = LIST_CONFIRM;
        if (row != NULL) *row = st->chosen;
    }
    return event;
}

/* --- pacing ------------------------------------------------------------------------------------------------------ */

uint32_t logic_interval(const DbfSettings* s, uint32_t (*random)(void))
{
    int ms;
    if (s == NULL) return DBF_INTERVAL_DEFAULT_MS;
    if (s->randomize_input_delay && random != NULL)
        return LOGIC_RANDOM_MIN_MS + random() % (LOGIC_RANDOM_MAX_MS - LOGIC_RANDOM_MIN_MS + 1u);
    ms = s->input_interval_ms;
    if (ms < 0) ms = 0;
    if (ms > DBF_INTERVAL_MAX_MS) ms = DBF_INTERVAL_MAX_MS;
    return (uint32_t)ms;
}

uint64_t logic_deadline(uint32_t len, uint32_t interval_ms, uint64_t now)
{
    uint64_t span = (uint64_t)len * interval_ms + LOGIC_DEADLINE_SLACK_MS;
    return now + (span > LOGIC_DEADLINE_FLOOR_MS ? span : LOGIC_DEADLINE_FLOOR_MS);
}
