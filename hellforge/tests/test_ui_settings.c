/* Tests for src/ui_settings.c, the settings window's Status tab, against the fake OvApi of tests/fake_ov.c: the test
 * builds a DbfSnapshot by hand, draws it, and reads what the UI asked the host to draw. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "admission.h"
#include "fake_ov.h"
#include "game.h"
#include "snapshot.h"
#include "test.h"
#include "ui_settings.h"

static DbfSnapshot g_snap;

static void set_reason(char* field, size_t size, const char* text)
{
    snap_copy_text(field, size, text);
}

static void set_row(DbfRow* r, uint32_t kind, const uint8_t* code, int n)
{
    memset(r, 0, sizeof *r);
    r->kind = kind;
    r->active = true;
    r->code_len = (uint8_t)n;
    if (n > 0) memcpy(r->code, code, (size_t)n);
}

/* A mission: the menu open, four cards. Orbital Precision Strike (118) has a five-direction code, 4 has none, 150 is a
 * kind from a HellForge mod, 3 has a code of three. Admission: STATE and STRATAGEMS ok, HUD_READ pending, the rest off. */
static void sample(DbfSnapshot* s)
{
    static const uint8_t ops[5] = { 2, 2, 1, 3, 3 };
    static const uint8_t three[3] = { 1, 4, 3 };
    memset(s, 0, sizeof *s);
    s->tick = 42;
    s->host_version = 4;
    s->build_ok = true;
    for (int f = 0; f < FEAT_COUNT; f++) {
        s->admit[f] = ADMIT_REFUSED;
        set_reason(s->admit_reason[f], sizeof s->admit_reason[f], "not mapped yet");
    }
    s->admit[FEAT_STATE] = ADMIT_OK;
    s->admit_reason[FEAT_STATE][0] = '\0';
    s->admit[FEAT_STRATAGEMS] = ADMIT_OK;
    s->admit_reason[FEAT_STRATAGEMS][0] = '\0';
    s->admit[FEAT_HUD_READ] = ADMIT_PENDING;
    set_reason(s->admit_reason[FEAT_HUD_READ], sizeof s->admit_reason[FEAT_HUD_READ], "witness charlie not readable yet");
    s->game.build_ok = true;
    s->game.in_gameplay = true;
    s->game.hud_ready = true;
    s->game.menu_open = true;
    s->game.local_ok = true;
    s->game.scramble_known = false;
    s->game.row_count = 4;
    set_row(&s->game.rows[0], 118, ops, 5);
    set_row(&s->game.rows[1], 4, NULL, 0);
    set_row(&s->game.rows[2], 150, NULL, 0);
    set_row(&s->game.rows[3], 3, three, 3);
}


/* The list view the game thread fills (snap_fill_list): bindings at their defaults, no problems in settings.ini, no job. */
static void fill_list_view(DbfSnapshot* s)
{
    ListView* l = &s->list;
    l->valid = true;
    l->enabled = true;
    l->chosen = -1;
    l->entry_state = ENTRY_IDLE;
    snap_copy_text(l->bind_next, sizeof l->bind_next, "wheel_down");
    snap_copy_text(l->bind_previous, sizeof l->bind_previous, "wheel_up");
    snap_copy_text(l->bind_confirm, sizeof l->bind_confirm, "mouse1");
    snap_copy_text(l->settings_file, sizeof l->settings_file, "settings.ini");
}

static void draw(const DbfSnapshot* s)
{
    fake_ov_reset();
    ui_settings_draw(fake_ov_api(), s);
}

static bool has(const char* line)
{
    if (fake_ov_find(line, 0) >= 0) return true;
    printf("  missing log line \"%s\"\n", line);
    return false;
}

static bool has_not(const char* line)
{
    if (fake_ov_find(line, 0) < 0) return true;
    printf("  unexpected log line \"%s\"\n", line);
    return false;
}

/* The row of stratagem `name`: its name text, then a column, then its code text. */
static bool row_is(const char* name, const char* code)
{
    char a[160], b[160];
    int at;
    snprintf(a, sizeof a, "text:%s", name);
    snprintf(b, sizeof b, "text:%s", code);
    at = fake_ov_find(a, 0);
    if (at < 0) {
        printf("  no row named \"%s\"\n", name);
        return false;
    }
    if (at < 2 || strcmp(fake_ov_line(at - 1), "cell") != 0 || strcmp(fake_ov_line(at - 2), "row") != 0) {
        printf("  \"%s\" does not start a table row\n", name);
        return false;
    }
    if (!fake_ov_line(at + 1) || strcmp(fake_ov_line(at + 1), "cell") != 0 || !fake_ov_line(at + 2)
        || strcmp(fake_ov_line(at + 2), b) != 0) {
        printf("  the row \"%s\" does not continue with a cell showing \"%s\"\n", name, code);
        return false;
    }
    return true;
}

static bool balanced(void)
{
    if (fake_ov_open() == 0 && fake_ov_misuse() == 0 && !fake_ov_overflowed()) return true;
    printf("  open %d, misuse %d, overflowed %d\n", fake_ov_open(), fake_ov_misuse(), fake_ov_overflowed());
    return false;
}

/* --- tests ----------------------------------------------------------------------------------------------------- */

static void test_kind_names(void)
{
    CHECK(strcmp(dbf_kind_name(118), "Orbital Precision Strike") == 0, "kind 118 is Orbital Precision Strike");
    CHECK(strcmp(dbf_kind_name(3), "Eagle 500kg Bomb") == 0, "kind 3 is Eagle 500kg Bomb");
    CHECK(strcmp(dbf_kind_name(0), "Stratagem 0") == 0, "kind 0 has no name");
    CHECK(strcmp(dbf_kind_name(150), "Stratagem 150") == 0, "kind 150 is a HellForge kind: Stratagem 150");
    CHECK(strcmp(dbf_kind_name(4294967295u), "Stratagem 4294967295") == 0, "the largest kind is spelt out");
    {
        bool all = true;
        for (uint32_t k = 0; k < 150; k++)
            if (dbf_kind_name(k) == NULL || dbf_kind_name(k)[0] == '\0') all = false;
        CHECK(all, "every vanilla kind has a non-empty name");
    }
}

static void test_status_in_mission(void)
{
    sample(&g_snap);
    draw(&g_snap);
    CHECK(has("tabbar:dbf-tabs"), "a tab bar named dbf-tabs");
    CHECK(has("tab:Status"), "a tab named Status");
    CHECK(has("text:Game build 25480438: OK"), "the build line");
    CHECK(has("text:Selection state: OK"), "an admitted feature: OK");
    CHECK(has("text:Stratagems: OK"), "another");
    CHECK(has("text:HUD reads: Waiting (witness charlie not readable yet)"), "a pending feature: Waiting, with its reason");
    CHECK(has("text:Weapon strip: Off (not mapped yet)"), "a refused feature: Off, with its reason");
    CHECK(has("text:Overlay Host API 4"), "the host's API version");
    CHECK(has("text:In a mission: yes"), "in a mission");
    CHECK(has("text:Stratagem menu: open"), "the menu is open");
    CHECK(has("text:Codes do not follow scrambling yet"), "in a mission with scramble unknown: the scramble note");
    CHECK(has("table:dbf-stratagems"), "a table of stratagems");
    CHECK(has("col:Stratagem") && has("col:Code"), "with two columns");
    CHECK(row_is("Orbital Precision Strike", "> > ^ v v"), "a row: the name and its code as arrows");
    CHECK(row_is("Eagle 500kg Bomb", "^ < v"), "another row, with all four arrows in use");
    CHECK(row_is("Stratagem 150", "no code"), "a HellForge kind: its number, no code");
    CHECK(row_is("Orbital Gatling Barrage", "no code"), "a vanilla kind with no code");
    CHECK(fake_ov_count_prefix("row") == 4, "four rows");
    CHECK(balanced(), "every begin has its end");
}

static void test_status_order(void)
{
    int bar, tab, build, state, hud, host, mission, menu, scramble, table;
    sample(&g_snap);
    draw(&g_snap);
    bar = fake_ov_find("tabbar:dbf-tabs", 0);
    tab = fake_ov_find("tab:Status", 0);
    build = fake_ov_find("text:Game build 25480438: OK", 0);
    state = fake_ov_find("text:Selection state: OK", 0);
    hud = fake_ov_find("text:HUD reads: Waiting (witness charlie not readable yet)", 0);
    host = fake_ov_find("text:Overlay Host API 4", 0);
    mission = fake_ov_find("text:In a mission: yes", 0);
    menu = fake_ov_find("text:Stratagem menu: open", 0);
    scramble = fake_ov_find("text:Codes do not follow scrambling yet", 0);
    table = fake_ov_find("table:dbf-stratagems", 0);
    CHECK(bar == 0 && tab == bar + 1, "the tab bar opens the window and the tab follows");
    CHECK(tab < build && build < state && state < hud, "the build line, then the features in order");
    CHECK(hud < host && host < mission && mission < menu && menu < scramble && scramble < table,
        "then the host, the mission, the menu, the scramble note and the table");
    CHECK(strcmp(fake_ov_line(fake_ov_lines() - 1), "end:tabbar") == 0
            && strcmp(fake_ov_line(fake_ov_lines() - 2), "end:tab") == 0,
        "the tab closes, then the bar");
}

static void test_every_feature_line(void)
{
    int names = 0;
    sample(&g_snap);
    draw(&g_snap);
    for (int f = 0; f < FEAT_COUNT; f++) {
        char prefix[96];
        snprintf(prefix, sizeof prefix, "text:%s: ", adm_feature_name((Feature)f));
        if (fake_ov_count_prefix(prefix) == 1) names++;
        else printf("  feature line for \"%s\" appears %d times\n", prefix, fake_ov_count_prefix(prefix));
    }
    CHECK(names == FEAT_COUNT, "one line per feature, by its admission name");
}

static void test_scramble_known(void)
{
    sample(&g_snap);
    g_snap.game.scramble_known = true;
    draw(&g_snap);
    CHECK(has_not("text:Codes do not follow scrambling yet"), "scramble known: no note");
    CHECK(has("text:In a mission: yes"), "still in a mission");
}

static void test_menu_closed(void)
{
    sample(&g_snap);
    g_snap.game.menu_open = false;
    draw(&g_snap);
    CHECK(has("text:Stratagem menu: closed"), "menu closed");
    CHECK(has_not("text:Stratagem menu: open"), "and not open");
    CHECK(has("table:dbf-stratagems"), "rows are listed with the menu closed too");
}

static void test_not_in_mission(void)
{
    sample(&g_snap);
    g_snap.game.in_gameplay = false;
    g_snap.game.hud_ready = false;
    g_snap.game.menu_open = false;
    set_reason(g_snap.game.reason, sizeof g_snap.game.reason, "not in gameplay");
    draw(&g_snap);
    CHECK(has("text:In a mission: no (not in gameplay)"), "not in gameplay: no, with the reason");
    CHECK(has_not("text:In a mission: yes"), "and not yes");
    CHECK(has("text:Stratagem menu: closed"), "the menu is closed");
    CHECK(fake_ov_count_prefix("table:") == 0 && fake_ov_count_prefix("row") == 0, "no table and no rows");
    CHECK(has_not("text:Orbital Precision Strike") && has_not("text:no code"), "no stratagem lines");
    CHECK(has_not("text:Codes do not follow scrambling yet"), "no scramble note outside a mission");
    CHECK(has("text:Game build 25480438: OK") && has("text:Overlay Host API 4"), "the rest of the tab is still drawn");
    CHECK(balanced(), "every begin has its end");
}

static void test_not_in_mission_without_reason(void)
{
    sample(&g_snap);
    g_snap.game.in_gameplay = false;
    g_snap.game.reason[0] = '\0';
    draw(&g_snap);
    CHECK(has("text:In a mission: no"), "no reason: just no");
}

static void test_reader_reason(void)
{
    int menu, reader, scramble;
    sample(&g_snap);
    set_reason(g_snap.game.reason, sizeof g_snap.game.reason, "local ownership mapping unavailable");
    draw(&g_snap);
    CHECK(has("text:In a mission: yes"), "in a mission with a reader reason");
    CHECK(has("text:Reader: local ownership mapping unavailable"), "in a mission: the reader's reason is shown");
    CHECK(fake_ov_count_prefix("text:Reader: ") == 1, "once");
    menu = fake_ov_find("text:Stratagem menu: open", 0);
    reader = fake_ov_find("text:Reader: local ownership mapping unavailable", 0);
    scramble = fake_ov_find("text:Codes do not follow scrambling yet", 0);
    CHECK(menu >= 0 && menu < reader && reader < scramble, "after the menu line and before the scramble line");
    CHECK(fake_ov_find("table:dbf-stratagems", 0) > scramble, "and the rows still follow");
    CHECK(balanced(), "balanced");

    sample(&g_snap);
    g_snap.game.scramble_known = true;
    set_reason(g_snap.game.reason, sizeof g_snap.game.reason, "local ownership mapping unavailable");
    draw(&g_snap);
    menu = fake_ov_find("text:Stratagem menu: open", 0);
    reader = fake_ov_find("text:Reader: local ownership mapping unavailable", 0);
    CHECK(menu >= 0 && menu < reader && has_not("text:Codes do not follow scrambling yet"),
        "with scramble known the reason still follows the menu line");

    sample(&g_snap);
    g_snap.game.reason[0] = '\0';
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("text:Reader:") == 0, "in a mission with an empty reason: no Reader line");

    sample(&g_snap);
    g_snap.game.in_gameplay = false;
    set_reason(g_snap.game.reason, sizeof g_snap.game.reason, "not in gameplay");
    draw(&g_snap);
    CHECK(has("text:In a mission: no (not in gameplay)"), "not in a mission: the reason is in the mission line");
    CHECK(fake_ov_count_prefix("text:Reader:") == 0, "and not repeated as a Reader line");

    sample(&g_snap);
    g_snap.game.hud_ready = false;
    set_reason(g_snap.game.reason, sizeof g_snap.game.reason, "HUD not ready");
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("text:Reader:") == 0, "HUD not ready is not a mission either: no Reader line");

    sample(&g_snap);
    memset(g_snap.game.reason, 's', sizeof g_snap.game.reason - 1);
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("text:Reader: ssss") == 1 && balanced(), "the longest reason fits the line");
}

static void test_hud_not_ready(void)
{
    sample(&g_snap);
    g_snap.game.hud_ready = false;
    set_reason(g_snap.game.reason, sizeof g_snap.game.reason, "HUD not ready");
    draw(&g_snap);
    CHECK(has("text:In a mission: no (HUD not ready)"), "in gameplay but the HUD is not up: not in a mission yet");
    CHECK(fake_ov_count_prefix("table:") == 0 && has_not("text:Codes do not follow scrambling yet"), "no rows, no note");
}

static void test_build_refused(void)
{
    sample(&g_snap);
    g_snap.build_ok = false;
    set_reason(g_snap.build_reason, sizeof g_snap.build_reason, "build 6ae0e5ff is not 25480438");
    draw(&g_snap);
    CHECK(has("text:Game build: build 6ae0e5ff is not 25480438"), "the build reason replaces the OK line");
    CHECK(has_not("text:Game build 25480438: OK"), "and no OK line");
    sample(&g_snap);
    g_snap.build_ok = false;
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("text:Game build: ") == 1, "a refused build without a reason still gets a line");
}

static void test_waiting_and_off_without_reason(void)
{
    sample(&g_snap);
    g_snap.admit_reason[FEAT_HUD_READ][0] = '\0';
    g_snap.admit_reason[FEAT_WEAPON][0] = '\0';
    draw(&g_snap);
    CHECK(has("text:HUD reads: Waiting"), "Waiting with no reason has no brackets");
    CHECK(has("text:Weapon strip: Off"), "nor does Off");
}

static void test_arrows(void)
{
    static const uint8_t all[8] = { 1, 2, 3, 4, 4, 3, 2, 1 };
    static const uint8_t bad[4] = { 1, 0, 5, 255 };
    uint8_t twelve[12];
    sample(&g_snap);
    set_row(&g_snap.game.rows[0], 118, all, 8);
    set_row(&g_snap.game.rows[1], 3, bad, 4);
    for (int i = 0; i < 12; i++) twelve[i] = (uint8_t)(i % 4 + 1);
    set_row(&g_snap.game.rows[2], 4, twelve, 12);
    g_snap.game.row_count = 3;
    draw(&g_snap);
    CHECK(has("text:^ > v < < v > ^"), "1 up, 2 right, 3 down, 4 left, separated by spaces");
    CHECK(has("text:^ ? ? ?"), "a direction outside 1 to 4 shows as ?");
    CHECK(has("text:^ > v < ^ > v < ^ > v <"), "a twelve-direction code");
}

static void test_row_limits(void)
{
    sample(&g_snap);
    g_snap.game.row_count = 99;
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("row") == DBF_VAL_CARD_COUNT, "a row count past the card count is cut to it");
    CHECK(balanced(), "and the table is closed");
    sample(&g_snap);
    g_snap.game.row_count = -3;
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("row") == 0, "a negative row count draws no rows");
    CHECK(balanced(), "and stays balanced");
    sample(&g_snap);
    g_snap.game.row_count = 0;
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("table:") == 0 && has("text:In a mission: yes"), "a mission with no rows: no table");
    sample(&g_snap);
    g_snap.game.rows[0].code_len = 40; /* longer than the row's array */
    draw(&g_snap);
    CHECK(balanced() && has("text:Game build 25480438: OK"), "a code length past the array is cut, not read past");
}

static void test_long_reason(void)
{
    char want[200];
    sample(&g_snap);
    memset(g_snap.admit_reason[FEAT_CAMERA], 'r', sizeof g_snap.admit_reason[FEAT_CAMERA] - 1);
    memset(g_snap.game.reason, 's', sizeof g_snap.game.reason - 1);
    g_snap.game.in_gameplay = false;
    draw(&g_snap);
    snprintf(want, sizeof want, "text:Camera hold: Off (%.79s)", g_snap.admit_reason[FEAT_CAMERA]);
    CHECK(has(want), "the longest feature reason is shown whole");
    CHECK(fake_ov_count_prefix("text:In a mission: no (ssss") == 1, "so is the longest mission reason");
    CHECK(balanced(), "and nothing overflows");
}

static void test_no_snapshot(void)
{
    draw(NULL);
    CHECK(has("tabbar:dbf-tabs") && has("tab:Status"), "before the first snapshot the tab is still there");
    CHECK(fake_ov_count_prefix("text:") == 1, "with one line saying so");
    CHECK(balanced(), "balanced");
}

static void test_hidden_tab(void)
{
    sample(&g_snap);
    fake_ov_reset();
    fake_ov_set_results(1, 0, 1);
    ui_settings_draw(fake_ov_api(), &g_snap);
    CHECK(has("tab:Status") && fake_ov_count_prefix("text:") == 0, "tab not shown: nothing drawn in it");
    CHECK(fake_ov_find("end:tab", 0) < 0 && fake_ov_find("end:tabbar", 0) >= 0, "end_tab_item is not called for a hidden tab");
    CHECK(balanced(), "balanced");

    fake_ov_reset();
    fake_ov_set_results(0, 1, 1);
    ui_settings_draw(fake_ov_api(), &g_snap);
    CHECK(has("tabbar:dbf-tabs") && fake_ov_lines() == 1, "tab bar not shown: nothing else is called, not even end_tab_bar");
    CHECK(balanced(), "balanced");

    fake_ov_reset();
    fake_ov_set_results(1, 1, 0);
    ui_settings_draw(fake_ov_api(), &g_snap);
    CHECK(has("table:dbf-stratagems") && fake_ov_find("end:table", 0) < 0, "table not shown: end_table is not called");
    CHECK(fake_ov_count_prefix("row") == 0, "and no rows are submitted");
    CHECK(balanced(), "balanced");
}


static void test_entry_lines(void)
{
    int scramble, separator, bindings, settings, entry, table;
    sample(&g_snap);
    fill_list_view(&g_snap);
    draw(&g_snap);
    CHECK(has("text:Bindings: wheel_down / wheel_up / mouse1"), "the bindings line: next, previous, confirm");
    CHECK(has("text:Settings: settings.ini (0 problems)"), "the settings line names the file, not a path");
    CHECK(has("text:Entry: idle"), "the entry line: idle");
    CHECK(fake_ov_count_prefix("text:Bindings: ") == 1 && fake_ov_count_prefix("text:Settings: ") == 1 &&
              fake_ov_count_prefix("text:Entry: ") == 1,
          "one of each");
    scramble = fake_ov_find("text:Codes do not follow scrambling yet", 0);
    bindings = fake_ov_find("text:Bindings: wheel_down / wheel_up / mouse1", 0);
    settings = fake_ov_find("text:Settings: settings.ini (0 problems)", 0);
    entry = fake_ov_find("text:Entry: idle", 0);
    table = fake_ov_find("table:dbf-stratagems", 0);
    separator = fake_ov_find("separator", scramble);
    CHECK(scramble < separator && separator < bindings && bindings < settings && settings < entry && entry < table,
          "after the scramble note, behind a rule: bindings, settings, entry, then the table");
    CHECK(balanced(), "balanced");
}

static void test_entry_lines_need_a_filled_list(void)
{
    sample(&g_snap);
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("text:Bindings: ") == 0 && fake_ov_count_prefix("text:Settings: ") == 0 &&
              fake_ov_count_prefix("text:Entry: ") == 0,
          "a snapshot whose list was never filled shows none of the three lines");
    CHECK(fake_ov_find("separator", 0) >= 0 && fake_ov_count_prefix("separator") == 2,
          "and no extra rule (the features' and the table's)");
}

static void test_entry_lines_outside_a_mission(void)
{
    sample(&g_snap);
    fill_list_view(&g_snap);
    g_snap.game.in_gameplay = false;
    g_snap.game.hud_ready = false;
    g_snap.game.menu_open = false;
    draw(&g_snap);
    CHECK(has("text:Bindings: wheel_down / wheel_up / mouse1") && has("text:Settings: settings.ini (0 problems)") &&
              has("text:Entry: idle"),
          "they are drawn outside a mission too: the keys and the file matter there");
    CHECK(balanced(), "balanced");
}

static void test_bindings_status(void)
{
    int line, status;
    sample(&g_snap);
    fill_list_view(&g_snap);
    snap_copy_text(g_snap.list.bind_status, sizeof g_snap.list.bind_status, "wheel bindings need Overlay Host 0.5.0");
    draw(&g_snap);
    line = fake_ov_find("text:Bindings: wheel_down / wheel_up / mouse1", 0);
    status = fake_ov_find("text:wheel bindings need Overlay Host 0.5.0", 0);
    CHECK(status == line + 1, "the bindings status is the line right under the bindings");

    sample(&g_snap);
    fill_list_view(&g_snap);
    draw(&g_snap);
    line = fake_ov_find("text:Bindings: wheel_down / wheel_up / mouse1", 0);
    CHECK(strncmp(fake_ov_line(line + 1), "text:Settings: ", 15) == 0, "with no status the settings line follows at once");
}

static void test_unbound_reads_none(void)
{
    sample(&g_snap);
    fill_list_view(&g_snap);
    g_snap.list.bind_next[0] = '\0';
    g_snap.list.bind_confirm[0] = '\0';
    draw(&g_snap);
    CHECK(has("text:Bindings: none / wheel_up / none"), "a binding with no name reads none");
}

static void test_settings_problem_count(void)
{
    sample(&g_snap);
    fill_list_view(&g_snap);
    g_snap.list.settings_problems = 1;
    draw(&g_snap);
    CHECK(has("text:Settings: settings.ini (1 problem)"), "one problem is singular");
    g_snap.list.settings_problems = 3;
    draw(&g_snap);
    CHECK(has("text:Settings: settings.ini (3 problems)"), "three are plural");
    g_snap.list.settings_problems = 2000000000;
    draw(&g_snap);
    CHECK(has("text:Settings: settings.ini (2000000000 problems)"), "a large count is written whole");
    g_snap.list.settings_problems = -4;
    draw(&g_snap);
    CHECK(has("text:Settings: settings.ini (0 problems)"), "a negative count reads 0");
    g_snap.list.settings_problems = 0;
    g_snap.list.settings_file[0] = '\0';
    draw(&g_snap);
    CHECK(has("text:Settings: defaults (0 problems)"), "no file name (no settings file was read): the defaults are in use");
}

static void test_entry_states(void)
{
    sample(&g_snap);
    fill_list_view(&g_snap);
    g_snap.list.entry_state = ENTRY_RUNNING;
    g_snap.list.entry_kind = 118;
    snap_copy_text(g_snap.list.entry_name, sizeof g_snap.list.entry_name, "Orbital Precision Strike");
    g_snap.list.entry_sent = 2;
    g_snap.list.entry_len = 5;
    draw(&g_snap);
    CHECK(has("text:Entry: entering Orbital Precision Strike (2/5)"), "running: entering <name> (<sent>/<len>)");

    g_snap.list.entry_sent = 0;
    draw(&g_snap);
    CHECK(has("text:Entry: entering Orbital Precision Strike (0/5)"), "nothing sent yet");

    g_snap.list.entry_state = ENTRY_DONE;
    draw(&g_snap);
    CHECK(has("text:Entry: done"), "done");

    g_snap.list.entry_state = ENTRY_FAILED;
    snap_copy_text(g_snap.list.entry_reason, sizeof g_snap.list.entry_reason, "menu closed");
    draw(&g_snap);
    CHECK(has("text:Entry: failed: menu closed"), "failed: <reason>");

    g_snap.list.entry_reason[0] = '\0';
    draw(&g_snap);
    CHECK(has("text:Entry: failed"), "failed with no reason: just failed");

    memset(g_snap.list.entry_reason, 'r', sizeof g_snap.list.entry_reason - 1);
    g_snap.list.entry_reason[sizeof g_snap.list.entry_reason - 1] = '\0';
    draw(&g_snap);
    CHECK(fake_ov_count_prefix("text:Entry: failed: rrrr") == 1 && fake_ov_overflowed() == 0, "the longest reason is shown whole");
    CHECK(balanced(), "balanced");
}

static void test_entry_name_from_the_list(void)
{
    sample(&g_snap);
    fill_list_view(&g_snap);
    g_snap.list.entry_state = ENTRY_RUNNING;
    g_snap.list.entry_kind = 150;
    snap_copy_text(g_snap.list.entry_name, sizeof g_snap.list.entry_name, "Stratagem 150");
    g_snap.list.entry_len = 4;
    draw(&g_snap);
    CHECK(has("text:Entry: entering Stratagem 150 (0/4)"), "a HellForge kind is entered by its number");
}

static void test_null_api(void)
{
    sample(&g_snap);
    ui_settings_draw(NULL, &g_snap);
    CHECK(true, "no API: nothing happens");
}

int main(void)
{
    test_kind_names();
    test_status_in_mission();
    test_status_order();
    test_every_feature_line();
    test_scramble_known();
    test_menu_closed();
    test_not_in_mission();
    test_not_in_mission_without_reason();
    test_reader_reason();
    test_hud_not_ready();
    test_build_refused();
    test_waiting_and_off_without_reason();
    test_arrows();
    test_row_limits();
    test_long_reason();
    test_entry_lines();
    test_entry_lines_need_a_filled_list();
    test_entry_lines_outside_a_mission();
    test_bindings_status();
    test_unbound_reads_none();
    test_settings_problem_count();
    test_entry_states();
    test_entry_name_from_the_list();
    test_no_snapshot();
    test_hidden_tab();
    test_null_api();
    printf("%s\n", test_failures() == 0 ? "PASS test_ui_settings" : "FAIL test_ui_settings");
    TEST_MAIN_END
}
