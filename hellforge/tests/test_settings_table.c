/* Tests for src/settings.c over the generated blacklist table (no test table: admission.c defines the generated one, as it
 * does in the DLL). test_settings.c covers the rules with a small table of its own; this covers what only the real table can
 * break: its kinds fit the settings' slots, are unique, and each one has its default and can be set from the file. */
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "addresses_25480438.h"
#include "settings.h"
#include "test.h"

static DbfSettings g_s;
static char g_problems[256];
static char g_text[16384];

static bool in_table(int kind)
{
    for (int i = 0; i < dbf_blacklist_kind_count; i++)
        if ((int)dbf_blacklist_kinds[i].kind == kind) return true;
    return false;
}

static void test_table_fits_the_settings(void)
{
    bool sound = dbf_blacklist_kind_count > 0;
    bool unique = true;
    for (int i = 0; i < dbf_blacklist_kind_count; i++) {
        const DbfBlacklistKind* k = &dbf_blacklist_kinds[i];
        sound &= k->kind >= 1u && k->kind < (unsigned)DBF_BLACKLIST_SLOTS && k->name != NULL && k->name[0] != '\0';
        for (int j = 0; j < i; j++) unique &= dbf_blacklist_kinds[j].kind != k->kind;
    }
    CHECK(sound, "every kind of the generated table is 1..199 and has a name");
    CHECK(unique, "and no kind is in the table twice");
}

static void test_defaults_follow_the_table(void)
{
    bool right = true;
    settings_defaults(&g_s);
    for (int k = 0; k < DBF_BLACKLIST_SLOTS; k++) {
        bool want = false;
        for (int i = 0; i < dbf_blacklist_kind_count; i++)
            if ((int)dbf_blacklist_kinds[i].kind == k) want = dbf_blacklist_kinds[i].default_on;
        right &= g_s.blacklist_kind[k] == want;
    }
    CHECK(right, "settings_defaults gives every kind its default_on and every other slot false");
    CHECK(settings_parse(&g_s, "", 0, g_problems, sizeof g_problems) == 0, "an empty file over the generated table: no problems");
}

static void test_every_kind_can_be_set(void)
{
    size_t at = 0;
    int trues = 0;
    bool right = true;
    at += (size_t)snprintf(g_text + at, sizeof g_text - at, "[blacklist]\n");
    for (int i = 0; i < dbf_blacklist_kind_count; i++)
        at += (size_t)snprintf(g_text + at, sizeof g_text - at, "kind_%u = true\n", dbf_blacklist_kinds[i].kind);
    CHECK(settings_parse(&g_s, g_text, at, g_problems, sizeof g_problems) == 0, "kind_<id> = true for every id of the table: no problems");
    for (int k = 0; k < DBF_BLACKLIST_SLOTS; k++) {
        trues += g_s.blacklist_kind[k] ? 1 : 0;
        right &= g_s.blacklist_kind[k] == in_table(k);
    }
    CHECK(right && trues == dbf_blacklist_kind_count, "exactly the table's kinds are hidden");

    at = (size_t)snprintf(g_text, sizeof g_text, "[blacklist]\n");
    for (int i = 0; i < dbf_blacklist_kind_count; i++)
        at += (size_t)snprintf(g_text + at, sizeof g_text - at, "kind_%u = false\n", dbf_blacklist_kinds[i].kind);
    CHECK(settings_parse(&g_s, g_text, at, g_problems, sizeof g_problems) == 0, "kind_<id> = false for every id: no problems");
    trues = 0;
    for (int k = 0; k < DBF_BLACKLIST_SLOTS; k++) trues += g_s.blacklist_kind[k] ? 1 : 0;
    CHECK(trues == 0, "and none is hidden");

    right = true;
    for (int k = 0; k < DBF_BLACKLIST_SLOTS; k++) {
        if (in_table(k)) continue;
        snprintf(g_text, sizeof g_text, "[blacklist]\nkind_%d = true\n", k);
        right &= settings_parse(&g_s, g_text, strlen(g_text), g_problems, sizeof g_problems) == 1;
    }
    CHECK(right, "every id the table does not name is an unknown key");
}

int main(void)
{
    test_table_fits_the_settings();
    test_defaults_follow_the_table();
    test_every_kind_can_be_set();
    printf("%s\n", test_failures() == 0 ? "PASS test_settings_table" : "FAIL test_settings_table");
    TEST_MAIN_END
}
