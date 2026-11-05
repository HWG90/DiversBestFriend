/* flags: -DDBF_TEST_WITNESSES */
/* Tests for src/settings.c: the defaults, every key of [dbf], [bindings] and [blacklist], the file format (comments,
 * whitespace, case, line endings, a byte order mark, the length of the text), and the problems: what is listed, that the
 * rest of the file is still read, and that the problem text is built whole or not at all. settings.c reads the blacklist
 * table through the generated header's extern declaration; -DDBF_TEST_WITNESSES gives admission.c the small test table of
 * tests/test_witnesses.h instead of the generated one: kinds 5 (hidden by default), 42, 148 and 199 (the largest settings
 * keep). test_settings_table.c covers the same rules over the generated table. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "addresses_25480438.h"
#include "settings.h"
#include "test.h"

static DbfSettings g_s;
static char g_p[1024];

static int parse(const char* text)
{
    return settings_parse(&g_s, text, strlen(text), g_p, sizeof g_p);
}

static bool same_binding(Binding a, Binding b) { return a.kind == b.kind && a.code == b.code; }

static bool equal(const DbfSettings* a, const DbfSettings* b)
{
    if (a->enabled != b->enabled || a->selection_sounds != b->selection_sounds ||
        a->randomize_input_delay != b->randomize_input_delay || a->instant_stratagems != b->instant_stratagems ||
        a->hide_sos != b->hide_sos || a->hide_eagle_rearm != b->hide_eagle_rearm ||
        a->input_interval_ms != b->input_interval_ms)
        return false;
    for (int k = 0; k < DBF_BLACKLIST_SLOTS; k++)
        if (a->blacklist_kind[k] != b->blacklist_kind[k]) return false;
    for (int i = 0; i < BIND_COUNT; i++)
        if (!same_binding(a->bind[i], b->bind[i])) return false;
    return true;
}

static DbfSettings defaults(void)
{
    DbfSettings d;
    settings_defaults(&d);
    return d;
}

static bool is_default(void)
{
    DbfSettings d = defaults();
    return equal(&g_s, &d);
}

static int lines_in(const char* text)
{
    int n = text[0] != '\0';
    for (const char* c = text; *c; c++)
        if (*c == '\n') n++;
    return n;
}

/* --- defaults -------------------------------------------------------------------------------------------------- */

static void test_defaults(void)
{
    DbfSettings s;
    memset(&s, 0xAB, sizeof s);
    settings_defaults(&s);
    CHECK(s.enabled == true && s.selection_sounds == true, "defaults: enabled and selection_sounds are on");
    CHECK(s.randomize_input_delay == false && s.instant_stratagems == false, "defaults: randomize_input_delay and instant_stratagems are off");
    CHECK(s.hide_sos == false && s.hide_eagle_rearm == false, "defaults: hide_sos and hide_eagle_rearm are off");
    CHECK(s.input_interval_ms == 70, "defaults: input_interval_ms is 70");
    CHECK(s.blacklist_kind[5] == true, "defaults: kind 5 is hidden (the table says default_on)");
    CHECK(s.blacklist_kind[42] == false && s.blacklist_kind[148] == false && s.blacklist_kind[199] == false,
          "defaults: kinds 42, 148 and 199 are shown");
    bool others_off = true;
    for (int k = 0; k < DBF_BLACKLIST_SLOTS; k++)
        if (k != 5 && s.blacklist_kind[k]) others_off = false;
    CHECK(others_off, "defaults: every kind the table does not name is shown");
    CHECK(same_binding(s.bind[BIND_NEXT], (Binding){ BIND_WHEEL_DOWN, 0 }), "defaults: next is wheel_down");
    CHECK(same_binding(s.bind[BIND_PREVIOUS], (Binding){ BIND_WHEEL_UP, 0 }), "defaults: previous is wheel_up");
    CHECK(same_binding(s.bind[BIND_CONFIRM], (Binding){ BIND_MOUSE, 1 }), "defaults: confirm is mouse1");
    bool slots_none = true;
    for (int i = BIND_SLOT1; i <= BIND_SLOT4; i++) slots_none &= s.bind[i].kind == BIND_NONE && s.bind[i].code == 0;
    CHECK(slots_none, "defaults: the four slot hotkeys are unbound");
    CHECK(BIND_COUNT == 7 && DBF_BLACKLIST_SLOTS == 200, "seven actions, 200 kinds");
}

static void test_parse_nothing(void)
{
    char problems[8] = "xxxxxxx";
    memset(&g_s, 0xAB, sizeof g_s);
    CHECK(settings_parse(&g_s, "", 0, g_p, sizeof g_p) == 0 && is_default() && g_p[0] == '\0', "empty text: the defaults, no problems");
    memset(&g_s, 0xAB, sizeof g_s);
    CHECK(settings_parse(&g_s, NULL, 0, problems, sizeof problems) == 0 && is_default() && problems[0] == '\0',
          "NULL text of length 0: the defaults, no problems");
    CHECK(parse("\n\n   \n\t\n; only a comment\n# and another\n") == 0 && is_default() && g_p[0] == '\0',
          "blank lines and comments only: the defaults");
    g_s.enabled = false;
    CHECK(parse("[dbf]\n[bindings]\n[blacklist]\n") == 0 && is_default(), "empty sections change nothing, and parse starts from the defaults");
    CHECK(settings_parse(&g_s, "[dbf]\nenabled = false\n", strlen("[dbf]\nenabled = false\n"), NULL, 0) == 0 && !g_s.enabled, "NULL problems with size 0 is allowed");
}

/* --- [dbf] ----------------------------------------------------------------------------------------------------- */

typedef struct { const char* key; size_t offset; bool def; } BoolKey;
static const BoolKey g_bool_keys[] = {
    { "enabled", offsetof(DbfSettings, enabled), true },
    { "selection_sounds", offsetof(DbfSettings, selection_sounds), true },
    { "randomize_input_delay", offsetof(DbfSettings, randomize_input_delay), false },
    { "instant_stratagems", offsetof(DbfSettings, instant_stratagems), false },
    { "hide_sos", offsetof(DbfSettings, hide_sos), false },
    { "hide_eagle_rearm", offsetof(DbfSettings, hide_eagle_rearm), false },
};

static bool* field(DbfSettings* s, const BoolKey* k) { return (bool*)(void*)((char*)s + k->offset); }

static void test_dbf_booleans(void)
{
    for (size_t i = 0; i < sizeof g_bool_keys / sizeof g_bool_keys[0]; i++) {
        const BoolKey* k = &g_bool_keys[i];
        char text[160], name[160];
        DbfSettings want = defaults();
        *field(&want, k) = !k->def;
        snprintf(text, sizeof text, "[dbf]\n%s = %s\n", k->key, k->def ? "false" : "true");
        snprintf(name, sizeof name, "[dbf] %s = %s: only that setting changes, no problems", k->key, k->def ? "false" : "true");
        CHECK(parse(text) == 0 && equal(&g_s, &want), name);
        snprintf(text, sizeof text, "[dbf]\n%s = %s\n", k->key, k->def ? "true" : "false");
        snprintf(name, sizeof name, "[dbf] %s = %s (its default): nothing changes", k->key, k->def ? "true" : "false");
        CHECK(parse(text) == 0 && is_default(), name);
    }
}

static void test_boolean_forms(void)
{
    CHECK(parse("[dbf]\nhide_sos = true\n") == 0 && g_s.hide_sos, "true");
    CHECK(parse("[dbf]\nhide_sos = TRUE\n") == 0 && g_s.hide_sos, "TRUE");
    CHECK(parse("[dbf]\nhide_sos = 1\n") == 0 && g_s.hide_sos, "1");
    CHECK(parse("[dbf]\nenabled = false\n") == 0 && !g_s.enabled, "false");
    CHECK(parse("[dbf]\nenabled = False\n") == 0 && !g_s.enabled, "False");
    CHECK(parse("[dbf]\nenabled = 0\n") == 0 && !g_s.enabled, "0");
    CHECK(parse("[dbf]\nenabled = yes\n") == 1 && g_s.enabled && strstr(g_p, "line 2: ") == g_p, "yes is not a boolean: listed, skipped");
    CHECK(parse("[dbf]\nenabled = 2\n") == 1 && g_s.enabled, "2 is not a boolean");
    CHECK(parse("[dbf]\nenabled = \n") == 1 && g_s.enabled, "an empty value is not a boolean");
    CHECK(parse("[dbf]\nenabled = true false\n") == 1 && g_s.enabled, "two words are not a boolean");
    CHECK(parse("[dbf]\nhide_sos = true\nhide_sos = maybe\n") == 1 && g_s.hide_sos, "a bad value after a good one leaves the good one");
    CHECK(strstr(g_p, "\"maybe\"") != NULL && strstr(g_p, "hide_sos") != NULL, "the problem names the key and shows the value");
}

static void test_interval(void)
{
    CHECK(parse("[dbf]\ninput_interval_ms = 0\n") == 0 && g_s.input_interval_ms == 0, "input_interval_ms 0 (one direction per frame)");
    CHECK(parse("[dbf]\ninput_interval_ms = 1\n") == 0 && g_s.input_interval_ms == 1, "input_interval_ms 1");
    CHECK(parse("[dbf]\ninput_interval_ms = 120\n") == 0 && g_s.input_interval_ms == 120, "input_interval_ms 120");
    CHECK(parse("[dbf]\ninput_interval_ms = 250\n") == 0 && g_s.input_interval_ms == 250, "input_interval_ms 250 (the largest)");
    CHECK(parse("[dbf]\ninput_interval_ms =\t 90 \t\n") == 0 && g_s.input_interval_ms == 90, "spaces and tabs around the number are trimmed");
    CHECK(parse("[dbf]\ninput_interval_ms = 251\n") == 1 && g_s.input_interval_ms == 70, "251: listed, the default 70");
    CHECK(strstr(g_p, "line 2: ") == g_p && strstr(g_p, "input_interval_ms") != NULL, "and the problem names the key and the line");
    CHECK(parse("[dbf]\ninput_interval_ms = -1\n") == 1 && g_s.input_interval_ms == 70, "-1: listed, the default");
    CHECK(parse("[dbf]\ninput_interval_ms = 1000\n") == 1 && g_s.input_interval_ms == 70, "1000: listed, the default");
    CHECK(parse("[dbf]\ninput_interval_ms = fast\n") == 1 && g_s.input_interval_ms == 70, "fast: listed, the default");
    CHECK(parse("[dbf]\ninput_interval_ms = \n") == 1 && g_s.input_interval_ms == 70, "empty: listed, the default");
    CHECK(parse("[dbf]\ninput_interval_ms = 70ms\n") == 1 && g_s.input_interval_ms == 70, "70ms: listed, the default");
    CHECK(parse("[dbf]\ninput_interval_ms = 1.5\n") == 1 && g_s.input_interval_ms == 70, "1.5: listed, the default");
    CHECK(parse("[dbf]\ninput_interval_ms = 0x10\n") == 1 && g_s.input_interval_ms == 70, "0x10: listed, the default");
    CHECK(parse("[dbf]\ninput_interval_ms = +5\n") == 1 && g_s.input_interval_ms == 70, "+5: listed, the default");
    CHECK(parse("[dbf]\ninput_interval_ms = 99999999999999999999999\n") == 1 && g_s.input_interval_ms == 70, "a number too long for an int: listed, the default");
    CHECK(parse("[dbf]\ninput_interval_ms = 100\ninput_interval_ms = 999\n") == 1 && g_s.input_interval_ms == 70,
          "a later out-of-range value gives the default, not the earlier value");
    CHECK(parse("[dbf]\ninput_interval_ms = 999\ninput_interval_ms = 100\n") == 1 && g_s.input_interval_ms == 100,
          "and a later good value wins over an earlier bad one");
}

/* --- the format ------------------------------------------------------------------------------------------------ */

static void test_format(void)
{
    DbfSettings want;
    CHECK(parse("; leading comment\n# another\n[dbf]\n  ; indented comment\n\t# tab comment\nhide_sos = true\n") == 0 && g_s.hide_sos,
          "comments with ; and # (also indented) are skipped");
    CHECK(parse("[dbf]\nhide_sos=true\n") == 0 && g_s.hide_sos, "no spaces around =");
    CHECK(parse("[dbf]\n   hide_sos   =   true   \n") == 0 && g_s.hide_sos, "many spaces around names and values");
    CHECK(parse("[dbf]\n\thide_sos\t=\ttrue\t\n") == 0 && g_s.hide_sos, "tabs around names and values");
    CHECK(parse("  [dbf]  \nhide_sos = true\n") == 0 && g_s.hide_sos, "spaces around a section header");
    CHECK(parse("[ dbf ]\nhide_sos = true\n") == 0 && g_s.hide_sos, "spaces inside a section header");
    CHECK(parse("[dbf]\r\nhide_sos = true\r\ninput_interval_ms = 90\r\n") == 0 && g_s.hide_sos && g_s.input_interval_ms == 90,
          "CR LF line endings");
    CHECK(parse("[dbf]\nhide_sos = true") == 0 && g_s.hide_sos, "no newline after the last line");
    CHECK(parse("\xEF\xBB\xBF[dbf]\nhide_sos = true\n") == 0 && g_s.hide_sos, "a UTF-8 byte order mark at the start is skipped");
    CHECK(parse("[DBF]\nHide_SOS = TRUE\n") == 0 && g_s.hide_sos, "section names, keys and values are not case sensitive");
    CHECK(parse("[dbf]\nhide_sos = true\nhide_sos = false\n") == 0 && !g_s.hide_sos, "a later line for the same key wins");
    CHECK(parse("[dbf]\nhide_sos = true\n[bindings]\nnext = none\n[dbf]\nhide_eagle_rearm = true\n") == 0 && g_s.hide_sos &&
              g_s.hide_eagle_rearm && g_s.bind[BIND_NEXT].kind == BIND_NONE,
          "a section may be opened again");
    CHECK(parse("[dbf]\nhide_sos = true ; not a comment\n") == 1 && !g_s.hide_sos, "comments are whole lines: text after a value is part of it");
    CHECK(parse("[dbf]\n; hide_sos = true\n") == 0 && !g_s.hide_sos, "a commented-out setting is not read");
    CHECK(parse("[dbf]\ninput_interval_ms = 90\n\n\n[blacklist]\n\nkind_42 = true\n") == 0 && g_s.input_interval_ms == 90 && g_s.blacklist_kind[42],
          "blank lines between settings");

    {
        const char text[] = "[dbf]\nenabled = false\nhide_sos = true\n";
        size_t cut = strlen("[dbf]\nenabled = false\n");
        memset(&g_s, 0, sizeof g_s);
        CHECK(settings_parse(&g_s, text, cut, g_p, sizeof g_p) == 0 && !g_s.enabled && !g_s.hide_sos,
              "only len bytes are read, though the buffer goes on (and it needs no NUL)");
        CHECK(settings_parse(&g_s, text, strlen("[dbf]\nenabled = fa"), g_p, sizeof g_p) == 1 && g_s.enabled,
              "len may cut a line: what is left of it is read as it is, and here is a bad value");
        {
            char exact[8];
            memcpy(exact, "[dbf]\nx=", 8); /* no NUL after the last byte */
            CHECK(settings_parse(&g_s, exact, sizeof exact, g_p, sizeof g_p) == 1, "text with no terminator is read to its length");
        }
    }
    {
        const char with_nul[] = "[dbf]\nhide_sos = true\n\0hide_eagle_rearm = true\n";
        CHECK(settings_parse(&g_s, with_nul, sizeof with_nul - 1, g_p, sizeof g_p) == 1 && g_s.hide_sos && !g_s.hide_eagle_rearm,
              "a NUL byte is an ordinary character of its line, not the end of the text");
    }
    want = defaults();
    want.enabled = false;
    want.input_interval_ms = 0;
    want.bind[BIND_SLOT1] = (Binding){ BIND_KEY, 0x31 };
    want.blacklist_kind[5] = false;
    want.blacklist_kind[148] = true;
    CHECK(parse("; DBF settings\n[dbf]\nenabled = false\ninput_interval_ms = 0\n\n[bindings]\nslot1 = key:0x31\n\n[blacklist]\nkind_5 = false\nkind_148 = true\n") == 0 &&
              equal(&g_s, &want),
          "a whole file");
}

/* --- problems -------------------------------------------------------------------------------------------------- */

static void test_problems(void)
{
    CHECK(parse("[nope]\nenabled = false\nhide_sos = true\n[dbf]\nhide_eagle_rearm = true\n") == 1 && g_s.enabled && !g_s.hide_sos &&
              g_s.hide_eagle_rearm,
          "an unknown section: listed once, its keys skipped without a problem each, the next section read");
    CHECK(strcmp(g_p, "line 1: unknown section \"nope\"") == 0, "and its problem text");

    CHECK(parse("[dbf]\nfoo = 1\nhide_sos = true\n") == 1 && g_s.hide_sos && strcmp(g_p, "line 2: unknown key \"foo\" in [dbf]") == 0,
          "an unknown key: listed with its line, the lines after it are read");
    CHECK(parse("enabled = false\n[dbf]\nhide_sos = true\n") == 1 && g_s.enabled && g_s.hide_sos && strstr(g_p, "line 1: ") == g_p,
          "a key before any section: listed, skipped");
    CHECK(parse("[dbf]\njunk\nhide_sos = true\n") == 1 && g_s.hide_sos && strstr(g_p, "line 2: ") == g_p, "a line with no =: listed, skipped");
    CHECK(parse("[dbf]\n = true\nhide_sos = true\n") == 1 && g_s.hide_sos && strstr(g_p, "line 2: ") == g_p, "a line with no key: listed, skipped");
    CHECK(parse("[dbf\nenabled = false\n[dbf]\nhide_sos = true\n") == 1 && g_s.enabled && g_s.hide_sos && strstr(g_p, "line 1: ") == g_p,
          "a section header with no ]: listed once; the keys under it are skipped");
    CHECK(parse("[]\nenabled = false\n") == 1 && g_s.enabled && strstr(g_p, "line 1: ") == g_p, "an empty section name is an unknown section");
    CHECK(parse("[dbf]\nsos = 1\n[bindings]\nnext = flip\n[blacklist]\nkind_6 = true\nkind_42 = maybe\n") == 4,
          "problems in every section are all counted");
    CHECK(lines_in(g_p) == 4 && strstr(g_p, "line 2: ") == g_p && strstr(g_p, "\nline 4: ") && strstr(g_p, "\nline 6: ") &&
              strstr(g_p, "\nline 7: ") && g_p[strlen(g_p) - 1] != '\n',
          "the problems are one per line, in order, with no newline after the last");
    CHECK(parse("[dbf]\nhide_sos = true\nenabled = maybe\nhide_eagle_rearm = true\n") == 1 && g_s.hide_sos && g_s.hide_eagle_rearm,
          "a bad line does not stop the file: the lines on both sides of it are read");

    /* text a player typed is shown cut and in ASCII */
    {
        char key[400], text[500];
        memset(key, 'k', sizeof key - 1);
        key[sizeof key - 1] = '\0';
        snprintf(text, sizeof text, "[dbf]\n%s = true\n", key);
        CHECK(parse(text) == 1 && strlen(g_p) < 200 && strstr(g_p, "line 2: ") == g_p, "a 400-byte key gives a short problem line");
        CHECK(parse("[dbf]\nna\x01me\xff = true\n") == 1, "control and high bytes in a key are only a problem");
        bool ascii = true;
        for (const char* c = g_p; *c; c++) ascii &= (*c >= 0x20 && *c < 0x7f) || *c == '\n';
        CHECK(ascii, "and the problem text is printable ASCII");
    }
    {
        char big[20000];
        memset(big, 'x', sizeof big - 1);
        big[sizeof big - 1] = '\0';
        CHECK(settings_parse(&g_s, big, strlen(big), g_p, sizeof g_p) == 1, "one 20000-byte line without newline: one problem");
    }
}

static void test_problem_buffer(void)
{
    const char* text = "[dbf]\nfoo = 1\nbar = 2\nbaz = 3\n";
    char full[512], small[512];
    size_t first;
    CHECK(settings_parse(&g_s, text, strlen(text), full, sizeof full) == 3 && lines_in(full) == 3, "three problems, three lines");
    first = strcspn(full, "\n");
    CHECK(settings_parse(&g_s, text, strlen(text), small, first + 1) == 3 && strlen(small) == first && memcmp(small, full, first) == 0,
          "a buffer that holds exactly the first problem gets it whole; the count still says 3");
    CHECK(settings_parse(&g_s, text, strlen(text), small, first) == 3 && small[0] == '\0', "one byte short of the first problem: an empty string, still 3");
    CHECK(settings_parse(&g_s, text, strlen(text), small, 1) == 3 && small[0] == '\0', "a buffer of 1 byte is just the terminator");
    CHECK(settings_parse(&g_s, text, strlen(text), small, strlen(full) - 1) == 3 && lines_in(small) == 2 && strncmp(small, full, strlen(small)) == 0,
          "one byte short of all three: the first two, whole");
    CHECK(settings_parse(&g_s, text, strlen(text), small, strlen(full) + 1) == 3 && strcmp(small, full) == 0, "exactly enough for all three");
    CHECK(settings_parse(&g_s, text, strlen(text), NULL, 0) == 3, "no buffer: only the count");
    CHECK(settings_parse(&g_s, text, strlen(text), NULL, 100) == 3, "a NULL buffer with a size is not written");
    small[0] = 'x';
    CHECK(settings_parse(&g_s, text, strlen(text), small, 0) == 3 && small[0] == 'x', "size 0 writes nothing");
    {
        /* a long problem first and a short one after it: when the long one does not fit, the short one is not added either,
         * so the text is always the first problems of the list */
        const char* uneven = "[dbf]\nfooooooooooooooooooooooooooooo = 1\nb = 2\n";
        char both[256];
        size_t second_len;
        CHECK(settings_parse(&g_s, uneven, strlen(uneven), both, sizeof both) == 2 && lines_in(both) == 2, "an uneven pair: two problems");
        second_len = strlen(strchr(both, '\n') + 1);
        CHECK(settings_parse(&g_s, uneven, strlen(uneven), small, second_len + 1) == 2 && small[0] == '\0',
              "room for the second problem only: neither is added");
    }
    memset(small, 'z', sizeof small);
    CHECK(settings_parse(&g_s, "[dbf]\nhide_sos = true\n", strlen("[dbf]\nhide_sos = true\n"), small, sizeof small) == 0 && small[0] == '\0', "no problems: the buffer is an empty string");
}

/* --- [bindings] ------------------------------------------------------------------------------------------------ */

static bool binding_is(const char* value, BindAction action, uint8_t kind, uint16_t code)
{
    char text[128];
    static const char* const names[BIND_COUNT] = { "next", "previous", "confirm", "slot1", "slot2", "slot3", "slot4" };
    snprintf(text, sizeof text, "[bindings]\n%s = %s\n", names[action], value);
    return parse(text) == 0 && g_s.bind[action].kind == kind && g_s.bind[action].code == code;
}

static bool binding_refused(const char* value)
{
    char text[128];
    DbfSettings d = defaults();
    snprintf(text, sizeof text, "[bindings]\nslot2 = %s\n", value);
    return parse(text) == 1 && equal(&g_s, &d) && strstr(g_p, "line 2: ") == g_p;
}

static void test_binding_values(void)
{
    char name[96];
    CHECK(binding_is("none", BIND_SLOT1, BIND_NONE, 0), "none");
    CHECK(binding_is("wheel_up", BIND_SLOT1, BIND_WHEEL_UP, 0), "wheel_up");
    CHECK(binding_is("wheel_down", BIND_SLOT1, BIND_WHEEL_DOWN, 0), "wheel_down");
    for (unsigned n = 1; n <= 5; n++) {
        char value[16];
        snprintf(value, sizeof value, "mouse%u", n);
        snprintf(name, sizeof name, "%s", value);
        CHECK(binding_is(value, BIND_SLOT1, BIND_MOUSE, (uint16_t)n), name);
    }
    CHECK(binding_is("key:0x31", BIND_SLOT1, BIND_KEY, 0x31), "key:0x31");
    CHECK(binding_is("key:0X7a", BIND_SLOT1, BIND_KEY, 0x7A), "key:0X7a (hex digits in either case)");
    CHECK(binding_is("key:0x1", BIND_SLOT1, BIND_KEY, 0x01), "key:0x1 (one hex digit)");
    CHECK(binding_is("key:0xFE", BIND_SLOT1, BIND_KEY, 0xFE), "key:0xFE (the largest)");
    CHECK(binding_is("key:a", BIND_SLOT1, BIND_KEY, 'A'), "key:a is VK 'A'");
    CHECK(binding_is("key:Z", BIND_SLOT1, BIND_KEY, 'Z'), "key:Z is VK 'Z'");
    CHECK(binding_is("key:f", BIND_SLOT1, BIND_KEY, 'F'), "key:f is the letter F, not a function key");
    CHECK(binding_is("key:0", BIND_SLOT1, BIND_KEY, '0'), "key:0 is VK '0'");
    CHECK(binding_is("key:9", BIND_SLOT1, BIND_KEY, '9'), "key:9 is VK '9'");
    CHECK(binding_is("key:f1", BIND_SLOT1, BIND_KEY, 0x70), "key:f1 is VK_F1");
    CHECK(binding_is("key:F12", BIND_SLOT1, BIND_KEY, 0x7B), "key:F12 is VK_F12");
    CHECK(binding_is("key:f13", BIND_SLOT1, BIND_KEY, 0x7C), "key:f13 is VK_F13");
    CHECK(binding_is("key:f24", BIND_SLOT1, BIND_KEY, 0x87), "key:f24 is VK_F24");
    CHECK(binding_is("Mouse2", BIND_SLOT1, BIND_MOUSE, 2), "binding values are not case sensitive");
    CHECK(binding_is("WHEEL_UP", BIND_SLOT1, BIND_WHEEL_UP, 0), "WHEEL_UP");
    CHECK(binding_is("KEY:0x41", BIND_SLOT1, BIND_KEY, 0x41), "KEY:0x41");

    static const struct { const char* name; uint16_t mask; } pads[] = {
        { "a", 0x1000 }, { "b", 0x2000 }, { "x", 0x4000 }, { "y", 0x8000 }, { "lb", 0x0100 }, { "rb", 0x0200 },
        { "back", 0x0020 }, { "start", 0x0010 }, { "ls", 0x0040 }, { "rs", 0x0080 }, { "dpad_up", 0x0001 },
        { "dpad_down", 0x0002 }, { "dpad_left", 0x0004 }, { "dpad_right", 0x0008 },
    };
    for (size_t i = 0; i < sizeof pads / sizeof pads[0]; i++) {
        char value[32];
        snprintf(value, sizeof value, "pad:%s", pads[i].name);
        snprintf(name, sizeof name, "%s is 0x%04x", value, pads[i].mask);
        CHECK(binding_is(value, BIND_SLOT2, BIND_PAD, pads[i].mask), name);
    }
    CHECK(binding_is("pad:DPAD_UP", BIND_SLOT2, BIND_PAD, 0x0001), "pad:DPAD_UP");

    static const char* const bad[] = {
        "", "keyboard", "wheel", "wheel_left", "mouse", "mouse0", "mouse6", "mouse10", "mouse1x", "key", "key:", "key:0x", "key:0x0",
        "key:0x00", "key:0xFF", "key:0x100", "key:0x031", "key:0x0031", "key:0xZZ", "key:ab", "key:-", "key: a", "key:f0", "key:f25", "key:f100", "key:f01", "key:fa",
        "pad", "pad:", "pad:c", "pad:dpad", "pad:dpad_up_left", "pad: a", "pad:a b", "none x", "0x31", "31", "a",
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        char text[128];
        snprintf(text, sizeof text, "\"%s\" is refused: listed, the binding stays", bad[i]);
        CHECK(binding_refused(bad[i]), text);
    }
}

static void test_binding_actions(void)
{
    static const char* const names[BIND_COUNT] = { "next", "previous", "confirm", "slot1", "slot2", "slot3", "slot4" };
    for (int a = 0; a < BIND_COUNT; a++) {
        char text[96], name[96];
        DbfSettings want = defaults();
        want.bind[a] = (Binding){ BIND_KEY, (uint16_t)(0x41 + a) };
        snprintf(text, sizeof text, "[bindings]\n%s = key:0x%02x\n", names[a], 0x41 + a);
        snprintf(name, sizeof name, "[bindings] %s sets that action only", names[a]);
        CHECK(parse(text) == 0 && equal(&g_s, &want), name);
    }
    DbfSettings want = defaults();
    want.bind[BIND_NEXT].kind = BIND_NONE;
    want.bind[BIND_NEXT].code = 0;
    CHECK(parse("[bindings]\nnext = none\n") == 0 && equal(&g_s, &want), "next = none clears the default");
    CHECK(parse("[bindings]\nNEXT = mouse3\n") == 0 && g_s.bind[BIND_NEXT].kind == BIND_MOUSE && g_s.bind[BIND_NEXT].code == 3, "action names are not case sensitive");
    CHECK(parse("[bindings]\nslot5 = key:a\n") == 1 && is_default() && strstr(g_p, "unknown key \"slot5\" in [bindings]") != NULL, "slot5 is an unknown key");
    CHECK(parse("[bindings]\nenabled = true\n") == 1 && is_default(), "a [dbf] key in [bindings] is unknown there");
    CHECK(parse("[dbf]\nnext = none\n") == 1 && is_default(), "a [bindings] key in [dbf] is unknown there");
    CHECK(parse("[bindings]\nnext = flip\nprevious = key:a\n") == 1 && g_s.bind[BIND_NEXT].kind == BIND_WHEEL_DOWN &&
              g_s.bind[BIND_PREVIOUS].kind == BIND_KEY,
          "a bad binding keeps that action's default and the next line is read");
    CHECK(strstr(g_p, "\"flip\"") != NULL && strstr(g_p, "next") != NULL, "and the problem names the action and shows the value");
    CHECK(parse("[bindings]\nnext = key:a\nnext = bogus\n") == 1 && g_s.bind[BIND_NEXT].kind == BIND_KEY && g_s.bind[BIND_NEXT].code == 'A',
          "a bad value after a good one leaves the good one");
    CHECK(parse("[bindings]\nslot1 = key:a\nslot2 = key:a\n") == 0 && g_s.bind[BIND_SLOT1].code == 'A' && g_s.bind[BIND_SLOT2].code == 'A',
          "two actions may share an input (the file does not forbid it)");
}

/* --- [blacklist] ----------------------------------------------------------------------------------------------- */

static void test_blacklist(void)
{
    DbfSettings want;
    CHECK(parse("[blacklist]\nkind_5 = false\n") == 0 && !g_s.blacklist_kind[5], "kind_5 = false turns the default off");
    want = defaults();
    want.blacklist_kind[42] = true;
    CHECK(parse("[blacklist]\nkind_42 = true\n") == 0 && equal(&g_s, &want), "kind_42 = true hides kind 42 only");
    want = defaults();
    want.blacklist_kind[199] = true;
    CHECK(parse("[blacklist]\nkind_199 = 1\n") == 0 && equal(&g_s, &want), "kind_199 (the largest slot) = 1");
    want = defaults();
    want.blacklist_kind[148] = true;
    CHECK(parse("[blacklist]\nKIND_148 = True\n") == 0 && equal(&g_s, &want), "KIND_148 = True (case)");
    CHECK(parse("[blacklist]\nkind_42 = true\nkind_42 = false\n") == 0 && !g_s.blacklist_kind[42], "a later line wins");
    CHECK(parse("[blacklist]\nkind_5 = true\nkind_42 = true\nkind_148 = true\nkind_199 = true\n") == 0 && g_s.blacklist_kind[5] &&
              g_s.blacklist_kind[42] && g_s.blacklist_kind[148] && g_s.blacklist_kind[199],
          "every kind of the table");

    DbfSettings d = defaults();
    CHECK(parse("[blacklist]\nkind_6 = true\n") == 1 && equal(&g_s, &d) && strstr(g_p, "unknown key \"kind_6\" in [blacklist]") != NULL,
          "kind_6 is not in the table: an unknown key");
    CHECK(parse("[blacklist]\nkind_0 = true\nkind_1 = true\nkind_198 = true\n") == 3 && equal(&g_s, &d), "kinds the table does not name are unknown keys");
    CHECK(parse("[blacklist]\nkind_200 = true\nkind_4294967299 = true\nkind_99999999999999999999 = true\n") == 3 && equal(&g_s, &d),
          "kind 200 and larger, and ids too long for a number, are unknown keys");
    CHECK(parse("[blacklist]\nkind_ = true\nkind_x = true\nkind_4x = true\nkind__5 = true\nkind_-5 = true\nkind_5.0 = true\nkind = true\n") == 7 &&
              equal(&g_s, &d),
          "malformed kind names are unknown keys");
    CHECK(parse("[blacklist]\nkind_42 = maybe\n") == 1 && equal(&g_s, &d) && strstr(g_p, "\"maybe\"") != NULL && strstr(g_p, "kind_42") != NULL,
          "a bad value: listed with the key, the kind unchanged");
    CHECK(parse("[blacklist]\nkind_5 = false\nkind_5 = maybe\n") == 1 && !g_s.blacklist_kind[5], "a bad value after a good one leaves the good one");
    CHECK(parse("[dbf]\nkind_42 = true\n") == 1 && equal(&g_s, &d), "a kind in [dbf] is unknown there");
    CHECK(parse("[blacklist]\nhide_sos = true\nenabled = false\n") == 2 && equal(&g_s, &d), "[dbf] keys in [blacklist] are unknown there");
    CHECK(parse("[blacklist]\nkind_42 = true\nenabled = false\nkind_148 = true\n") == 1 && g_s.blacklist_kind[42] && g_s.blacklist_kind[148] && g_s.enabled,
          "an unknown key among kinds does not stop the rest");
}


/* --- bind_describe ----------------------------------------------------------------------------------------------- */

static bool describes(uint8_t kind, uint16_t code, const char* want)
{
    Binding b = { kind, code };
    char out[32];
    memset(out, 'x', sizeof out);
    bind_describe(&b, out, sizeof out);
    if (strcmp(out, want) == 0) return true;
    printf("  binding kind %u code 0x%x described as \"%s\", expected \"%s\"\n", kind, code, out, want);
    return false;
}

static void test_describe_spellings(void)
{
    static const struct { const char* name; uint16_t mask; } pads[] = {
        { "a", 0x1000 }, { "b", 0x2000 }, { "x", 0x4000 }, { "y", 0x8000 }, { "lb", 0x0100 }, { "rb", 0x0200 },
        { "back", 0x0020 }, { "start", 0x0010 }, { "ls", 0x0040 }, { "rs", 0x0080 }, { "dpad_up", 0x0001 },
        { "dpad_down", 0x0002 }, { "dpad_left", 0x0004 }, { "dpad_right", 0x0008 },
    };
    CHECK(describes(BIND_NONE, 0, "none"), "unbound reads none");
    CHECK(describes(BIND_WHEEL_UP, 0, "wheel_up") && describes(BIND_WHEEL_DOWN, 0, "wheel_down"), "the wheel");
    CHECK(describes(BIND_WHEEL_UP, 5, "wheel_up"), "a wheel binding's code is not looked at");
    CHECK(describes(BIND_MOUSE, 1, "mouse1") && describes(BIND_MOUSE, 5, "mouse5"), "mouse buttons 1 and 5");
    CHECK(describes(BIND_KEY, 'A', "key:a") && describes(BIND_KEY, 'Z', "key:z"), "letters, lower case");
    CHECK(describes(BIND_KEY, 'F', "key:f"), "the letter F is not a function key");
    CHECK(describes(BIND_KEY, '0', "key:0") && describes(BIND_KEY, '9', "key:9"), "digits");
    CHECK(describes(BIND_KEY, 0x70, "key:f1") && describes(BIND_KEY, 0x7B, "key:f12") && describes(BIND_KEY, 0x87, "key:f24"),
          "function keys");
    CHECK(describes(BIND_KEY, 0x1B, "key:0x1B") && describes(BIND_KEY, 0x01, "key:0x01") && describes(BIND_KEY, 0xFE, "key:0xFE"),
          "any other key in hex, two digits");
    CHECK(describes(BIND_KEY, 0x88, "key:0x88") && describes(BIND_KEY, 0x40, "key:0x40") && describes(BIND_KEY, 0x2F, "key:0x2F"),
          "the codes just outside the letters, digits and function keys are hex too");
    for (size_t i = 0; i < sizeof pads / sizeof pads[0]; i++) {
        char want[32];
        snprintf(want, sizeof want, "pad:%s", pads[i].name);
        CHECK(describes(BIND_PAD, pads[i].mask, want), want);
    }
}

static void test_describe_unusable(void)
{
    CHECK(describes(BIND_KEY, 0, "none") && describes(BIND_KEY, 0xFF, "none") && describes(BIND_KEY, 0x100, "none"),
          "a key code outside 1 to 0xFE is none, as bind_init takes it");
    CHECK(describes(BIND_MOUSE, 0, "none") && describes(BIND_MOUSE, 6, "none"), "a mouse code outside 1 to 5");
    CHECK(describes(BIND_PAD, 0, "none") && describes(BIND_PAD, 0x0003, "none") && describes(BIND_PAD, 0x0400, "none"),
          "a pad mask that is not exactly one button");
    CHECK(describes(9, 0x41, "none") && describes(255, 1, "none"), "an unknown kind");
}

static void test_describe_round_trip(void)
{
    /* Every binding the parser can make reads back, through the parser, as itself. */
    Binding all[512];
    int n = 0;
    bool every = true;
    all[n++] = (Binding){ BIND_NONE, 0 };
    all[n++] = (Binding){ BIND_WHEEL_UP, 0 };
    all[n++] = (Binding){ BIND_WHEEL_DOWN, 0 };
    for (uint16_t m = 1; m <= 5; m++) all[n++] = (Binding){ BIND_MOUSE, m };
    for (uint16_t k = 1; k <= 0xFE; k++) all[n++] = (Binding){ BIND_KEY, k };
    for (int bit = 0; bit < 16; bit++) {
        uint16_t mask = (uint16_t)(1u << bit);
        if (mask == 0x0400 || mask == 0x0800) continue; /* XInput bits the settings file has no button name for */
        all[n++] = (Binding){ BIND_PAD, mask };
    }
    for (int i = 0; i < n; i++) {
        char out[32], text[64];
        Binding b = all[i];
        bind_describe(&b, out, sizeof out);
        snprintf(text, sizeof text, "[bindings]\nconfirm = %s\n", out);
        if (parse(text) != 0 || g_s.bind[BIND_CONFIRM].kind != b.kind || g_s.bind[BIND_CONFIRM].code != b.code) {
            printf("  kind %u code 0x%x -> \"%s\" does not parse back to itself\n", b.kind, b.code, out);
            every = false;
        }
    }
    CHECK(n > 270 && every, "describe, then parse, gives back every binding the parser can make (key 1 to 0xFE, mouse, wheel, pads)");
}

static void test_describe_defaults(void)
{
    DbfSettings d = defaults();
    char out[32];
    bind_describe(&d.bind[BIND_NEXT], out, sizeof out);
    CHECK(strcmp(out, "wheel_down") == 0, "the default Next reads wheel_down");
    bind_describe(&d.bind[BIND_PREVIOUS], out, sizeof out);
    CHECK(strcmp(out, "wheel_up") == 0, "Previous wheel_up");
    bind_describe(&d.bind[BIND_CONFIRM], out, sizeof out);
    CHECK(strcmp(out, "mouse1") == 0, "Confirm mouse1");
    bind_describe(&d.bind[BIND_SLOT1], out, sizeof out);
    CHECK(strcmp(out, "none") == 0, "the slot hotkeys read none");
}

static void test_describe_buffer(void)
{
    Binding b = { BIND_PAD, 0x0008 }; /* pad:dpad_right, 14 bytes */
    char out[32];
    memset(out, 'x', sizeof out);
    bind_describe(&b, out, 15);
    CHECK(strcmp(out, "pad:dpad_right") == 0 && out[15] == 'x', "exactly fitting: whole, terminated, nothing past it");
    memset(out, 'x', sizeof out);
    bind_describe(&b, out, 14);
    CHECK(strcmp(out, "pad:dpad_righ") == 0 && out[14] == 'x', "one byte short: cut, terminated");
    memset(out, 'x', sizeof out);
    bind_describe(&b, out, 1);
    CHECK(out[0] == '\0' && out[1] == 'x', "a buffer of one byte: just the terminator");
    memset(out, 'x', sizeof out);
    bind_describe(&b, out, 0);
    CHECK(out[0] == 'x', "a buffer of none: untouched");
    bind_describe(&b, NULL, 8);
    CHECK(true, "a NULL buffer: nothing happens");
    memset(out, 'x', sizeof out);
    bind_describe(NULL, out, sizeof out);
    CHECK(strcmp(out, "none") == 0, "a NULL binding reads none");
}

int main(void)
{
    test_defaults();
    test_parse_nothing();
    test_dbf_booleans();
    test_boolean_forms();
    test_interval();
    test_format();
    test_problems();
    test_problem_buffer();
    test_binding_values();
    test_binding_actions();
    test_blacklist();
    test_describe_spellings();
    test_describe_unusable();
    test_describe_round_trip();
    test_describe_defaults();
    test_describe_buffer();
    printf("%s\n", test_failures() == 0 ? "PASS test_settings" : "FAIL test_settings");
    TEST_MAIN_END
}
