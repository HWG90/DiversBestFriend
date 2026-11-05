/* ui_settings: see ui_settings.h. */
#include <stdbool.h>
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

static bool kind_is_named(uint32_t kind)
{
    return kind < DBF_KIND_NAME_COUNT && dbf_kind_names[kind] != NULL;
}

static void line_unnamed(Line* l, uint32_t kind)
{
    line_begin(l, "Stratagem ");
    line_add_uint(l, kind);
}

const char* dbf_kind_name(uint32_t kind)
{
    static Line unnamed;
    if (kind_is_named(kind)) return dbf_kind_names[kind];
    line_unnamed(&unnamed, kind);
    return unnamed.text;
}

void dbf_kind_name_copy(uint32_t kind, char* dst, size_t size)
{
    Line l;
    if (kind_is_named(kind)) {
        snap_copy_text(dst, size, dbf_kind_names[kind]);
        return;
    }
    line_unnamed(&l, kind);
    snap_copy_text(dst, size, l.text);
}

void dbf_code_arrows(const uint8_t* code, size_t n, char* dst, size_t size)
{
    static const char ARROWS[5] = { '?', '^', '>', 'v', '<' };
    size_t at = 0;
    if (dst == NULL || size == 0) return;
    if (code == NULL) n = 0;
    if (n > DBF_CODE_CAPACITY) n = DBF_CODE_CAPACITY;
    for (size_t i = 0; i < n; i++) {
        if (i > 0 && at < size - 1) dst[at++] = ' ';
        if (at < size - 1) dst[at++] = code[i] >= 1 && code[i] <= 4 ? ARROWS[code[i]] : '?';
    }
    dst[at] = '\0';
}

/* "^ > v <" for the row's code (1 up, 2 right, 3 down, 4 left, anything else "?"), "no code" when it has none. */
static void code_text(Line* l, const DbfRow* r)
{
    char arrows[2 * DBF_CODE_CAPACITY];
    line_begin(l, NULL);
    if (r->code_len == 0) {
        line_add(l, "no code");
        return;
    }
    dbf_code_arrows(r->code, r->code_len, arrows, sizeof arrows);
    line_add(l, arrows);
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

/* The binding names, the settings file and the state of the code entry (the list view; see ui_settings.h). */
static void draw_entry_lines(const OvApi* ov, const ListView* v)
{
    Line l;
    if (!v->valid) return;
    ov->separator();
    line_begin(&l, "Bindings: ");
    line_add(&l, v->bind_next[0] != '\0' ? v->bind_next : "none");
    line_add(&l, " / ");
    line_add(&l, v->bind_previous[0] != '\0' ? v->bind_previous : "none");
    line_add(&l, " / ");
    line_add(&l, v->bind_confirm[0] != '\0' ? v->bind_confirm : "none");
    ov->text(l.text);
    if (v->bind_status[0] != '\0') ov->text(v->bind_status);

    line_begin(&l, "Settings: ");
    line_add(&l, v->settings_file[0] != '\0' ? v->settings_file : "defaults");
    line_add(&l, " (");
    line_add_uint(&l, v->settings_problems > 0 ? (uint32_t)v->settings_problems : 0u);
    line_add(&l, v->settings_problems == 1 ? " problem)" : " problems)");
    ov->text(l.text);

    line_begin(&l, "Entry: ");
    switch (v->entry_state) {
    case ENTRY_RUNNING:
        line_add(&l, "entering ");
        line_add(&l, v->entry_name);
        line_add(&l, " (");
        line_add_uint(&l, v->entry_sent);
        line_add(&l, "/");
        line_add_uint(&l, v->entry_len);
        line_add(&l, ")");
        break;
    case ENTRY_DONE: line_add(&l, "done"); break;
    case ENTRY_FAILED:
        line_add(&l, "failed");
        if (v->entry_reason[0] != '\0') {
            line_add(&l, ": ");
            line_add(&l, v->entry_reason);
        }
        break;
    default: line_add(&l, "idle"); break;
    }
    ov->text(l.text);
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
    draw_entry_lines(ov, &s->list);
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
