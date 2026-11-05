/* Tests for bind_poll (src/bindings.c) chained into logic_list_step (src/logic.c), as the tick will chain them: the levels
 * one gives are the edges the other takes. bindings and logic each have tests of their own; these are the rules that only
 * hold when the two work together: a wheel notch is a move however many arrive at once, and a Confirm held while nothing
 * could fire (a blocked tick, the menu opening) never confirms. The BindPort is a fake; the wheel total is the Overlay
 * Host's (120 units a notch, + up); the default bindings (next = wheel_down, previous = wheel_up, confirm = mouse1). */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "bindings.h"
#include "game.h"
#include "logic.h"
#include "settings.h"
#include "test.h"

/* --- the fake port and the tick -------------------------------------------------------------------------------- */

static bool g_keys[256];
static int64_t g_total;

static bool fake_key_down(uint16_t vk) { return vk < 256 && g_keys[vk]; }
static bool fake_foreground(void) { return true; }
static bool fake_wheel_total(int64_t* total)
{
    *total = g_total;
    return true;
}

static const BindPort g_port = { fake_key_down, fake_foreground, fake_wheel_total, NULL };

#define VK_LBUTTON 0x01 /* mouse1, as bindings.c reads it */

static void turn(int notches) { g_total += (int64_t)notches * 120; }

static DbfSettings g_settings;
static GameView g_view;
static ListState g_st;
static int g_row;

static DbfRow make_row(uint32_t kind, uintptr_t card, float y, uint32_t entry)
{
    DbfRow r;
    memset(&r, 0, sizeof r);
    r.card = card;
    r.list_y = y;
    r.kind = kind;
    r.entry = entry;
    r.active = true;
    memcpy(r.timer + DBF_OFF_CARD_TIMER_KIND_OFFSET, &kind, sizeof kind);
    return r;
}

/* Eight rows, row i at the i-th place of the list (kind 10 + i, card 0x1000 + 0x100 * i), the menu open or closed. */
static void make_view(bool open)
{
    memset(&g_view, 0, sizeof g_view);
    g_view.build_ok = g_view.in_gameplay = g_view.hud_ready = true;
    g_view.menu_open = open;
    g_view.row_count = 8;
    for (int i = 0; i < 8; i++) g_view.rows[i] = make_row(10 + (uint32_t)i, 0x1000 + (uintptr_t)i * 0x100, 800.0f - 100.0f * (float)i, (uint32_t)i);
}

/* A new session: fake and module reset, the default bindings, a list state of its own. Nothing is polled yet. */
static void begin(bool open)
{
    memset(g_keys, 0, sizeof g_keys);
    g_total = 0;
    settings_defaults(&g_settings);
    make_view(open);
    memset(&g_st, 0, sizeof g_st);
    bind_init(&g_port, g_settings.bind);
}

/* One tick: bind_poll (`allowed` is the caller's gate), then logic_list_step with its levels. */
static ListEvent tick(bool allowed)
{
    bool levels[BIND_COUNT];
    bind_poll(levels, allowed, NULL, 0);
    g_row = 12345;
    return logic_list_step(&g_st, &g_view, &g_settings, levels, false, &g_row);
}

/* `n` ticks with nothing new; counts the moves and the confirmations. */
static int g_moves, g_confirms;
static void run(int n, bool allowed)
{
    for (int i = 0; i < n; i++) {
        ListEvent e = tick(allowed);
        g_moves += e == LIST_MOVED;
        g_confirms += e == LIST_CONFIRM;
    }
}

/* --- the wheel ------------------------------------------------------------------------------------------------- */

static void test_wheel_burst(void)
{
    begin(true);
    run(2, true);
    CHECK(g_st.was_open && g_st.chosen == 0, "the menu is open and the first row is chosen");

    g_moves = g_confirms = 0;
    turn(-3); /* three notches down between two ticks */
    run(10, true);
    CHECK(g_moves == 3, "three wheel-down notches between two ticks are three moves over the following ticks");
    CHECK(g_st.chosen == 3 && g_st.chosen_card == 0x1300, "and the choice went from row 0 to row 3");
    CHECK(g_confirms == 0, "(no confirmation)");

    g_moves = 0;
    run(10, true);
    CHECK(g_moves == 0 && g_st.chosen == 3, "and then nothing more");

    /* The same, one tick at a time, to see where the moves land. */
    begin(true);
    run(2, true);
    turn(-3);
    int chosen[8] = { 0 };
    ListEvent events[8];
    for (int i = 0; i < 8; i++) {
        events[i] = tick(true);
        chosen[i] = g_st.chosen;
    }
    CHECK(events[0] == LIST_MOVED && events[1] == LIST_NONE && events[2] == LIST_MOVED && events[3] == LIST_NONE &&
              events[4] == LIST_MOVED && events[5] == LIST_NONE && events[6] == LIST_NONE,
          "the moves come on every other tick: move, none, move, none, move");
    CHECK(chosen[0] == 1 && chosen[2] == 2 && chosen[4] == 3 && chosen[7] == 3, "row 1, then 2, then 3");

    /* Up: Previous, with a wrap. */
    begin(true);
    run(2, true);
    turn(2);
    g_moves = 0;
    run(8, true);
    CHECK(g_moves == 2 && g_st.chosen == 6, "two wheel-up notches from row 0: two moves, wrapping to row 6 (0 -> 7 -> 6)");

    /* A big burst. */
    begin(true);
    run(2, true);
    turn(-7);
    g_moves = 0;
    run(20, true);
    CHECK(g_moves == 7 && g_st.chosen == 7, "seven notches: seven moves, to the last row");
    turn(-1);
    g_moves = 0;
    run(4, true);
    CHECK(g_moves == 1 && g_st.chosen == 0, "and one more wraps to the first");
}

static void test_wheel_one_notch_per_tick(void)
{
    begin(true);
    run(2, true);
    g_moves = g_confirms = 0;
    for (int i = 0; i < 3; i++) {
        turn(-1); /* one notch each tick */
        ListEvent e = tick(true);
        g_moves += e == LIST_MOVED;
        g_confirms += e == LIST_CONFIRM;
    }
    run(10, true);
    CHECK(g_moves == 3, "one notch per tick for three ticks: three moves");
    CHECK(g_st.chosen == 3, "to row 3");

    /* Notches both ways in a row: down, up, down. */
    begin(true);
    run(2, true);
    g_moves = 0;
    turn(-1);
    run(3, true);
    turn(1);
    run(3, true);
    turn(-1);
    run(3, true);
    CHECK(g_moves == 3 && g_st.chosen == 1, "down, up, down: three moves, ending on row 1");

    /* A single notch: one move. */
    begin(true);
    run(2, true);
    g_moves = 0;
    turn(-1);
    run(6, true);
    CHECK(g_moves == 1 && g_st.chosen == 1, "one notch: one move");
}

static void test_wheel_when_blocked(void)
{
    begin(true);
    run(2, true);
    g_moves = 0;
    turn(-3);
    run(4, false);
    run(6, true);
    CHECK(g_moves == 0 && g_st.chosen == 0, "notches turned while nothing could fire are gone: no move later");
    turn(-1);
    run(4, true);
    CHECK(g_moves == 1 && g_st.chosen == 1, "and the next one moves");
}

/* --- Confirm ----------------------------------------------------------------------------------------------------- */

static void test_confirm_basic(void)
{
    begin(true);
    run(2, true);
    g_confirms = 0;
    g_keys[VK_LBUTTON] = true;
    CHECK(tick(true) == LIST_CONFIRM && g_row == 0, "a press of mouse1 with the menu open confirms the chosen row");
    CHECK(tick(true) == LIST_NONE, "held: no second confirmation");
    g_keys[VK_LBUTTON] = false;
    run(2, true);
    g_keys[VK_LBUTTON] = true;
    CHECK(tick(true) == LIST_CONFIRM && g_row == 0, "let go and pressed again: another one");
    g_keys[VK_LBUTTON] = false;
    run(2, true);

    turn(-2);
    run(6, true);
    g_keys[VK_LBUTTON] = true;
    CHECK(tick(true) == LIST_CONFIRM && g_row == 2, "after two wheel notches the press confirms row 2");
}

static void test_confirm_held_across_a_block(void)
{
    begin(true);
    run(2, true);
    g_confirms = 0;
    g_keys[VK_LBUTTON] = true;
    CHECK(tick(true) == LIST_CONFIRM, "(a press confirms)");
    tick(true);

    /* Held while the tick is blocked (a window open, the game's UI in the way), and still held when it ends. */
    tick(false);
    tick(false);
    g_confirms = 0;
    run(5, true);
    CHECK(g_confirms == 0, "Confirm held across a blocked -> allowed transition: no confirmation");
    g_keys[VK_LBUTTON] = false;
    run(3, true);
    CHECK(g_confirms == 0, "and none when it is let go");
    g_keys[VK_LBUTTON] = true;
    CHECK(tick(true) == LIST_CONFIRM, "until it is pressed again");

    /* Pressed while blocked, let go and pressed again while still blocked: the block hid all of it. */
    begin(true);
    run(2, true);
    g_keys[VK_LBUTTON] = true;
    tick(false);
    g_keys[VK_LBUTTON] = false;
    tick(false);
    g_keys[VK_LBUTTON] = true;
    g_confirms = 0;
    run(3, true);
    CHECK(g_confirms == 0, "pressed while blocked and still held when the block ends: no confirmation");

    /* Not held when the block ends: it works the moment it is pressed. */
    begin(true);
    run(2, true);
    tick(false);
    tick(false);
    run(2, true);
    g_keys[VK_LBUTTON] = true;
    CHECK(tick(true) == LIST_CONFIRM && g_row == 0, "a Confirm not held when the block ended works as soon as it is pressed");
}

static void test_confirm_held_at_open(void)
{
    /* Held while the menu was closed (the ticks were allowed), still held when it opens. */
    begin(false);
    run(2, true);
    g_keys[VK_LBUTTON] = true;
    run(3, true);
    g_view.menu_open = true;
    g_confirms = 0;
    run(4, true);
    CHECK(g_st.was_open && g_confirms == 0, "the menu opens with Confirm held: no confirmation");
    g_keys[VK_LBUTTON] = false;
    run(2, true);
    CHECK(g_confirms == 0, "and none when it is let go");
    g_keys[VK_LBUTTON] = true;
    CHECK(tick(true) == LIST_CONFIRM && g_row == 0, "until it is pressed again");

    /* Pressed on the very tick the menu opens (a press that opened it, or was made with it). */
    begin(false);
    run(2, true);
    g_keys[VK_LBUTTON] = true;
    g_view.menu_open = true;
    g_confirms = 0;
    run(3, true);
    CHECK(g_confirms == 0, "Confirm pressed on the tick the menu opens: no confirmation");
    g_keys[VK_LBUTTON] = false;
    run(2, true);
    g_keys[VK_LBUTTON] = true;
    CHECK(tick(true) == LIST_CONFIRM, "the next press confirms");

    /* Held from before the module started, the menu already open on the first tick. */
    begin(true);
    g_keys[VK_LBUTTON] = true;
    g_confirms = 0;
    run(4, true);
    CHECK(g_confirms == 0, "Confirm held since before bind_init, menu open: no confirmation");
    g_keys[VK_LBUTTON] = false;
    run(2, true);
    g_keys[VK_LBUTTON] = true;
    CHECK(tick(true) == LIST_CONFIRM, "pressed again after a release: it confirms");

    /* The menu opens while the ticks are blocked (the opening click was taken by the UI) and Confirm is held. */
    begin(false);
    run(2, true);
    g_keys[VK_LBUTTON] = true;
    tick(false);
    g_view.menu_open = true;
    tick(false);
    g_confirms = 0;
    run(4, true);
    CHECK(g_confirms == 0, "the menu opens during a block with Confirm held: no confirmation after it");
    g_keys[VK_LBUTTON] = false;
    run(2, true);
    g_keys[VK_LBUTTON] = true;
    CHECK(tick(true) == LIST_CONFIRM, "and the next press confirms");
}

static void test_confirm_and_wheel_together(void)
{
    /* A burst of notches and a Confirm press between them: Confirm is for the row chosen at that tick. */
    begin(true);
    run(2, true);
    turn(-3);
    ListEvent first = tick(true); /* the first move: row 1 */
    tick(true);
    g_keys[VK_LBUTTON] = true;
    ListEvent e = tick(true); /* the second move happens this tick (pulse), and the press confirms the row after it */
    CHECK(first == LIST_MOVED && e == LIST_CONFIRM && g_row == 2, "Confirm pressed as the second notch lands confirms row 2");
}

int main(void)
{
    test_wheel_burst();
    test_wheel_one_notch_per_tick();
    test_wheel_when_blocked();
    test_confirm_basic();
    test_confirm_held_across_a_block();
    test_confirm_held_at_open();
    test_confirm_and_wheel_together();
    printf("%s\n", test_failures() == 0 ? "PASS test_list_input" : "FAIL test_list_input");
    TEST_MAIN_END
}
