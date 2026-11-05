/* ui_settings: see ui_settings.h. */
#include <stddef.h>
#include <string.h>
#include "kind_names_25480438.h"
#include "ui_settings.h"

#define LINE_SIZE 256
#define DBF_KIND_NAME_COUNT (sizeof dbf_kind_names / sizeof dbf_kind_names[0])

/* A text line built piece by piece (no printf: the DLL needs no C runtime import for it); cut when it does not fit. */
typedef struct Line {
    char text[LINE_SIZE];
    size_t length;
} Line;

static void line_begin(Line* l, const char* first)
{
    l->length = 0;
    l->text[0] = '\0';
    if (first != NULL)
        for (const char* p = first; *p != '\0' && l->length < LINE_SIZE - 1; p++) l->text[l->length++] = *p;
    l->text[l->length] = '\0';
}

static void line_add(Line* l, const char* text)
{
    for (const char* p = text; *p != '\0' && l->length < LINE_SIZE - 1; p++) l->text[l->length++] = *p;
    l->text[l->length] = '\0';
}

static void line_add_uint(Line* l, uint32_t value)
{
    char digits[11];
    int n = 0;
    do {
        digits[n++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value != 0);
    while (n > 0 && l->length < LINE_SIZE - 1) l->text[l->length++] = digits[--n];
    l->text[l->length] = '\0';
}

const char* dbf_kind_name(uint32_t kind)
{
    static Line unnamed;
    if (kind < DBF_KIND_NAME_COUNT && dbf_kind_names[kind] != NULL) return dbf_kind_names[kind];
    line_begin(&unnamed, "Stratagem ");
    line_add_uint(&unnamed, kind);
    return unnamed.text;
}

/* "^ > v <" for the row's code (1 up, 2 right, 3 down, 4 left, anything else "?"), "no code" when it has none. */
static void code_text(Line* l, const DbfRow* r)
{
    static const char ARROWS[5] = { '?', '^', '>', 'v', '<' };
    size_t n = r->code_len;
    char one[2] = { 0, 0 };
    line_begin(l, NULL);
    if (n == 0) {
        line_add(l, "no code");
        return;
    }
    if (n > DBF_CODE_CAPACITY) n = DBF_CODE_CAPACITY;
    for (size_t i = 0; i < n; i++) {
        one[0] = r->code[i] >= 1 && r->code[i] <= 4 ? ARROWS[r->code[i]] : '?';
        if (i > 0) line_add(l, " ");
        line_add(l, one);
    }
}

static void draw_feature(const OvApi* ov, const DbfSnapshot* s, Feature f)
{
    Line l;
    const char* reason = s->admit_reason[f];
    line_begin(&l, adm_feature_name(f));
    switch (s->admit[f]) {
    case ADMIT_OK:
        line_add(&l, ": OK");
        reason = "";
        break;
    case ADMIT_PENDING: line_add(&l, ": Waiting"); break;
    default: line_add(&l, ": Off"); break;
    }
    if (reason[0] != '\0') {
        line_add(&l, " (");
        line_add(&l, reason);
        line_add(&l, ")");
    }
    ov->text(l.text);
}

static void draw_stratagems(const OvApi* ov, const GameView* g)
{
    int rows = g->row_count;
    if (rows <= 0) return;
    if (rows > (int)DBF_VAL_CARD_COUNT) rows = (int)DBF_VAL_CARD_COUNT; /* the macro is unsigned: compare as int */
    ov->separator();
    if (!ov->begin_table("dbf-stratagems", 2)) return;
    ov->table_setup_column("Stratagem");
    ov->table_setup_column("Code");
    ov->table_headers_row();
    for (int i = 0; i < rows; i++) {
        Line code;
        ov->table_next_row();
        ov->table_next_column();
        ov->text(dbf_kind_name(g->rows[i].kind));
        ov->table_next_column();
        code_text(&code, &g->rows[i]);
        ov->text(code.text);
    }
    ov->end_table();
}

static void draw_status(const OvApi* ov, const DbfSnapshot* s)
{
    Line l;
    bool in_mission;
    if (s == NULL) {
        ov->text("Waiting for the first update from the game");
        return;
    }
    if (s->build_ok) {
        ov->text("Game build 25480438: OK");
    } else {
        line_begin(&l, "Game build: ");
        line_add(&l, s->build_reason[0] != '\0' ? s->build_reason : "not verified");
        ov->text(l.text);
    }
    for (int f = 0; f < FEAT_COUNT; f++) draw_feature(ov, s, (Feature)f);
    ov->separator();

    line_begin(&l, "Overlay Host API ");
    line_add_uint(&l, s->host_version);
    ov->text(l.text);

    in_mission = s->game.in_gameplay && s->game.hud_ready;
    if (in_mission) {
        ov->text("In a mission: yes");
    } else {
        line_begin(&l, "In a mission: no");
        if (s->game.reason[0] != '\0') {
            line_add(&l, " (");
            line_add(&l, s->game.reason);
            line_add(&l, ")");
        }
        ov->text(l.text);
    }
    ov->text(s->game.menu_open ? "Stratagem menu: open" : "Stratagem menu: closed");
    if (in_mission && s->game.reason[0] != '\0') { /* outside a mission the reason is in the mission line above */
        line_begin(&l, "Reader: ");
        line_add(&l, s->game.reason);
        ov->text(l.text);
    }
    if (in_mission && !s->game.scramble_known) ov->text("Codes do not follow scrambling yet");
    if (in_mission) draw_stratagems(ov, &s->game);
}

void ui_settings_draw(const OvApi* ov, const DbfSnapshot* s)
{
    if (ov == NULL) return;
    if (!ov->begin_tab_bar("dbf-tabs")) return;
    if (ov->begin_tab_item("Status")) {
        draw_status(ov, s);
        ov->end_tab_item();
    }
    ov->end_tab_bar();
}
