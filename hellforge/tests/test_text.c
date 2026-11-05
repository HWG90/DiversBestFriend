/* Tests for src/text.c, the text every unit shares: the line built piece by piece, the stratagems' names (the render
 * thread's dbf_kind_name and the copy any thread may take) and the codes as "^ > v <". The names and arrows moved here from
 * ui_settings.c (Task 12, so that the snapshot no longer depends on a UI unit); the Status tab's own drawing of them stays
 * in test_ui_settings.c. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "game.h"
#include "test.h"
#include "text.h"

/* --- the line -------------------------------------------------------------------------------------------------- */

static void test_line(void)
{
    DbfLine l;
    dbf_line_begin(&l, "Entry: ");
    dbf_line_add(&l, "entering ");
    dbf_line_add_uint(&l, 0);
    dbf_line_add(&l, "/");
    dbf_line_add_uint(&l, 4294967295u);
    CHECK(strcmp(l.text, "Entry: entering 0/4294967295") == 0 && l.length == strlen(l.text),
          "a line from pieces: text, 0 and the largest number spelt out");
    dbf_line_begin(&l, NULL);
    CHECK(l.text[0] == '\0' && l.length == 0, "begin with NULL: an empty line");
    dbf_line_add(&l, NULL);
    CHECK(l.text[0] == '\0' && l.length == 0, "adding NULL adds nothing");
    dbf_line_begin(&l, "x");
    dbf_line_begin(&l, "y");
    CHECK(strcmp(l.text, "y") == 0, "begin starts again");
}

static void test_line_is_cut(void)
{
    DbfLine l;
    char long_text[DBF_LINE_SIZE * 2];
    memset(long_text, 'a', sizeof long_text - 1);
    long_text[sizeof long_text - 1] = '\0';
    dbf_line_begin(&l, long_text);
    CHECK(l.length == DBF_LINE_SIZE - 1 && strlen(l.text) == DBF_LINE_SIZE - 1, "a text too long is cut to the line");
    dbf_line_add(&l, "b");
    dbf_line_add_uint(&l, 7);
    CHECK(l.length == DBF_LINE_SIZE - 1 && l.text[DBF_LINE_SIZE - 2] == 'a', "a full line takes nothing more");
    memset(long_text, 'c', DBF_LINE_SIZE - 3);
    long_text[DBF_LINE_SIZE - 3] = '\0';
    dbf_line_begin(&l, long_text);
    dbf_line_add_uint(&l, 12345);
    CHECK(l.length == DBF_LINE_SIZE - 1 && memcmp(l.text + DBF_LINE_SIZE - 3, "12", 2) == 0,
          "a number that does not fit keeps its first digits");
}

static void test_copy(void)
{
    char small[4];
    char big[16];
    dbf_text_copy(big, sizeof big, "abc");
    CHECK(strcmp(big, "abc") == 0, "a copy that fits");
    dbf_text_copy(small, sizeof small, "abcdef");
    CHECK(strcmp(small, "abc") == 0, "a copy that does not fit is cut and terminated");
    dbf_text_copy(big, sizeof big, NULL);
    CHECK(big[0] == '\0', "NULL copies as empty");
    big[0] = 'z';
    dbf_text_copy(big, 0, "abc");
    CHECK(big[0] == 'z', "size 0 writes nothing");
    dbf_text_copy(NULL, 4, "abc");
    CHECK(true, "a NULL destination does nothing");
}

/* --- names ----------------------------------------------------------------------------------------------------- */

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

static void test_kind_name_copy(void)
{
    char name[48], tiny[6];
    const char* shared = dbf_kind_name(777u);
    dbf_kind_name_copy(118, name, sizeof name);
    CHECK(strcmp(name, "Orbital Precision Strike") == 0, "the copy of a named kind");
    dbf_kind_name_copy(151, name, sizeof name);
    CHECK(strcmp(name, "Stratagem 151") == 0, "the copy of a HellForge kind");
    CHECK(strcmp(shared, "Stratagem 777") == 0, "the copy does not use dbf_kind_name's static text");
    dbf_kind_name_copy(118, tiny, sizeof tiny);
    CHECK(strcmp(tiny, "Orbit") == 0, "a copy that does not fit is cut and terminated");
    dbf_kind_name_copy(118, NULL, 8);
    dbf_kind_name_copy(118, name, 0);
    CHECK(true, "a NULL or empty destination does nothing");
}

/* --- arrows ---------------------------------------------------------------------------------------------------- */

static void test_arrows(void)
{
    static const uint8_t all[8] = { 1, 2, 3, 4, 4, 3, 2, 1 };
    static const uint8_t bad[4] = { 1, 0, 5, 255 };
    uint8_t long_code[DBF_CODE_CAPACITY + 4];
    char out[64], small[4];
    dbf_code_arrows(all, 8, out, sizeof out);
    CHECK(strcmp(out, "^ > v < < v > ^") == 0, "1 up, 2 right, 3 down, 4 left, separated by spaces");
    dbf_code_arrows(bad, 4, out, sizeof out);
    CHECK(strcmp(out, "^ ? ? ?") == 0, "a direction outside 1 to 4 shows as ?");
    dbf_code_arrows(all, 0, out, sizeof out);
    CHECK(out[0] == '\0', "no directions: empty");
    dbf_code_arrows(NULL, 5, out, sizeof out);
    CHECK(out[0] == '\0', "no code: empty");
    for (size_t i = 0; i < sizeof long_code; i++) long_code[i] = 1;
    dbf_code_arrows(long_code, sizeof long_code, out, sizeof out);
    CHECK(strlen(out) == 2 * DBF_CODE_CAPACITY - 1, "at most DBF_CODE_CAPACITY directions");
    dbf_code_arrows(all, 8, small, sizeof small);
    CHECK(strcmp(small, "^ >") == 0, "cut to fit and terminated");
    small[0] = 'z';
    dbf_code_arrows(all, 8, small, 0);
    CHECK(small[0] == 'z', "size 0 writes nothing");
}

int main(void)
{
    test_line();
    test_line_is_cut();
    test_copy();
    test_kind_names();
    test_kind_name_copy();
    test_arrows();
    printf("%s\n", test_failures() == 0 ? "PASS test_text" : "FAIL test_text");
    TEST_MAIN_END
}
