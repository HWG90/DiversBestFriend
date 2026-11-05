/* Tests for src/ui_list.c, the plain list drawn on the HUD, against the fake OvApi of tests/fake_ov.c: the test builds a
 * DbfSnapshot by hand, draws it into a 1920 x 1080 frame and reads the rect and text calls the list made. The fake's theme
 * gives every token a colour of its own (fake_ov_theme_color), so a colour in the log names the token it came from. */
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "fake_ov.h"
#include "goose_overlay.h"
#include "snapshot.h"
#include "test.h"
#include "ui_list.h"

static DbfSnapshot g_snap;
static OvFrame g_frame = { 1920.0f, 1080.0f, 1.0f / 60.0f, 1.0, 1.0f, 0 };

#define NAME0 "Eagle 500kg Bomb"
#define NAME1 "Orbital Precision Strike"
#define NAME2 "Orbital Gatling Barrage"
#define NAME3 "Stratagem 150"
#define NAME4 "Extraction Beacon"

static void put_row(ListRowView* r, uint32_t kind, const char* name, const uint8_t* code, int n, bool eligible)
{
    memset(r, 0, sizeof *r);
    r->kind = kind;
    snap_copy_text(r->name, sizeof r->name, name);
    r->code_len = (uint8_t)n;
    if (n > 0) memcpy(r->code, code, (size_t)n < sizeof r->code ? (size_t)n : sizeof r->code);
    r->eligible = eligible;
}

/* A mission with the menu open and DBF on: five rows in list order. Row 1 is chosen. Row 2 is on a 45 s cooldown, row 3 (a
 * HellForge kind with no code) is unavailable, row 4 has nothing against it. No job is running. */
static void sample(DbfSnapshot* s)
{
    static const uint8_t bomb[5] = { 1, 2, 3, 3, 3 };
    static const uint8_t ops[3] = { 2, 2, 1 };
    static const uint8_t gatling[5] = { 2, 3, 4, 1, 1 };
    static const uint8_t beacon[4] = { 1, 2, 4, 3 };
    ListView* l = &s->list;
    memset(s, 0, sizeof *s);
    s->game.in_gameplay = true;
    s->game.hud_ready = true;
    s->game.menu_open = true;
    l->valid = true;
    l->enabled = true;
    l->row_count = 5;
    put_row(&l->rows[0], 3, NAME0, bomb, 5, true);
    put_row(&l->rows[1], 118, NAME1, ops, 3, true);
    put_row(&l->rows[2], 4, NAME2, gatling, 5, false);
    l->rows[2].timer.valid = true;
    l->rows[2].timer.cooldown = true;
    l->rows[2].timer.seconds = 45;
    put_row(&l->rows[3], 150, NAME3, NULL, 0, false);
    l->rows[3].timer.valid = true;
    l->rows[3].timer.unavailable = true;
    put_row(&l->rows[4], 7, NAME4, beacon, 4, true);
    l->chosen = 1;
    l->entry_state = ENTRY_IDLE;
}

static void draw_in(const OvFrame* f, const DbfSnapshot* s, bool old_host)
{
    fake_ov_reset();
    if (old_host) fake_ov_set_old_host(1);
    ui_list_draw(fake_ov_api(), f, s);
}

static void draw(const DbfSnapshot* s) { draw_in(&g_frame, s, false); }

/* "dtext:<colour of theme token>:<text>" */
static void dtext(char* out, size_t size, int token, const char* text)
{
    snprintf(out, size, "dtext:%08X:%s", (unsigned)fake_ov_theme_color(token), text);
}

static int find_dtext(int token, const char* text)
{
    char line[300];
    dtext(line, sizeof line, token, text);
    return fake_ov_find(line, 0);
}

static bool has_dtext(int token, const char* text)
{
    if (find_dtext(token, text) >= 0) return true;
    printf("  missing dtext in token %d: \"%s\"\n", token, text);
    return false;
}

static bool has_no_dtext(int token, const char* text)
{
    if (find_dtext(token, text) < 0) return true;
    printf("  unexpected dtext in token %d: \"%s\"\n", token, text);
    return false;
}

static bool drew_nothing(void)
{
    if (fake_ov_lines() == 0) return true;
    printf("  %d lines were drawn; the first is \"%s\"\n", fake_ov_lines(), fake_ov_line(0));
    return false;
}

/* The line number of the first dtext whose text is `text` (any colour), or -1. */
static int find_text(const char* text)
{
    size_t n = strlen(text);
    for (int i = 0; i < fake_ov_lines(); i++) {
        const char* line = fake_ov_line(i);
        size_t length = strlen(line);
        if (strncmp(line, "dtext:", 6) == 0 && length >= 15 + n && strcmp(line + 15, text) == 0) return i;
    }
    return -1;
}

/* --- tests ----------------------------------------------------------------------------------------------------- */

static void test_draws_nothing(void)
{
    sample(&g_snap);
    draw(&g_snap);
    CHECK(fake_ov_lines() > 0, "(control) the sample draws something");

    ui_list_draw(NULL, &g_frame, &g_snap);
    CHECK(true, "no API: nothing happens");
    fake_ov_reset();
    ui_list_draw(fake_ov_api(), NULL, &g_snap);
    CHECK(drew_nothing(), "no frame: nothing is drawn");
    fake_ov_reset();
    ui_list_draw(fake_ov_api(), &g_frame, NULL);
    CHECK(drew_nothing(), "no snapshot: nothing is drawn");

    sample(&g_snap);
    g_snap.game.in_gameplay = false;
    draw(&g_snap);
    CHECK(drew_nothing(), "not in gameplay: nothing is drawn");

    sample(&g_snap);
    g_snap.game.hud_ready = false;
    draw(&g_snap);
    CHECK(drew_nothing(), "the HUD not ready: nothing is drawn");

    sample(&g_snap);
    g_snap.game.menu_open = false;
    draw(&g_snap);
    CHECK(drew_nothing(), "the menu closed: nothing is drawn");

    sample(&g_snap);
    g_snap.list.enabled = false;
    draw(&g_snap);
    CHECK(drew_nothing(), "DBF off in the settings: nothing is drawn");

    sample(&g_snap);
    g_snap.list.valid = false;
    draw(&g_snap);
    CHECK(drew_nothing(), "a snapshot whose list was never filled: nothing is drawn");

    sample(&g_snap);
    g_snap.list.row_count = 0;
    draw(&g_snap);
    CHECK(drew_nothing(), "no rows: no empty plate");

    sample(&g_snap);
    g_snap.list.row_count = -3;
    draw(&g_snap);
    CHECK(drew_nothing(), "a negative row count draws nothing");
}

static void test_widget_calls_absent(void)
{
    sample(&g_snap);
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("text:") == 0 && fake_ov_count_prefix("separator") == 0 && fake_ov_count_prefix("tab") == 0,
          "a HUD list uses draw calls only: no widget text, separator or tab");
    CHECK(fake_ov_count_prefix("rect:") >= 1 && fake_ov_count_prefix("dtext:") >= 1, "it draws a rect and text");
}

static void test_plate(void)
{
    float g[5];
    char first[40];
    sample(&g_snap);
    draw(&g_snap);
    snprintf(first, sizeof first, "rect:%08X", (unsigned)fake_ov_theme_color(OV_THEME_PANEL));
    CHECK(strcmp(fake_ov_line(0), first) == 0, "the first thing drawn is the plate, in the theme's panel colour");
    CHECK(fake_ov_count_prefix(first) == 1, "and there is only one plate");
    CHECK(fake_ov_geom(0, g), "the plate has numbers");
    CHECK(g[4] == 6.0f, "its corners are 6 px at scale 1 (DESIGN.md hud_plate_rounding)");
    CHECK(g[0] >= 0.0f && g[2] <= 1920.0f / 3.0f, "it lies in the left third of the screen");
    CHECK(g[1] >= 0.0f && g[3] <= 1080.0f && g[3] > g[1] && g[2] > g[0], "and on the screen, with a size");
}

static void test_plate_is_centred(void)
{
    float g[5];
    OvFrame tall = { 1920.0f, 1440.0f, 1.0f / 60.0f, 1.0, 1.0f, 0 };
    sample(&g_snap);
    draw(&g_snap);
    fake_ov_geom(0, g);
    CHECK(fabsf(g[1] - (1080.0f - g[3])) < 0.01f, "the plate is centred up and down: as far from the top as from the bottom");
    draw_in(&tall, &g_snap, false);
    fake_ov_geom(0, g);
    CHECK(fabsf(g[1] - (1440.0f - g[3])) < 0.01f, "on a taller frame too");
}

static void test_everything_inside_the_plate(void)
{
    float plate[5], g[5];
    bool inside = true;
    sample(&g_snap);
    draw(&g_snap);
    fake_ov_geom(0, plate);
    for (int i = 1; i < fake_ov_lines(); i++) {
        if (!fake_ov_geom(i, g)) continue;
        if (strncmp(fake_ov_line(i), "dtext:", 6) == 0) {
            if (g[0] < plate[0] || g[1] < plate[1] || g[1] > plate[3]) inside = false;
            /* the text ends inside the plate: its width is size / 2 per byte in the fake */
            if (g[0] + (float)strlen(fake_ov_line(i) + 15) * g[2] * 0.5f > plate[2]) inside = false;
        } else if (g[0] < plate[0] || g[1] < plate[1] || g[2] > plate[2] || g[3] > plate[3]) {
            inside = false;
        }
    }
    CHECK(inside, "every text and bar lies inside the plate");
}

static void test_rows_in_order(void)
{
    static const char* const names[5] = { NAME0, NAME1, NAME2, NAME3, NAME4 };
    int at[5];
    float g[5], previous_y = -1.0f, first_x = 0.0f, pitch = 0.0f;
    bool ordered = true, same_x = true, even = true;
    sample(&g_snap);
    draw(&g_snap);
    for (int i = 0; i < 5; i++) at[i] = find_text(names[i]);
    for (int i = 0; i < 5; i++) {
        float y, x;
        if (at[i] < 0) {
            printf("  no row named \"%s\"\n", names[i]);
            ordered = false;
            continue;
        }
        fake_ov_geom(at[i], g);
        x = g[0];
        y = g[1];
        if (i > 0 && at[i] < at[i - 1]) ordered = false; /* drawn in list order */
        if (i == 0) first_x = x;
        if (x != first_x) same_x = false;
        if (i > 0 && y <= previous_y) ordered = false;   /* and lower on the screen each time */
        if (i == 1) pitch = y - previous_y;
        if (i > 1 && fabsf((y - previous_y) - pitch) > 0.001f) even = false;
        previous_y = y;
    }
    CHECK(at[0] >= 0 && at[1] >= 0 && at[2] >= 0 && at[3] >= 0 && at[4] >= 0, "all five names are drawn");
    CHECK(ordered, "in the order of the list, one below the other");
    CHECK(same_x, "starting at the same x");
    CHECK(even, "and an even distance apart");
    CHECK(pitch > 22.0f, "which leaves a gap between the lines (the text is 22 px high at scale 1)");
}

static void test_columns_line_up(void)
{
    float g[5];
    float code_x = -1.0f, timer_x = -1.0f, name_x = -1.0f;
    bool codes_align = true, timers_align = true;
    sample(&g_snap);
    draw(&g_snap);
    fake_ov_geom(find_text(NAME0), g);
    name_x = g[0];
    {
        const char* codes[5] = { "^ > v v v", "> > ^", "> v < ^ ^", "no code", "^ > < v" };
        for (int i = 0; i < 5; i++) {
            int at = find_text(codes[i]);
            if (at < 0) {
                printf("  no code \"%s\"\n", codes[i]);
                codes_align = false;
                continue;
            }
            fake_ov_geom(at, g);
            if (code_x < 0.0f) code_x = g[0];
            if (g[0] != code_x) codes_align = false;
        }
    }
    CHECK(codes_align, "the codes start at one x in every row");
    CHECK(code_x > name_x + (float)strlen(NAME1) * 11.0f, "to the right of the longest name");
    {
        int a = find_text("45s"), b = find_text("unavailable");
        if (a >= 0 && b >= 0) {
            fake_ov_geom(a, g);
            timer_x = g[0];
            fake_ov_geom(b, g);
            timers_align = g[0] == timer_x;
        } else {
            timers_align = false;
        }
    }
    CHECK(timers_align, "the timers start at one x");
    CHECK(timer_x > code_x + 9.0f * 11.0f, "to the right of the longest code");
}

static void test_colours(void)
{
    sample(&g_snap);
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_TEXT, NAME0), "an eligible row's name is the theme's text colour");
    CHECK(has_dtext(OV_THEME_ACCENT, NAME1), "the chosen row's name is the accent");
    CHECK(has_dtext(OV_THEME_TEXT_OFF, NAME2), "a row on cooldown is dimmed (text_off)");
    CHECK(has_dtext(OV_THEME_TEXT_OFF, NAME3), "so is an unavailable one");
    CHECK(has_dtext(OV_THEME_TEXT, NAME4), "a row after them is plain again");
    CHECK(has_dtext(OV_THEME_TEXT, "^ > v v v"), "an eligible row's code has the text colour too");
    CHECK(has_dtext(OV_THEME_ACCENT, "> > ^"), "the chosen row's code is the accent");
    CHECK(has_dtext(OV_THEME_TEXT_OFF, "> v < ^ ^"), "a dimmed row's code is dimmed");
    CHECK(has_dtext(OV_THEME_TEXT_OFF, "no code"), "a row with no code says so, dimmed here");
    CHECK(has_dtext(OV_THEME_TEXT_OFF, "45s") && has_dtext(OV_THEME_TEXT_OFF, "unavailable"), "and so are the timers");
}

static void test_old_host_dimming(void)
{
    char needle[16];
    sample(&g_snap);
    draw_in(&g_frame, &g_snap, true);
    CHECK(fake_ov_theme_color(OV_THEME_TEXT_OFF) == 0xFFFFFFFFu, "(control) an old host answers 0xFFFFFFFF for text_off");
    CHECK(has_dtext(OV_THEME_TEXT_DIM, NAME2) && has_dtext(OV_THEME_TEXT_DIM, NAME3),
          "a host before 0.4.0: dimmed rows fall back to text_dim");
    CHECK(has_dtext(OV_THEME_TEXT_DIM, "45s"), "and their timers");
    CHECK(has_dtext(OV_THEME_ACCENT, NAME1) && has_dtext(OV_THEME_TEXT, NAME0), "the other colours are unchanged");
    snprintf(needle, sizeof needle, "%08X", 0xFFFFFFFFu);
    {
        bool white = false;
        for (int i = 0; i < fake_ov_lines(); i++)
            if (strstr(fake_ov_line(i), needle) != NULL) white = true;
        CHECK(!white, "nothing is drawn in the 0xFFFFFFFF an old host answers");
    }
}

static void test_only_theme_colours(void)
{
    bool all = true;
    sample(&g_snap);
    g_snap.list.entry_state = ENTRY_RUNNING;
    g_snap.list.entry_kind = 3;
    g_snap.list.entry_sent = 2;
    g_snap.list.entry_len = 5;
    draw(&g_snap);
    for (int i = 0; i < fake_ov_lines(); i++) {
        const char* line = fake_ov_line(i);
        unsigned colour = 0;
        bool known = false;
        const char* hex = strncmp(line, "rect:", 5) == 0 ? line + 5 : strncmp(line, "dtext:", 6) == 0 ? line + 6 : NULL;
        if (hex == NULL) continue;
        sscanf(hex, "%8x", &colour);
        for (int t = 0; t <= OV_THEME_ACCENT_PRESS; t++)
            if (fake_ov_theme_color(t) == colour) known = true;
        if (!known) {
            printf("  line %d has a colour that is no theme token: %s\n", i, line);
            all = false;
        }
    }
    CHECK(all, "every colour drawn is one theme() answered, never a literal");
}

static void test_codes_and_timers_text(void)
{
    sample(&g_snap);
    g_snap.list.rows[4].timer.valid = true;
    g_snap.list.rows[4].timer.incoming = true;
    g_snap.list.rows[4].timer.seconds = 7;
    g_snap.list.rows[0].code[2] = 9; /* not a direction */
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_TEXT, "^ > ? v v"), "a direction that is none of 1 to 4 shows as ?");
    CHECK(has_dtext(OV_THEME_TEXT, "7s"), "an incoming timer shows its seconds");
    CHECK(has_dtext(OV_THEME_TEXT_OFF, "45s"), "so does a cooldown");
}

static void test_timer_text_edges(void)
{
    sample(&g_snap);
    g_snap.list.rows[4].timer.valid = true;
    g_snap.list.rows[4].timer.cooldown = true;
    g_snap.list.rows[4].timer.seconds = 86400;
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_TEXT, "86400s"), "the largest timer is written whole");

    sample(&g_snap);
    g_snap.list.rows[4].timer.valid = true;
    g_snap.list.rows[4].timer.cooldown = true;
    g_snap.list.rows[4].timer.seconds = 0;
    draw(&g_snap);
    CHECK(find_text("0s") < 0, "a timer of 0 seconds (no timer) shows nothing");

    sample(&g_snap);
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("dtext:") == 5 + 5 + 2, "rows with no timer have no timer text: names, codes and two timers");
}

static void test_chosen_bar(void)
{
    char accent[24];
    float bar[5], name[5];
    int found = -1, count = 0;
    sample(&g_snap);
    draw(&g_snap);
    snprintf(accent, sizeof accent, "rect:%08X", (unsigned)fake_ov_theme_color(OV_THEME_ACCENT));
    for (int i = 0; i < fake_ov_lines(); i++)
        if (strcmp(fake_ov_line(i), accent) == 0) {
            found = i;
            count++;
        }
    CHECK(count == 1, "the chosen row has one accent bar");
    if (found >= 0) {
        fake_ov_geom(found, bar);
        fake_ov_geom(find_text(NAME1), name);
        CHECK(bar[2] - bar[0] == 3.0f, "3 px wide (DESIGN.md selected_bar)");
        CHECK(bar[1] <= name[1] && bar[3] >= name[1] + 22.0f, "spanning the row's text");
        CHECK(bar[0] < name[0], "to the left of the text");
    }
}

static void test_chosen_wins_over_dim(void)
{
    sample(&g_snap);
    g_snap.list.chosen = 2; /* the row on cooldown: List Select never leaves it chosen, but if a snapshot says so */
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_ACCENT, NAME2) && has_dtext(OV_THEME_ACCENT, "> v < ^ ^"), "the chosen row is the accent, dimmed or not");
}

static void test_nothing_chosen(void)
{
    char accent_rect[24], accent_text[24];
    sample(&g_snap);
    g_snap.list.chosen = -1;
    draw(&g_snap);
    snprintf(accent_rect, sizeof accent_rect, "rect:%08X", (unsigned)fake_ov_theme_color(OV_THEME_ACCENT));
    snprintf(accent_text, sizeof accent_text, "dtext:%08X", (unsigned)fake_ov_theme_color(OV_THEME_ACCENT));
    CHECK(fake_ov_count_prefix(accent_rect) == 0 && fake_ov_count_prefix(accent_text) == 0, "nothing chosen: no accent at all");
    CHECK(has_dtext(OV_THEME_TEXT, NAME1), "the row is a plain eligible one");

    sample(&g_snap);
    g_snap.list.chosen = 99;
    draw(&g_snap);
    CHECK(fake_ov_count_prefix(accent_rect) == 0 && fake_ov_count_prefix(accent_text) == 0,
          "a chosen row past the rows highlights nothing");
    sample(&g_snap);
    g_snap.list.chosen = -7;
    draw(&g_snap);
    CHECK(fake_ov_count_prefix(accent_rect) == 0 && fake_ov_count_prefix(accent_text) == 0, "and a negative one");
}

static void test_progress(void)
{
    float first[5], rest[5];
    int a, b;
    sample(&g_snap);
    g_snap.list.entry_state = ENTRY_RUNNING;
    g_snap.list.entry_kind = 118; /* the chosen row */
    g_snap.list.entry_len = 3;

    g_snap.list.entry_sent = 1;
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_ACCENT, ">") && has_dtext(OV_THEME_TEXT, " > ^"),
          "one direction sent: it is filled (accent) and the rest follows in the text colour");
    a = find_dtext(OV_THEME_ACCENT, ">");
    b = find_dtext(OV_THEME_TEXT, " > ^");
    if (a >= 0 && b >= 0) {
        fake_ov_geom(a, first);
        fake_ov_geom(b, rest);
        CHECK(rest[0] == first[0] + 11.0f && rest[1] == first[1], "the rest starts where the sent part ends, on its line");
    }
    CHECK(has_no_dtext(OV_THEME_ACCENT, "> > ^"), "the whole code is no longer one accent text");

    g_snap.list.entry_sent = 2;
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_ACCENT, "> >") && has_dtext(OV_THEME_TEXT, " ^"), "two sent");

    g_snap.list.entry_sent = 3;
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_ACCENT, "> > ^") && fake_ov_count_prefix("dtext:") == 12, "all sent: the whole code is accent");

    g_snap.list.entry_sent = 9;
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_ACCENT, "> > ^"), "more sent than the code has counts as all of it");

    g_snap.list.entry_sent = 0;
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_TEXT, "> > ^") && has_dtext(OV_THEME_ACCENT, NAME1),
          "none sent yet: the chosen row's code is plain, so the first filled direction will show");
}

static void test_progress_on_another_row(void)
{
    sample(&g_snap);
    g_snap.list.entry_state = ENTRY_RUNNING;
    g_snap.list.entry_kind = 3; /* row 0: not the chosen one (a slot hotkey's job) */
    g_snap.list.entry_len = 5;
    g_snap.list.entry_sent = 2;
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_ACCENT, "^ >") && has_dtext(OV_THEME_TEXT, " v v v"), "the job's row shows the directions sent");
    CHECK(has_dtext(OV_THEME_ACCENT, "> > ^"), "the chosen row is still highlighted whole");
    CHECK(has_dtext(OV_THEME_ACCENT, NAME1) && has_dtext(OV_THEME_TEXT, NAME0), "and the names keep their colours");
}

static void test_progress_of_a_dimmed_row(void)
{
    sample(&g_snap);
    g_snap.list.entry_state = ENTRY_RUNNING;
    g_snap.list.entry_kind = 4; /* row 2, which went on cooldown */
    g_snap.list.entry_len = 5;
    g_snap.list.entry_sent = 1;
    draw(&g_snap);
    CHECK(has_dtext(OV_THEME_ACCENT, ">") && has_dtext(OV_THEME_TEXT_OFF, " v < ^ ^"),
          "a dimmed row under way: sent in the accent, the rest in its own dimmed colour");
}

static void test_progress_only_while_running(void)
{
    EntryState states[3] = { ENTRY_IDLE, ENTRY_DONE, ENTRY_FAILED };
    for (int i = 0; i < 3; i++) {
        sample(&g_snap);
        g_snap.list.entry_state = states[i];
        g_snap.list.entry_kind = 118;
        g_snap.list.entry_len = 3;
        g_snap.list.entry_sent = 1;
        draw(&g_snap);
        CHECK(has_dtext(OV_THEME_ACCENT, "> > ^") && fake_ov_count_prefix("dtext:") == 12,
              states[i] == ENTRY_IDLE ? "idle: no progress shown" : states[i] == ENTRY_DONE ? "done: no progress shown"
                                                                                           : "failed: no progress shown");
    }
}

static void test_progress_kind_not_listed(void)
{
    sample(&g_snap);
    g_snap.list.entry_state = ENTRY_RUNNING;
    g_snap.list.entry_kind = 99;
    g_snap.list.entry_len = 4;
    g_snap.list.entry_sent = 2;
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("dtext:") == 12, "a job whose stratagem is not in the list changes nothing");
}

static void test_scale(void)
{
    float one[5], two[5], text1[5], text2[5];
    OvFrame big = { 3840.0f, 2160.0f, 1.0f / 60.0f, 1.0, 2.0f, 0 };
    sample(&g_snap);
    draw(&g_snap);
    fake_ov_geom(0, one);
    fake_ov_geom(find_text(NAME0), text1);
    draw_in(&big, &g_snap, false);
    fake_ov_geom(0, two);
    fake_ov_geom(find_text(NAME0), text2);
    CHECK(two[4] == 12.0f, "at scale 2 the corners are 12 px");
    CHECK(text1[2] == 22.0f && text2[2] == 44.0f, "and the text is twice as high");
    CHECK(two[2] - two[0] > 1.99f * (one[2] - one[0]) && two[2] - two[0] < 2.01f * (one[2] - one[0]), "and the plate twice as wide");
    CHECK(two[2] <= 3840.0f / 3.0f, "still in the left third of the bigger screen");
}

static bool drawn_at_scale_one(void)
{
    float g[5];
    int at = find_text(NAME0);
    return fake_ov_count_prefix("dtext:") == 12 && at >= 0 && fake_ov_geom(at, g) && g[2] == 22.0f;
}

static void test_scale_odd(void)
{
    OvFrame odd = g_frame;
    odd.scale = 0.0f;
    sample(&g_snap);
    draw_in(&odd, &g_snap, false);
    CHECK(drawn_at_scale_one(), "a scale of 0 still draws (as scale 1)");
    odd.scale = -2.0f;
    draw_in(&odd, &g_snap, false);
    CHECK(drawn_at_scale_one(), "so does a negative one");
    odd.scale = NAN;
    draw_in(&odd, &g_snap, false);
    CHECK(drawn_at_scale_one(), "and NaN");
}

static void test_row_limits(void)
{
    static const uint8_t code[2] = { 1, 2 };
    sample(&g_snap);
    for (int i = 0; i < DBF_LIST_ROWS; i++) {
        char name[20];
        snprintf(name, sizeof name, "Row number %02d", i);
        put_row(&g_snap.list.rows[i], 20 + (uint32_t)i, name, code, 2, true);
    }
    g_snap.list.chosen = -1;
    g_snap.list.row_count = 99;
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("dtext:") == DBF_LIST_ROWS * 2, "a row count past the list's room is cut to it");
    CHECK(find_text("Row number 15") >= 0 && find_text("Row number 00") >= 0, "the first and the last row are there");

    sample(&g_snap);
    g_snap.list.row_count = 1;
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("dtext:") == 2 && has_dtext(OV_THEME_TEXT, NAME0), "a single row is drawn alone");
}

static void test_long_code_is_cut(void)
{
    uint8_t code[DBF_CODE_CAPACITY];
    char expected[2 * DBF_CODE_CAPACITY];
    size_t at = 0;
    sample(&g_snap);
    for (int i = 0; i < DBF_CODE_CAPACITY; i++) code[i] = 1;
    put_row(&g_snap.list.rows[0], 3, NAME0, code, DBF_CODE_CAPACITY, true);
    g_snap.list.rows[0].code_len = 250;
    draw(&g_snap);
    for (int i = 0; i < DBF_CODE_CAPACITY; i++) {
        if (i > 0) expected[at++] = ' ';
        expected[at++] = '^';
    }
    expected[at] = '\0';
    CHECK(has_dtext(OV_THEME_TEXT, expected), "a code length past the array is cut to it, not read past");
}

static void test_unterminated_name(void)
{
    int at;
    sample(&g_snap);
    memset(g_snap.list.rows[0].name, 'N', sizeof g_snap.list.rows[0].name); /* no terminator... */
    memset(g_snap.list.rows[0].code, 'M', sizeof g_snap.list.rows[0].code); /* ...and more text behind the field */
    draw(&g_snap);
    at = find_text("NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN");
    CHECK(at >= 0 && strlen(fake_ov_line(at) + 15) == DBF_LIST_NAME_SIZE,
          "a name without a terminator is read no further than its field");
}

static void test_missing_api_functions(void)
{
    OvApi api = *fake_ov_api();
    sample(&g_snap);
    fake_ov_reset();
    api.draw_text = NULL;
    ui_list_draw(&api, &g_frame, &g_snap);
    CHECK(drew_nothing(), "an API without draw_text: nothing is drawn");
    api = *fake_ov_api();
    api.theme = NULL;
    ui_list_draw(&api, &g_frame, &g_snap);
    CHECK(drew_nothing(), "without theme");
    api = *fake_ov_api();
    api.text_size = NULL;
    ui_list_draw(&api, &g_frame, &g_snap);
    CHECK(drew_nothing(), "without text_size");
    api = *fake_ov_api();
    api.draw_rect_filled = NULL;
    ui_list_draw(&api, &g_frame, &g_snap);
    CHECK(drew_nothing(), "without draw_rect_filled");
}

int main(void)
{
    test_draws_nothing();
    test_widget_calls_absent();
    test_plate();
    test_plate_is_centred();
    test_everything_inside_the_plate();
    test_rows_in_order();
    test_columns_line_up();
    test_colours();
    test_old_host_dimming();
    test_only_theme_colours();
    test_codes_and_timers_text();
    test_timer_text_edges();
    test_chosen_bar();
    test_chosen_wins_over_dim();
    test_nothing_chosen();
    test_progress();
    test_progress_on_another_row();
    test_progress_of_a_dimmed_row();
    test_progress_only_while_running();
    test_progress_kind_not_listed();
    test_scale();
    test_scale_odd();
    test_row_limits();
    test_long_code_is_cut();
    test_unterminated_name();
    test_missing_api_functions();
    printf("%s\n", test_failures() == 0 ? "PASS test_ui_list" : "FAIL test_ui_list");
    TEST_MAIN_END
}
