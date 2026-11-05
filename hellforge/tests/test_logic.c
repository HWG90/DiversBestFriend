/* Tests for src/logic.c: the card timers, the blacklist filter, which rows the list shows and may choose, List Select's
 * choice, edges and Confirm, and the pacing of the code entry. Pure functions: the tests build GameViews and levels by hand
 * (no game image, no admission). The ListState is the caller's, so every test starts from its own. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "addresses_25480438.h"
#include "bindings.h"
#include "game.h"
#include "logic.h"
#include "settings.h"
#include "test.h"

/* --- helpers --------------------------------------------------------------------------------------------------- */

static void put_u32(uint8_t* block, size_t off, uint32_t v) { memcpy(block + off, &v, sizeof v); }
static void put_f32(uint8_t* block, size_t off, float v) { memcpy(block + off, &v, sizeof v); }

/* A row of kind `kind` on card address `card`, at list position `y`, showing payload entry `entry`; its timer block is the
 * game's idle one (this kind, state 0). */
static DbfRow make_row(uint32_t kind, uintptr_t card, float y, uint32_t entry)
{
    DbfRow r;
    memset(&r, 0, sizeof r);
    r.card = card;
    r.list_y = y;
    r.kind = kind;
    r.entry = entry;
    r.active = true;
    put_u32(r.timer, DBF_OFF_CARD_TIMER_KIND_OFFSET, kind);
    return r;
}

static void set_state(DbfRow* r, uint32_t state) { put_u32(r->timer, DBF_OFF_CARD_TIMER_STATE_OFFSET, state); }

static void set_incoming(DbfRow* r, float seconds)
{
    set_state(r, DBF_VAL_TIMER_STATE_INCOMING);
    put_f32(r->timer, DBF_OFF_CARD_TIMER_INCOMING_SECONDS_OFFSET, seconds);
}

static void set_cooldown(DbfRow* r, float seconds)
{
    set_state(r, DBF_VAL_TIMER_STATE_COOLDOWN);
    put_f32(r->timer, DBF_OFF_CARD_TIMER_COOLDOWN_SECONDS_OFFSET, seconds);
}

static DbfSettings defaults(void)
{
    DbfSettings s;
    settings_defaults(&s);
    return s;
}

static DbfTimer timer_of(const DbfRow* r)
{
    DbfTimer t;
    memset(&t, 0xa5, sizeof t);
    logic_timer(r, &t);
    return t;
}

static bool timer_is(DbfTimer t, bool valid, bool unavailable, bool incoming, bool cooldown, uint32_t seconds)
{
    return t.valid == valid && t.unavailable == unavailable && t.incoming == incoming && t.cooldown == cooldown &&
           t.seconds == seconds;
}

static bool no_timer(DbfTimer t) { return t.valid && !t.unavailable && !t.incoming && !t.cooldown && t.seconds == 0; }

/* A GameView with the menu open and `n` rows (copied from `rows`). */
static GameView make_view(const DbfRow* rows, int n, bool open)
{
    GameView v;
    memset(&v, 0, sizeof v);
    v.build_ok = v.in_gameplay = v.hud_ready = true;
    v.menu_open = open;
    v.row_count = n;
    for (int i = 0; i < n; i++) v.rows[i] = rows[i];
    return v;
}

static bool g_levels[BIND_COUNT];

static void release_all(void) { memset(g_levels, 0, sizeof g_levels); }
static void hold(BindAction a) { g_levels[a] = true; }
static void let_go(BindAction a) { g_levels[a] = false; }

static int g_row;       /* *row of the last step */
static int g_press_row; /* *row of the step that pressed, in press() */

/* One step with the current levels. */
static ListEvent step(ListState* st, const GameView* v, const DbfSettings* s, bool busy)
{
    g_row = 12345;
    return logic_list_step(st, v, s, g_levels, busy, &g_row);
}

/* A press: the level goes up for one step and down again. Returns the event of the step that pressed (its *row in
 * g_press_row). */
static ListEvent press(ListState* st, const GameView* v, const DbfSettings* s, BindAction a, bool busy)
{
    ListEvent e;
    hold(a);
    e = step(st, v, s, busy);
    g_press_row = g_row;
    let_go(a);
    (void)step(st, v, s, busy); /* seen up */
    return e;
}

/* Four rows listed top to bottom by y: kind 10 (card 0x1000, entry 0), 11 (0x2000, entry 1), 12 (0x3000, entry 2), 13
 * (0x4000, entry 3). In GameView.rows they are in this order, so the row index is also the place in the list. */
static GameView four_rows(void)
{
    DbfRow r[4] = { make_row(10, 0x1000, 400.0f, 0), make_row(11, 0x2000, 300.0f, 1), make_row(12, 0x3000, 200.0f, 2),
                    make_row(13, 0x4000, 100.0f, 3) };
    return make_view(r, 4, true);
}

/* --- timers ---------------------------------------------------------------------------------------------------- */

static void test_timer_states(void)
{
    DbfRow r = make_row(42, 0x1000, 0.0f, 0);
    DbfTimer t = timer_of(&r);
    CHECK(timer_is(t, true, false, false, false, 0), "idle state 0: valid, no flag, no seconds");
    CHECK(no_timer(t), "(that is no timer)");

    set_state(&r, DBF_VAL_TIMER_STATE_UNAVAILABLE);
    CHECK(timer_is(timer_of(&r), true, true, false, false, 0), "state 5: unavailable, no timer");
    CHECK(DBF_VAL_TIMER_STATE_UNAVAILABLE == 5 && DBF_VAL_TIMER_STATE_INCOMING == 3 && DBF_VAL_TIMER_STATE_COOLDOWN == 4,
          "the states are R46's 5, 3 and 4");

    set_incoming(&r, 12.25f);
    CHECK(timer_is(timer_of(&r), true, false, true, false, 13), "state 3: incoming, 12.25 s rounds up to 13");
    set_cooldown(&r, 59.5f);
    CHECK(timer_is(timer_of(&r), true, false, false, true, 60), "state 4: cooldown, 59.5 s rounds up to 60");

    for (uint32_t state = 0; state < 12; state++) {
        char text[96];
        if (state == 3 || state == 4 || state == 5) continue;
        set_state(&r, state);
        put_f32(r.timer, 0, 30.0f);
        put_f32(r.timer, 8, 30.0f);
        snprintf(text, sizeof text, "state %u is neither unavailable nor a timer", state);
        CHECK(no_timer(timer_of(&r)), text);
    }
    set_state(&r, 0xffffffffu);
    CHECK(no_timer(timer_of(&r)), "state 0xffffffff is neither");
}

static void test_timer_fields(void)
{
    DbfRow r = make_row(7, 0x1000, 0.0f, 0);
    put_f32(r.timer, DBF_OFF_CARD_TIMER_INCOMING_SECONDS_OFFSET, 100.0f);
    put_f32(r.timer, DBF_OFF_CARD_TIMER_COOLDOWN_SECONDS_OFFSET, 200.0f);
    set_state(&r, DBF_VAL_TIMER_STATE_INCOMING);
    CHECK(timer_is(timer_of(&r), true, false, true, false, 100), "incoming reads the float at +0, not the one at +8");
    set_state(&r, DBF_VAL_TIMER_STATE_COOLDOWN);
    CHECK(timer_is(timer_of(&r), true, false, false, true, 200), "cooldown reads the float at +8, not the one at +0");
    CHECK(DBF_OFF_CARD_TIMER_KIND_OFFSET == 0x34 && DBF_OFF_CARD_TIMER_STATE_OFFSET == 0x40 &&
              DBF_OFF_CARD_TIMER_INCOMING_SECONDS_OFFSET == 0 && DBF_OFF_CARD_TIMER_COOLDOWN_SECONDS_OFFSET == 8,
          "the offsets are R46's (kind +0x34, state +0x40, seconds +0 and +8)");

    /* The block is the row's only when +0x34 holds the row's kind. */
    DbfRow other = r;
    put_u32(other.timer, DBF_OFF_CARD_TIMER_KIND_OFFSET, 8);
    CHECK(timer_is(timer_of(&other), false, false, false, false, 0), "a block of another kind says nothing (cooldown state ignored)");
    put_u32(other.timer, DBF_OFF_CARD_TIMER_KIND_OFFSET, 0);
    CHECK(timer_is(timer_of(&other), false, false, false, false, 0), "a block with kind 0 (not filled yet) says nothing");
    set_state(&other, DBF_VAL_TIMER_STATE_UNAVAILABLE);
    put_u32(other.timer, DBF_OFF_CARD_TIMER_KIND_OFFSET, 8);
    CHECK(timer_is(timer_of(&other), false, false, false, false, 0), "nor does unavailable of another kind's block");
    memset(other.timer, 0, sizeof other.timer);
    CHECK(timer_is(timer_of(&other), false, false, false, false, 0), "an all-zero block of a row with kind 7 says nothing");
    DbfRow kindless = make_row(0, 0x1000, 0.0f, 0);
    set_state(&kindless, DBF_VAL_TIMER_STATE_UNAVAILABLE);
    CHECK(timer_is(timer_of(&kindless), false, false, false, false, 0),
          "a row without a kind (0) has no timer, even with an all-zero block that agrees");

    /* The wrong bytes of the block do not matter: only +0x34, +0x40 and the two floats are read. */
    DbfRow noisy = make_row(7, 0x1000, 0.0f, 0);
    memset(noisy.timer, 0x5a, sizeof noisy.timer);
    put_u32(noisy.timer, DBF_OFF_CARD_TIMER_KIND_OFFSET, 7);
    put_u32(noisy.timer, DBF_OFF_CARD_TIMER_STATE_OFFSET, DBF_VAL_TIMER_STATE_COOLDOWN);
    put_f32(noisy.timer, DBF_OFF_CARD_TIMER_COOLDOWN_SECONDS_OFFSET, 3.0f);
    CHECK(timer_is(timer_of(&noisy), true, false, false, true, 3), "other bytes of the block are not read");

    DbfTimer t = { true, true, true, true, 9 };
    logic_timer(NULL, &t);
    CHECK(timer_is(t, false, false, false, false, 0), "a NULL row gives an all-zero timer");
    logic_timer(&r, NULL);
    CHECK(true, "a NULL out is ignored");
}

static void test_timer_seconds(void)
{
    DbfRow r = make_row(9, 0x1000, 0.0f, 0);
    union { uint32_t u; float f; } nan_bits = { 0x7fc00000u }, inf_bits = { 0x7f800000u }, ninf_bits = { 0xff800000u },
        snan_bits = { 0x7fa00000u }, denorm = { 1u };

    set_cooldown(&r, 1.0f);
    CHECK(timer_is(timer_of(&r), true, false, false, true, 1), "1.0 s is 1");
    set_cooldown(&r, 0.001f);
    CHECK(timer_is(timer_of(&r), true, false, false, true, 1), "0.001 s rounds up to 1");
    set_cooldown(&r, denorm.f);
    CHECK(timer_is(timer_of(&r), true, false, false, true, 1), "the smallest positive float rounds up to 1");
    set_cooldown(&r, 59.0f);
    CHECK(timer_is(timer_of(&r), true, false, false, true, 59), "a whole number of seconds stays");
    set_cooldown(&r, 59.0001f);
    CHECK(timer_is(timer_of(&r), true, false, false, true, 60), "a hair over rounds up");
    set_cooldown(&r, 86399.5f);
    CHECK(timer_is(timer_of(&r), true, false, false, true, 86400), "86399.5 rounds up to the limit");
    set_cooldown(&r, 86400.0f);
    CHECK(timer_is(timer_of(&r), true, false, false, true, 86400), "86400 s (a day) is accepted");
    CHECK(DBF_VAL_TIMER_SECONDS_MAX == 86400u, "(the limit is R46's 86400)");
    set_cooldown(&r, 86400.5f);
    CHECK(no_timer(timer_of(&r)), "over a day is no timer");
    set_cooldown(&r, 1.0e9f);
    CHECK(no_timer(timer_of(&r)), "a billion seconds is no timer");

    set_cooldown(&r, 0.0f);
    CHECK(no_timer(timer_of(&r)), "0 s is no timer");
    set_cooldown(&r, -0.0f);
    CHECK(no_timer(timer_of(&r)), "-0 s is no timer");
    set_cooldown(&r, -5.0f);
    CHECK(no_timer(timer_of(&r)), "negative seconds are no timer");
    set_cooldown(&r, ninf_bits.f);
    CHECK(no_timer(timer_of(&r)), "-infinity is no timer");
    set_cooldown(&r, inf_bits.f);
    CHECK(no_timer(timer_of(&r)), "+infinity is no timer");
    set_cooldown(&r, nan_bits.f);
    CHECK(no_timer(timer_of(&r)), "NaN is no timer");
    set_cooldown(&r, snan_bits.f);
    CHECK(no_timer(timer_of(&r)), "a signalling NaN is no timer");

    set_incoming(&r, 0.0f);
    CHECK(no_timer(timer_of(&r)), "incoming 0 s is no timer");
    set_incoming(&r, nan_bits.f);
    CHECK(no_timer(timer_of(&r)), "incoming NaN is no timer");
    set_incoming(&r, 90000.0f);
    CHECK(no_timer(timer_of(&r)), "incoming over a day is no timer");
    set_incoming(&r, 0.5f);
    CHECK(timer_is(timer_of(&r), true, false, true, false, 1), "incoming 0.5 s is 1");
}

/* --- the blacklist --------------------------------------------------------------------------------------------- */

static void test_blacklisted(void)
{
    DbfSettings s = defaults();
    CHECK(!logic_blacklisted(5, &s) && !logic_blacklisted(42, &s) && !logic_blacklisted(145, &s) && !logic_blacklisted(49, &s),
          "defaults hide nothing");
    s.blacklist_kind[42] = true;
    CHECK(logic_blacklisted(42, &s), "a kind in blacklist_kind is blacklisted");
    CHECK(!logic_blacklisted(41, &s) && !logic_blacklisted(43, &s), "and its neighbours are not");
    s.blacklist_kind[199] = true;
    CHECK(logic_blacklisted(199, &s), "the last slot (199) works");
    CHECK(!logic_blacklisted(200, &s) && !logic_blacklisted(201, &s) && !logic_blacklisted(100000, &s) &&
              !logic_blacklisted(0xffffffffu, &s),
          "kinds of 200 and more cannot be blacklisted, and are not read out of the table");
    CHECK(!logic_blacklisted(0, &s), "kind 0 is not blacklisted by the table (eligibility refuses it on its own)");

    DbfSettings t = defaults();
    CHECK(DBF_VAL_HIDE_SOS_KIND == 145u && DBF_VAL_HIDE_EAGLE_REARM_KIND == 49u, "the toggles' kinds are 145 and 49");
    t.hide_sos = true;
    CHECK(logic_blacklisted(145, &t), "hide_sos blacklists the SOS Beacon (145)");
    CHECK(!logic_blacklisted(49, &t) && !logic_blacklisted(144, &t) && !logic_blacklisted(146, &t), "and nothing else");
    t.hide_sos = false;
    t.hide_eagle_rearm = true;
    CHECK(logic_blacklisted(49, &t), "hide_eagle_rearm blacklists the Eagle Rearm (49)");
    CHECK(!logic_blacklisted(145, &t) && !logic_blacklisted(48, &t) && !logic_blacklisted(50, &t), "and nothing else");
    t.hide_sos = true;
    CHECK(logic_blacklisted(145, &t) && logic_blacklisted(49, &t), "both toggles together");

    DbfSettings u = defaults();
    u.blacklist_kind[145] = true;
    CHECK(logic_blacklisted(145, &u), "the table can hide 145 on its own");
    u.blacklist_kind[145] = false;
    u.blacklist_kind[49] = true;
    CHECK(logic_blacklisted(49, &u) && !logic_blacklisted(145, &u), "and 49 on its own");

    CHECK(!logic_blacklisted(42, NULL), "no settings: nothing is blacklisted");
    CHECK(!logic_blacklisted(150, &t) && !logic_blacklisted(197, &t), "HellForge mod kinds are not hidden by default");
}

/* --- which rows --------------------------------------------------------------------------------------------- */

static void test_rows_order(void)
{
    DbfSettings s = defaults();
    int order[16];
    bool eligible[16];
    DbfRow rows[4] = { make_row(10, 0x1000, 100.0f, 0), make_row(11, 0x2000, 300.0f, 1), make_row(12, 0x3000, 200.0f, 2),
                       make_row(13, 0x4000, 400.0f, 3) };
    GameView v = make_view(rows, 4, true);
    int n = logic_list_rows(&v, &s, order, eligible);
    CHECK(n == 4, "four rows");
    CHECK(order[0] == 3 && order[1] == 1 && order[2] == 2 && order[3] == 0, "ordered by list_y, the largest (the top) first");
    CHECK(order[4] == -1 && order[15] == -1, "the rest of order is -1");
    CHECK(eligible[0] && eligible[1] && eligible[2] && eligible[3], "all four may be chosen");
    CHECK(!eligible[4] && !eligible[15], "and the rest of eligible is false");

    /* Ties: list_y, then entry ascending, then card ascending. */
    DbfRow tie[6] = { make_row(10, 0x5000, 50.0f, 4), make_row(11, 0x6000, 50.0f, 2), make_row(12, 0x3000, 50.0f, 4),
                      make_row(13, 0x1000, 90.0f, 9), make_row(14, 0x2000, 50.0f, 2), make_row(15, 0x9000, 50.0f, 7) };
    v = make_view(tie, 6, true);
    n = logic_list_rows(&v, &s, order, eligible);
    /* y 90 first (row 3); then y 50 by entry: entry 2 (rows 1 card 0x6000, 4 card 0x2000 -> card ascending: 4 then 1),
     * entry 4 (rows 0 card 0x5000, 2 card 0x3000 -> 2 then 0), entry 7 (row 5). */
    CHECK(n == 6 && order[0] == 3, "the row with the larger y first");
    CHECK(order[1] == 4 && order[2] == 1, "same y, same entry: the lower card address first");
    CHECK(order[3] == 2 && order[4] == 0, "same y: the lower entry first, then the lower card address within an entry");
    CHECK(order[5] == 5, "entry 7 after entries 2 and 4");

    /* The order of GameView.rows does not matter, and the sort does not touch it. */
    CHECK(v.rows[0].card == 0x5000 && v.rows[5].card == 0x9000, "the view's rows are not reordered");

    /* All sixteen rows, y rising with the index: reversed. */
    DbfRow all[16];
    for (int i = 0; i < 16; i++) all[i] = make_row(1 + (uint32_t)i, 0x1000 + (uintptr_t)i * 0x100, (float)i, (uint32_t)i);
    v = make_view(all, 16, true);
    n = logic_list_rows(&v, &s, order, eligible);
    bool reversed = n == 16;
    for (int i = 0; i < 16; i++) reversed &= order[i] == 15 - i && eligible[i];
    CHECK(reversed, "sixteen rows: reversed, all eligible");

    /* Counts. */
    v = make_view(all, 3, true);
    CHECK(logic_list_rows(&v, &s, NULL, NULL) == 3, "NULL arrays are allowed");
    CHECK(logic_list_rows(&v, &s, order, NULL) == 3 && order[0] == 2, "and each one alone");
    CHECK(logic_list_rows(&v, &s, NULL, eligible) == 3 && eligible[2] && !eligible[3], "(also the other)");
    v.row_count = 0;
    CHECK(logic_list_rows(&v, &s, order, eligible) == 0 && order[0] == -1 && !eligible[0], "no rows");
    v.row_count = -4;
    CHECK(logic_list_rows(&v, &s, order, eligible) == 0, "a negative count is no rows");
    v.row_count = 99;
    CHECK(logic_list_rows(&v, &s, order, eligible) == 16, "a count over 16 is cut to 16");
    CHECK(logic_list_rows(NULL, &s, order, eligible) == 0 && order[0] == -1 && !eligible[0], "no view: no rows");
}

static void test_rows_eligibility(void)
{
    DbfSettings s = defaults();
    int order[16];
    bool eligible[16];
    DbfRow rows[10];
    for (int i = 0; i < 10; i++) rows[i] = make_row(20 + (uint32_t)i, 0x1000 + (uintptr_t)i * 0x100, 1000.0f - (float)i, (uint32_t)i);
    rows[1].kind = 0;                                    /* no kind: the entry is not in the payload */
    put_u32(rows[1].timer, DBF_OFF_CARD_TIMER_KIND_OFFSET, 0);
    s.blacklist_kind[22] = true;                         /* row 2: blacklisted */
    set_cooldown(&rows[3], 20.0f);                       /* row 3: cooldown */
    set_incoming(&rows[4], 5.0f);                        /* row 4: incoming */
    set_state(&rows[5], DBF_VAL_TIMER_STATE_UNAVAILABLE); /* row 5: unavailable */
    set_cooldown(&rows[6], 0.0f);                        /* row 6: a cooldown state without seconds: unknown, not a timer */
    put_u32(rows[7].timer, DBF_OFF_CARD_TIMER_KIND_OFFSET, 3); /* row 7: a block of another kind: unknown */
    set_state(&rows[7], DBF_VAL_TIMER_STATE_COOLDOWN);
    put_f32(rows[7].timer, 8, 50.0f);
    rows[8].kind = 150;                                  /* row 8: a HellForge mod stratagem */
    put_u32(rows[8].timer, DBF_OFF_CARD_TIMER_KIND_OFFSET, 150);
    rows[9].kind = 197;                                  /* row 9: the last of them */
    put_u32(rows[9].timer, DBF_OFF_CARD_TIMER_KIND_OFFSET, 197);
    GameView v = make_view(rows, 10, true);
    int n = logic_list_rows(&v, &s, order, eligible);
    CHECK(n == 10, "all ten rows are shown, eligible or not");
    bool seen[10] = { false };
    for (int k = 0; k < n; k++) seen[order[k]] = true;
    bool all_seen = true;
    for (int i = 0; i < 10; i++) all_seen &= seen[i];
    CHECK(all_seen, "each row is in the order once");
    CHECK(eligible[0], "an ordinary row may be chosen");
    CHECK(!eligible[1], "kind 0 may not");
    CHECK(!eligible[2], "a blacklisted row is shown but may not be chosen");
    CHECK(!eligible[3], "a row on cooldown may not");
    CHECK(!eligible[4], "a row with an incoming timer may not");
    CHECK(!eligible[5], "an unavailable row may not");
    CHECK(eligible[6], "a cooldown state with unusable seconds is no timer: R46 lets it be chosen");
    CHECK(eligible[7], "a timer block of another kind says nothing: R46 lets the row be chosen");
    CHECK(eligible[8] && eligible[9], "kinds 150 and 197 (HellForge mod stratagems) may be chosen");

    s.hide_sos = true;
    DbfRow sos[2] = { make_row(145, 0x1000, 2.0f, 0), make_row(49, 0x2000, 1.0f, 1) };
    v = make_view(sos, 2, true);
    logic_list_rows(&v, &s, order, eligible);
    CHECK(!eligible[0] && eligible[1], "hide_sos: the SOS Beacon may not be chosen, the Eagle Rearm still may");
    s.hide_eagle_rearm = true;
    logic_list_rows(&v, &s, order, eligible);
    CHECK(!eligible[0] && !eligible[1], "and hide_eagle_rearm: it may not either");
    CHECK(logic_list_rows(&v, NULL, order, eligible) == 2 && eligible[0] && eligible[1],
          "no settings: only the kind and the timer decide");
}

/* --- List Select ------------------------------------------------------------------------------------------------ */

static void test_step_closed(void)
{
    DbfSettings s = defaults();
    GameView v = four_rows();
    v.menu_open = false;
    ListState st;
    memset(&st, 0, sizeof st);
    release_all();
    CHECK(step(&st, &v, &s, false) == LIST_NONE, "closed menu: nothing happens");
    CHECK(!st.was_open && st.chosen == -1 && !st.confirm_armed && st.chosen_card == 0 && st.chosen_kind == 0,
          "and the state is clear (nothing chosen, not open)");
    CHECK(g_row == -1, "*row is set to -1 when there is no confirmation");

    hold(BIND_NEXT);
    hold(BIND_CONFIRM);
    CHECK(step(&st, &v, &s, false) == LIST_NONE && !st.was_open, "levels with the menu closed do nothing");

    CHECK(logic_list_step(NULL, &v, &s, g_levels, false, &g_row) == LIST_NONE, "no state: LIST_NONE");
    CHECK(logic_list_step(&st, NULL, &s, g_levels, false, &g_row) == LIST_NONE, "no view: LIST_NONE");
    release_all();
    v.menu_open = true;
    CHECK(logic_list_step(&st, &v, &s, NULL, false, NULL) == LIST_NONE && st.was_open && st.chosen == 0,
          "no levels (all up) and no row pointer are allowed");
}

static void test_step_open_chooses_first(void)
{
    DbfSettings s = defaults();
    ListState st;
    memset(&st, 0, sizeof st);
    release_all();

    /* GameView.rows is not in list order: the first eligible row is the top one. */
    DbfRow rows[4] = { make_row(10, 0x1000, 100.0f, 0), make_row(11, 0x2000, 300.0f, 1), make_row(12, 0x3000, 200.0f, 2),
                       make_row(13, 0x4000, 400.0f, 3) };
    GameView v = make_view(rows, 4, true);
    CHECK(step(&st, &v, &s, false) == LIST_NONE, "opening is no event");
    CHECK(st.was_open && st.chosen == 3 && st.chosen_card == 0x4000 && st.chosen_kind == 13,
          "on open the first row of the list is chosen (row 3, the top by list_y), pinned by card and kind");

    /* The top row on cooldown: the first eligible one. */
    memset(&st, 0, sizeof st);
    set_cooldown(&rows[3], 30.0f);
    v = make_view(rows, 4, true);
    step(&st, &v, &s, false);
    CHECK(st.chosen == 1, "the top row is on cooldown: the next in the list is chosen");

    /* Blacklisted, unavailable, no kind: skipped too. */
    memset(&st, 0, sizeof st);
    s.blacklist_kind[11] = true;
    set_state(&rows[2], DBF_VAL_TIMER_STATE_UNAVAILABLE);
    v = make_view(rows, 4, true);
    step(&st, &v, &s, false);
    CHECK(st.chosen == 0 && st.chosen_card == 0x1000, "blacklisted, unavailable and on-cooldown rows are skipped: row 0");

    /* Nothing eligible. */
    memset(&st, 0, sizeof st);
    s.blacklist_kind[10] = true;
    v = make_view(rows, 4, true);
    CHECK(step(&st, &v, &s, false) == LIST_NONE, "nothing eligible: no event");
    CHECK(st.was_open && st.chosen == -1 && st.chosen_card == 0, "and nothing is chosen, though the list is open");
    s.blacklist_kind[10] = false;
    step(&st, &v, &s, false);
    CHECK(st.chosen == -1, "a row that becomes eligible later is not chosen by itself (R46)");
    CHECK(press(&st, &v, &s, BIND_NEXT, false) == LIST_MOVED && st.chosen == 0, "but Next chooses the first one");

    /* A zeroed state is a valid start; the one a closed step left is too. */
    ListState zero;
    memset(&zero, 0, sizeof zero);
    GameView four = four_rows();
    CHECK(step(&zero, &four, &s, false) == LIST_NONE && zero.chosen == 0, "a zeroed state opens fine");
}

static void test_step_next_previous(void)
{
    DbfSettings s = defaults();
    GameView v = four_rows();
    ListState st;
    memset(&st, 0, sizeof st);
    release_all();
    step(&st, &v, &s, false);
    CHECK(st.chosen == 0, "open: row 0");

    CHECK(press(&st, &v, &s, BIND_NEXT, false) == LIST_MOVED && st.chosen == 1, "Next: row 1");
    CHECK(press(&st, &v, &s, BIND_NEXT, false) == LIST_MOVED && st.chosen == 2, "Next: row 2");
    CHECK(press(&st, &v, &s, BIND_NEXT, false) == LIST_MOVED && st.chosen == 3, "Next: row 3");
    CHECK(press(&st, &v, &s, BIND_NEXT, false) == LIST_MOVED && st.chosen == 0, "Next at the last row wraps to the first");
    CHECK(press(&st, &v, &s, BIND_PREVIOUS, false) == LIST_MOVED && st.chosen == 3, "Previous at the first row wraps to the last");
    CHECK(press(&st, &v, &s, BIND_PREVIOUS, false) == LIST_MOVED && st.chosen == 2, "Previous: row 2");
    CHECK(st.chosen_card == 0x3000 && st.chosen_kind == 12, "and the pin follows");

    /* The list skips rows that may not be chosen. */
    set_cooldown(&v.rows[1], 10.0f);
    set_cooldown(&v.rows[3], 10.0f);
    step(&st, &v, &s, false);
    CHECK(st.chosen == 2, "(row 2 is still chosen)");
    CHECK(press(&st, &v, &s, BIND_NEXT, false) == LIST_MOVED && st.chosen == 0, "Next skips the rows on cooldown (3 is out: wraps to 0)");
    CHECK(press(&st, &v, &s, BIND_NEXT, false) == LIST_MOVED && st.chosen == 2, "Next from 0 skips row 1");
    CHECK(press(&st, &v, &s, BIND_PREVIOUS, false) == LIST_MOVED && st.chosen == 0, "Previous from 2 skips row 1");
    CHECK(press(&st, &v, &s, BIND_PREVIOUS, false) == LIST_MOVED && st.chosen == 2, "Previous from 0 wraps past row 3");
}

static void test_step_edges(void)
{
    DbfSettings s = defaults();
    GameView v = four_rows();
    ListState st;
    memset(&st, 0, sizeof st);
    release_all();
    step(&st, &v, &s, false);

    hold(BIND_NEXT);
    CHECK(step(&st, &v, &s, false) == LIST_MOVED && st.chosen == 1, "Next goes down: one move");
    CHECK(step(&st, &v, &s, false) == LIST_NONE && st.chosen == 1, "held on the next step: no move (not a rising edge)");
    for (int i = 0; i < 5; i++) step(&st, &v, &s, false);
    CHECK(st.chosen == 1, "held for many steps: still one move");
    let_go(BIND_NEXT);
    step(&st, &v, &s, false);
    hold(BIND_NEXT);
    CHECK(step(&st, &v, &s, false) == LIST_MOVED && st.chosen == 2, "let go and pressed again: another move");
    let_go(BIND_NEXT);
    step(&st, &v, &s, false);

    /* Both in one tick: neither moves. */
    hold(BIND_NEXT);
    hold(BIND_PREVIOUS);
    CHECK(step(&st, &v, &s, false) == LIST_NONE && st.chosen == 2, "Next and Previous rising together: neither moves");
    let_go(BIND_PREVIOUS);
    CHECK(step(&st, &v, &s, false) == LIST_NONE && st.chosen == 2, "Previous let go while Next is held: Next's edge is gone, no move");
    let_go(BIND_NEXT);
    step(&st, &v, &s, false);

    /* One then the other, a tick apart. */
    hold(BIND_NEXT);
    CHECK(step(&st, &v, &s, false) == LIST_MOVED && st.chosen == 3, "Next");
    hold(BIND_PREVIOUS);
    CHECK(step(&st, &v, &s, false) == LIST_MOVED && st.chosen == 2, "Previous a tick later (Next still held): its own edge moves");
    release_all();
    step(&st, &v, &s, false);

    /* The other actions are not List Select's. */
    hold(BIND_SLOT1);
    hold(BIND_SLOT2);
    hold(BIND_SLOT3);
    hold(BIND_SLOT4);
    CHECK(step(&st, &v, &s, false) == LIST_NONE && st.chosen == 2, "the slot hotkeys do nothing here");
    release_all();
    step(&st, &v, &s, false);

    /* Held while the menu was closed (or before it opened): no edge when it opens. */
    ListState st2;
    memset(&st2, 0, sizeof st2);
    GameView closed = four_rows();
    closed.menu_open = false;
    hold(BIND_NEXT);
    step(&st2, &closed, &s, false);
    CHECK(step(&st2, &v, &s, false) == LIST_NONE && st2.chosen == 0, "Next held since before the menu opened: no move at open");
    let_go(BIND_NEXT);
    step(&st2, &v, &s, false);
    CHECK(press(&st2, &v, &s, BIND_NEXT, false) == LIST_MOVED && st2.chosen == 1, "and it works once let go and pressed");

    /* A press on the tick the menu opens counts, from the first row. */
    ListState st3;
    memset(&st3, 0, sizeof st3);
    release_all();
    step(&st3, &closed, &s, false);
    hold(BIND_NEXT);
    CHECK(step(&st3, &v, &s, false) == LIST_MOVED && st3.chosen == 1, "a Next edge on the tick of opening moves from the first row");
    release_all();

    /* A press on the tick of opening, on a Previous: wraps to the last. */
    ListState st4;
    memset(&st4, 0, sizeof st4);
    step(&st4, &closed, &s, false);
    hold(BIND_PREVIOUS);
    CHECK(step(&st4, &v, &s, false) == LIST_MOVED && st4.chosen == 3, "and a Previous edge wraps to the last row");
    release_all();

    /* One eligible row: the press is heard and the row stays. */
    ListState st5;
    memset(&st5, 0, sizeof st5);
    GameView one = four_rows();
    set_cooldown(&one.rows[0], 9.0f);
    set_cooldown(&one.rows[1], 9.0f);
    set_cooldown(&one.rows[3], 9.0f);
    step(&st5, &one, &s, false);
    CHECK(st5.chosen == 2, "one eligible row: chosen at open");
    CHECK(press(&st5, &one, &s, BIND_NEXT, false) == LIST_MOVED && st5.chosen == 2, "Next with one eligible row: the press is heard, the row stays");
    CHECK(press(&st5, &one, &s, BIND_PREVIOUS, false) == LIST_MOVED && st5.chosen == 2, "so does Previous");
}

static void test_step_busy(void)
{
    DbfSettings s = defaults();
    GameView v = four_rows();
    ListState st;
    memset(&st, 0, sizeof st);
    release_all();
    step(&st, &v, &s, false);

    CHECK(press(&st, &v, &s, BIND_NEXT, true) == LIST_NONE && st.chosen == 0, "busy: Next does not move");
    CHECK(press(&st, &v, &s, BIND_PREVIOUS, true) == LIST_NONE && st.chosen == 0, "busy: Previous does not move");
    CHECK(press(&st, &v, &s, BIND_CONFIRM, true) == LIST_NONE && g_row == -1, "busy: Confirm does not confirm");

    /* The press is lost, not saved: held through the end of busy, it is not an edge any more. */
    hold(BIND_NEXT);
    hold(BIND_CONFIRM);
    CHECK(step(&st, &v, &s, true) == LIST_NONE, "busy with Next and Confirm pressed: nothing");
    CHECK(step(&st, &v, &s, false) == LIST_NONE && st.chosen == 0, "not busy any more, still held: no move, no confirm (the edge was spent)");
    release_all();
    step(&st, &v, &s, false);
    CHECK(press(&st, &v, &s, BIND_NEXT, false) == LIST_MOVED && st.chosen == 1, "and it works again after a release");

    /* The choice is still tracked while busy (it follows its card). */
    GameView moved = v;
    moved.rows[1].list_y = 1000.0f; /* the chosen row (row 1, card 0x2000) goes to the top: still row 1 */
    moved.rows[0].list_y = 50.0f;
    step(&st, &moved, &s, true);
    CHECK(st.chosen == 1 && st.chosen_card == 0x2000, "busy: the choice stays on its card");
    /* And is cleared while busy if the card goes away. */
    GameView gone = moved;
    gone.row_count = 1;
    step(&st, &gone, &s, true);
    CHECK(st.chosen == -1, "busy: a vanished card clears the choice");
}

static void test_step_confirm(void)
{
    DbfSettings s = defaults();
    GameView v = four_rows();
    ListState st;
    memset(&st, 0, sizeof st);
    release_all();
    step(&st, &v, &s, false);
    press(&st, &v, &s, BIND_NEXT, false);
    CHECK(st.chosen == 1, "(row 1 chosen)");

    hold(BIND_CONFIRM);
    CHECK(step(&st, &v, &s, false) == LIST_CONFIRM && g_row == 1, "Confirm: LIST_CONFIRM with the chosen row's index");
    CHECK(step(&st, &v, &s, false) == LIST_NONE && g_row == -1, "held: no second confirm (not a rising edge)");
    let_go(BIND_CONFIRM);
    CHECK(step(&st, &v, &s, false) == LIST_NONE, "released: nothing");
    CHECK(press(&st, &v, &s, BIND_CONFIRM, false) == LIST_CONFIRM && g_press_row == 1, "a press confirms again, with the same row");

    /* *row is an index into v->rows, not into the list order. */
    DbfRow rows[3] = { make_row(10, 0x1000, 100.0f, 0), make_row(11, 0x2000, 300.0f, 1), make_row(12, 0x3000, 200.0f, 2) };
    GameView u = make_view(rows, 3, true);
    ListState su;
    memset(&su, 0, sizeof su);
    release_all();
    step(&su, &u, &s, false);
    CHECK(su.chosen == 1, "(open: the row with the largest y is row 1)");
    hold(BIND_CONFIRM);
    CHECK(step(&su, &u, &s, false) == LIST_CONFIRM && g_row == 1, "Confirm gives the row's index in the view's rows");
    release_all();
    step(&su, &u, &s, false);
    press(&su, &u, &s, BIND_NEXT, false);
    hold(BIND_CONFIRM);
    CHECK(step(&su, &u, &s, false) == LIST_CONFIRM && g_row == 2 && su.chosen == 2, "after Next: the next row in the list (row 2)");
    release_all();
    step(&su, &u, &s, false);

    /* Nothing chosen. */
    ListState sn;
    memset(&sn, 0, sizeof sn);
    GameView none = four_rows();
    for (int i = 0; i < 4; i++) set_cooldown(&none.rows[i], 5.0f);
    step(&sn, &none, &s, false);
    CHECK(sn.chosen == -1, "(nothing chosen)");
    CHECK(press(&sn, &none, &s, BIND_CONFIRM, false) == LIST_NONE && g_row == -1, "Confirm with nothing chosen: nothing");

    /* The chosen row went on cooldown: the choice is cleared, so no confirmation. */
    GameView timed = v;
    release_all();
    ListState sc;
    memset(&sc, 0, sizeof sc);
    step(&sc, &timed, &s, false);
    set_cooldown(&timed.rows[0], 90.0f);
    hold(BIND_CONFIRM);
    CHECK(step(&sc, &timed, &s, false) == LIST_NONE && sc.chosen == -1, "the chosen row went on cooldown in the tick of the press: no confirm, choice cleared");
    release_all();
    step(&sc, &timed, &s, false);
    CHECK(press(&sc, &timed, &s, BIND_CONFIRM, false) == LIST_NONE, "and Confirm with the choice cleared does nothing");
    CHECK(press(&sc, &timed, &s, BIND_NEXT, false) == LIST_MOVED && sc.chosen == 1, "Next then chooses the first eligible row (row 0 is on cooldown)");

    /* Confirm and a move in the same tick: Confirm is for the row chosen after the move. */
    ListState sm;
    memset(&sm, 0, sizeof sm);
    release_all();
    step(&sm, &v, &s, false);
    hold(BIND_NEXT);
    hold(BIND_CONFIRM);
    CHECK(step(&sm, &v, &s, false) == LIST_CONFIRM && g_row == 1 && sm.chosen == 1,
          "Next and Confirm together: the confirmation is for the row Next moved to");
    release_all();
}

static void test_step_confirm_held_at_open(void)
{
    DbfSettings s = defaults();
    GameView v = four_rows();
    GameView closed = v;
    closed.menu_open = false;
    ListState st;
    memset(&st, 0, sizeof st);
    release_all();
    step(&st, &closed, &s, false);

    hold(BIND_CONFIRM);
    CHECK(step(&st, &v, &s, false) == LIST_NONE && g_row == -1, "Confirm held as the menu opens: nothing");
    CHECK(!st.confirm_armed, "(not armed)");
    CHECK(step(&st, &v, &s, false) == LIST_NONE, "and nothing while it stays held");
    let_go(BIND_CONFIRM);
    CHECK(step(&st, &v, &s, false) == LIST_NONE && st.confirm_armed, "let go: armed");
    hold(BIND_CONFIRM);
    CHECK(step(&st, &v, &s, false) == LIST_CONFIRM && g_row == 0, "pressed again: confirms row 0");
    release_all();
    step(&st, &v, &s, false);

    /* Confirm up at open: armed at once. */
    memset(&st, 0, sizeof st);
    step(&st, &closed, &s, false);
    step(&st, &v, &s, false);
    CHECK(st.confirm_armed, "Confirm up at open: armed from the start");
    CHECK(press(&st, &v, &s, BIND_CONFIRM, false) == LIST_CONFIRM, "and a press on the next tick confirms");

    /* Confirm pressed on the very tick of opening is a held Confirm (it opened the menu, or was pressed with it). */
    memset(&st, 0, sizeof st);
    step(&st, &closed, &s, false);
    hold(BIND_CONFIRM);
    CHECK(step(&st, &v, &s, false) == LIST_NONE, "a Confirm edge on the tick of opening does nothing");
    release_all();

    /* Closing and opening again re-arms from the levels at that moment. */
    memset(&st, 0, sizeof st);
    step(&st, &v, &s, false);
    CHECK(st.confirm_armed, "(open, armed)");
    step(&st, &closed, &s, false);
    CHECK(!st.was_open && !st.confirm_armed, "closing clears the arming");
    hold(BIND_CONFIRM);
    CHECK(step(&st, &v, &s, false) == LIST_NONE && !st.confirm_armed, "opened again with Confirm held: not armed");
    release_all();

    /* Confirm held since before the menu opened, through the menu being closed: no edge, not armed. */
    memset(&st, 0, sizeof st);
    hold(BIND_CONFIRM);
    step(&st, &closed, &s, false);
    step(&st, &closed, &s, false);
    CHECK(step(&st, &v, &s, false) == LIST_NONE, "held from before: nothing at open");
    release_all();
}

static void test_step_pinned(void)
{
    DbfSettings s = defaults();
    GameView v = four_rows();
    ListState st;
    memset(&st, 0, sizeof st);
    release_all();
    step(&st, &v, &s, false);
    press(&st, &v, &s, BIND_NEXT, false);
    press(&st, &v, &s, BIND_NEXT, false);
    CHECK(st.chosen == 2 && st.chosen_card == 0x3000, "(row 2, card 0x3000)");

    /* The list reorders: the cards swap positions in GameView.rows (the row at index 2 is now card 0x1000). */
    DbfRow reordered[4] = { v.rows[3], v.rows[1], v.rows[0], v.rows[2] };
    reordered[0].list_y = 400.0f;
    reordered[1].list_y = 300.0f;
    reordered[2].list_y = 200.0f;
    reordered[3].list_y = 100.0f;
    GameView w = make_view(reordered, 4, true);
    step(&st, &w, &s, false);
    CHECK(st.chosen == 3 && st.chosen_card == 0x3000, "the choice follows its card to its new row index (3)");
    hold(BIND_CONFIRM);
    CHECK(step(&st, &w, &s, false) == LIST_CONFIRM && g_row == 3, "and Confirm gives that index");
    release_all();
    step(&st, &w, &s, false);

    /* Moving after a reorder goes by the new order. */
    CHECK(press(&st, &w, &s, BIND_NEXT, false) == LIST_MOVED && st.chosen == 0, "Next from the last row (now 3) wraps to row 0");
    CHECK(press(&st, &w, &s, BIND_PREVIOUS, false) == LIST_MOVED && st.chosen == 3, "Previous from 0 wraps back");

    /* Positions change in y only (the cards stay at their row indices). */
    GameView x = w;
    x.rows[3].list_y = 1000.0f; /* the chosen card goes to the top of the list */
    x.rows[0].list_y = 50.0f;
    step(&st, &x, &s, false);
    CHECK(st.chosen == 3, "the choice is by card: a change of y keeps it");
    CHECK(press(&st, &x, &s, BIND_NEXT, false) == LIST_MOVED && st.chosen == 1, "Next goes by the new order (the top row is the card 0x3000: next is row 1)");

    /* A card above the chosen one is gone: the choice keeps its card and moves to its new index. */
    ListState g;
    memset(&g, 0, sizeof g);
    GameView gv = four_rows();
    release_all();
    step(&g, &gv, &s, false);
    press(&g, &gv, &s, BIND_NEXT, false);
    press(&g, &gv, &s, BIND_NEXT, false);
    CHECK(g.chosen == 2 && g.chosen_card == 0x3000, "(row 2, card 0x3000)");
    GameView above = make_view(&gv.rows[1], 3, true); /* cards 0x2000, 0x3000, 0x4000 */
    step(&g, &above, &s, false);
    CHECK(g.chosen == 1 && g.chosen_card == 0x3000, "a row above went away: the choice is the same card, now row 1");

    /* The card is gone. */
    GameView fewer = make_view(&gv.rows[3], 1, true); /* only card 0x4000 */
    step(&g, &fewer, &s, false);
    CHECK(g.chosen == -1 && g.chosen_card == 0 && g.chosen_kind == 0, "the card is gone: the choice is cleared");
    CHECK(press(&g, &fewer, &s, BIND_CONFIRM, false) == LIST_NONE, "Confirm does nothing");

    /* After that: Next picks the first, Previous the last. */
    GameView again = four_rows();
    ListState a;
    memset(&a, 0, sizeof a);
    release_all();
    step(&a, &again, &s, false);
    press(&a, &again, &s, BIND_NEXT, false);
    GameView short_list = again;
    short_list.rows[1] = short_list.rows[3];
    short_list.row_count = 3; /* rows: cards 0x1000, 0x4000, 0x3000; the chosen card 0x2000 is gone */
    step(&a, &short_list, &s, false);
    CHECK(a.chosen == -1, "(cleared)");
    CHECK(press(&a, &short_list, &s, BIND_NEXT, false) == LIST_MOVED && a.chosen == 0, "then Next chooses the first row of the list");
    ListState b;
    memset(&b, 0, sizeof b);
    step(&b, &again, &s, false);
    press(&b, &again, &s, BIND_NEXT, false);
    step(&b, &short_list, &s, false);
    CHECK(b.chosen == -1, "(cleared)");
    CHECK(press(&b, &short_list, &s, BIND_PREVIOUS, false) == LIST_MOVED && b.chosen == 1, "and Previous the last (row 1, the lowest by y)");

    /* The same card with another kind is another stratagem: cleared. */
    ListState k;
    memset(&k, 0, sizeof k);
    GameView kv = four_rows();
    step(&k, &kv, &s, false);
    GameView changed = kv;
    changed.rows[0].kind = 99;
    step(&k, &changed, &s, false);
    CHECK(k.chosen == -1, "the card's kind changed: the choice is cleared");

    /* The card is there but no longer eligible: cleared. */
    ListState e;
    memset(&e, 0, sizeof e);
    step(&e, &kv, &s, false);
    GameView cooling = kv;
    set_cooldown(&cooling.rows[0], 3.0f);
    step(&e, &cooling, &s, false);
    CHECK(e.chosen == -1, "the chosen row went on cooldown: the choice is cleared");
    release_all();
    step(&e, &kv, &s, false);
    CHECK(e.chosen == -1, "and the row that comes back is not chosen again by itself");

    /* Blacklisting the chosen kind (a setting changed with the menu open). */
    ListState bl;
    memset(&bl, 0, sizeof bl);
    DbfSettings s2 = defaults();
    step(&bl, &kv, &s2, false);
    s2.blacklist_kind[10] = true;
    step(&bl, &kv, &s2, false);
    CHECK(bl.chosen == -1, "the chosen kind was blacklisted: the choice is cleared");
}

static void test_step_close_resets(void)
{
    DbfSettings s = defaults();
    GameView v = four_rows();
    GameView closed = v;
    closed.menu_open = false;
    ListState st;
    memset(&st, 0, sizeof st);
    release_all();
    step(&st, &v, &s, false);
    press(&st, &v, &s, BIND_NEXT, false);
    press(&st, &v, &s, BIND_NEXT, false);
    CHECK(st.chosen == 2, "(row 2)");
    step(&st, &closed, &s, false);
    CHECK(!st.was_open && st.chosen == -1 && st.chosen_card == 0 && st.chosen_kind == 0 && !st.confirm_armed,
          "the menu closes: the state is reset");
    step(&st, &v, &s, false);
    CHECK(st.was_open && st.chosen == 0, "opened again: the first row, not the old one");

    /* While closed, levels still keep the edge memory but nothing moves. */
    step(&st, &closed, &s, false);
    CHECK(press(&st, &closed, &s, BIND_NEXT, false) == LIST_NONE && !st.was_open, "presses with the menu closed do nothing");
    CHECK(press(&st, &closed, &s, BIND_CONFIRM, false) == LIST_NONE, "(nor Confirm)");
}

/* --- pacing ------------------------------------------------------------------------------------------------------ */

static uint32_t g_rand_value;
static int g_rand_calls;
static uint32_t fake_random(void)
{
    g_rand_calls++;
    return g_rand_value;
}

static void test_interval(void)
{
    DbfSettings s = defaults();
    CHECK(logic_interval(&s, NULL) == 70, "the default setting is 70 ms");
    for (int ms = 0; ms <= 250; ms += 5) {
        char text[64];
        s.input_interval_ms = ms;
        snprintf(text, sizeof text, "setting %d is used as it is", ms);
        CHECK(logic_interval(&s, fake_random) == (uint32_t)ms, text);
    }
    s.input_interval_ms = 0;
    CHECK(logic_interval(&s, NULL) == 0, "0 is 0 (one direction per frame)");
    s.input_interval_ms = 251;
    CHECK(logic_interval(&s, NULL) == 250, "a setting over 250 is cut to 250");
    s.input_interval_ms = 100000;
    CHECK(logic_interval(&s, NULL) == 250, "far over: 250");
    s.input_interval_ms = -1;
    CHECK(logic_interval(&s, NULL) == 0, "negative: 0");
    s.input_interval_ms = 123;
    g_rand_calls = 0;
    g_rand_value = 9999;
    CHECK(logic_interval(&s, fake_random) == 123 && g_rand_calls == 0, "without randomize the random function is not called");

    s.randomize_input_delay = true;
    g_rand_calls = 0;
    g_rand_value = 0;
    CHECK(logic_interval(&s, fake_random) == 70 && g_rand_calls == 1, "randomize: random 0 is 70, and random is called once");
    g_rand_value = 1;
    CHECK(logic_interval(&s, fake_random) == 71, "random 1 is 71");
    g_rand_value = 170;
    CHECK(logic_interval(&s, fake_random) == 240, "random 170 is 240, the top of R46's range");
    g_rand_value = 171;
    CHECK(logic_interval(&s, fake_random) == 70, "random 171 wraps to 70");
    g_rand_value = 340;
    CHECK(logic_interval(&s, fake_random) == 239, "random 340 is 239");
    g_rand_value = 0xffffffffu;
    uint32_t r = logic_interval(&s, fake_random);
    CHECK(r >= 70 && r <= 240 && r == 70 + 0xffffffffu % 171, "the largest random is still in 70..240");
    bool in_range = true, seen_low = false, seen_high = false;
    for (uint32_t v = 0; v < 2000; v++) {
        g_rand_value = v;
        r = logic_interval(&s, fake_random);
        in_range &= r >= 70 && r <= 240;
        seen_low |= r == 70;
        seen_high |= r == 240;
    }
    CHECK(in_range && seen_low && seen_high, "over 2000 draws: always 70..240, both ends reached");
    CHECK(logic_interval(&s, NULL) == 123, "randomize with no random function: the setting");
    s.input_interval_ms = 400;
    CHECK(logic_interval(&s, NULL) == 250, "(limited, as without randomize)");
    CHECK(logic_interval(NULL, NULL) == DBF_INTERVAL_DEFAULT_MS, "no settings: the default 70");
}

static void test_deadline(void)
{
    CHECK(logic_deadline(0, 0, 1000) == 4000, "length 0, interval 0: now + 3000 (at least)");
    CHECK(logic_deadline(12, 70, 0) == 3000, "12 directions at 70 ms: 2340 ms, under the 3000 floor");
    CHECK(logic_deadline(12, 70, 5000) == 8000, "from now");
    CHECK(logic_deadline(10, 150, 0) == 3000, "len*interval + 1500 = 3000: 3000");
    CHECK(logic_deadline(10, 151, 0) == 3010, "one more ms per direction: 3010");
    CHECK(logic_deadline(12, 250, 0) == 4500, "12 at 250 ms: 3000 + 1500 = 4500");
    CHECK(logic_deadline(12, 240, 100) == 100 + 12 * 240 + 1500, "12 at 240 ms from 100");
    CHECK(logic_deadline(4, 0, 77) == 3077, "interval 0: the floor");
    CHECK(logic_deadline(0xffffffffu, 250, 0) == (uint64_t)0xffffffffu * 250u + 1500u, "no overflow with the largest length");
    CHECK(logic_deadline(1, 1, 0xfffffffffff0ull) == 0xfffffffffff0ull + 3000, "a large clock");
}

int main(void)
{
    test_timer_states();
    test_timer_fields();
    test_timer_seconds();
    test_blacklisted();
    test_rows_order();
    test_rows_eligibility();
    test_step_closed();
    test_step_open_chooses_first();
    test_step_next_previous();
    test_step_edges();
    test_step_busy();
    test_step_confirm();
    test_step_confirm_held_at_open();
    test_step_pinned();
    test_step_close_resets();
    test_interval();
    test_deadline();
    printf("%s\n", test_failures() == 0 ? "PASS test_logic" : "FAIL test_logic");
    TEST_MAIN_END
}
