/* ui_settings: see ui_settings.h. */
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "text.h"
#include "editor_catalog_icons.h"
#include "hud_options.h"
#include "settings_editor.h"
#include "ui_settings.h"

/* "^ > v <" for the row's code (1 up, 2 right, 3 down, 4 left, anything else "?"), "no code" when it has none. */
static void code_text(DbfLine* l, const DbfRow* r)
{
    char arrows[2 * DBF_CODE_CAPACITY];
    dbf_line_begin(l, NULL);
    if (r->code_len == 0) {
        dbf_line_add(l, "no code");
        return;
    }
    dbf_code_arrows(r->code, r->code_len, arrows, sizeof arrows);
    dbf_line_add(l, arrows);
}

static void draw_feature(const OvApi* ov, const DbfSnapshot* s, Feature f)
{
    DbfLine l;
    const char* reason = s->admit_reason[f];
    dbf_line_begin(&l, f == FEAT_WEAPON ? "C weapon reader" : adm_feature_name(f));
    switch (s->admit[f]) {
    case ADMIT_OK:
        dbf_line_add(&l, ": OK");
        reason = "";
        break;
    case ADMIT_PENDING: dbf_line_add(&l, ": Waiting"); break;
    default: dbf_line_add(&l, ": Off"); break;
    }
    if (reason[0] != '\0') {
        dbf_line_add(&l, " (");
        dbf_line_add(&l, reason);
        dbf_line_add(&l, ")");
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
        DbfLine code;
        ov->table_next_row();
        ov->table_next_column();
        const char* name = dbf_kind_name(g->rows[i].kind);
        if (ov->version >= 3 && ov->size >= offsetof(OvApi, draw_image_uv) + sizeof ov->draw_image_uv &&
            ov->draw_image_uv && ov->load_image && ov->draw_layer && ov->text_line_height &&
            ov->cursor_screen_pos && ov->dummy && ov->same_line) {
            float x, y;
            float size = ov->text_line_height();
            ov->cursor_screen_pos(&x, &y);
            ov->draw_layer(OV_LAYER_WINDOW);
            editor_stratagem_icon(ov, name, x, y, size);
            ov->dummy(size, size);
            ov->same_line();
        }
        ov->text(name);
        ov->table_next_column();
        code_text(&code, &g->rows[i]);
        ov->text(code.text);
    }
    ov->end_table();
}

/* The binding names, the settings file and the state of the code entry (the list view; see ui_settings.h). */
static void draw_entry_lines(const OvApi* ov, const ListView* v)
{
    DbfLine l;
    if (!v->valid) return;
    ov->separator();
    dbf_line_begin(&l, "Bindings: ");
    dbf_line_add(&l, v->bind_next[0] != '\0' ? v->bind_next : "none");
    dbf_line_add(&l, " / ");
    dbf_line_add(&l, v->bind_previous[0] != '\0' ? v->bind_previous : "none");
    dbf_line_add(&l, " / ");
    dbf_line_add(&l, v->bind_confirm[0] != '\0' ? v->bind_confirm : "none");
    ov->text(l.text);
    if (v->bind_status[0] != '\0') ov->text(v->bind_status);

    dbf_line_begin(&l, "Settings: ");
    dbf_line_add(&l, v->settings_file[0] != '\0' ? v->settings_file : "defaults");
    dbf_line_add(&l, " (");
    dbf_line_add_uint(&l, v->settings_problems > 0 ? (uint32_t)v->settings_problems : 0u);
    dbf_line_add(&l, v->settings_problems == 1 ? " problem)" : " problems)");
    ov->text(l.text);

    dbf_line_begin(&l, "Entry: ");
    switch (v->entry_state) {
    case ENTRY_RUNNING:
        dbf_line_add(&l, "entering ");
        dbf_line_add(&l, v->entry_name);
        dbf_line_add(&l, " (");
        dbf_line_add_uint(&l, v->entry_sent);
        dbf_line_add(&l, "/");
        dbf_line_add_uint(&l, v->entry_len);
        dbf_line_add(&l, ")");
        break;
    case ENTRY_DONE: dbf_line_add(&l, "done"); break;
    case ENTRY_FAILED:
        dbf_line_add(&l, "failed");
        if (v->entry_reason[0] != '\0') {
            dbf_line_add(&l, ": ");
            dbf_line_add(&l, v->entry_reason);
        }
        break;
    default: dbf_line_add(&l, "idle"); break;
    }
    ov->text(l.text);
}

void ui_status_draw(const OvApi* ov, const DbfSnapshot* s)
{
    DbfLine l;
    bool in_mission;
    if (s == NULL) {
        ov->text("Waiting for the first update from the game");
        return;
    }
    if (s->build_ok) {
        ov->text("Game build 25480438: OK");
    } else {
        dbf_line_begin(&l, "Game build: ");
        dbf_line_add(&l, s->build_reason[0] != '\0' ? s->build_reason : "not verified");
        ov->text(l.text);
    }
    for (int f = 0; f < FEAT_COUNT; f++) draw_feature(ov, s, (Feature)f);
    ov->separator();

    dbf_line_begin(&l, "Overlay Host API ");
    dbf_line_add_uint(&l, s->host_version);
    ov->text(l.text);

    ov->text(s->hud_owned ? "Native HUD archive: connected" : "Native HUD archive: waiting");

    if (s->hud_status[0]) ov->text(s->hud_status);

    in_mission = s->game.in_gameplay && s->game.hud_ready;
    if (in_mission) {
        ov->text("In a mission: yes");
    } else {
        dbf_line_begin(&l, "In a mission: no");
        if (s->game.reason[0] != '\0') {
            dbf_line_add(&l, " (");
            dbf_line_add(&l, s->game.reason);
            dbf_line_add(&l, ")");
        }
        ov->text(l.text);
    }
    ov->text(s->game.menu_open ? "Stratagem menu: open" : "Stratagem menu: closed");
    if (in_mission && s->game.reason[0] != '\0') { /* outside a mission the reason is in the mission line above */
        dbf_line_begin(&l, "Reader: ");
        dbf_line_add(&l, s->game.reason);
        ov->text(l.text);
    }
    if (in_mission && !s->game.scramble_known) ov->text("Codes do not follow scrambling yet");
    draw_entry_lines(ov, &s->list);
    if (in_mission) draw_stratagems(ov, &s->game);
}

static void draw_option(const OvApi* ov, DbfSettings* draft, unsigned i)
{
    const HudOption* d = hud_option_descriptor(i);
    bool available = hud_option_available(draft, i);
    int original = hud_option_get(draft, d->key);
    int value = original;
    int changed;
    ov->begin_disabled(!available);
    switch (d->widget) {
    case HUD_TOGGLE:
        changed = ov->checkbox(d->label, &value);
        break;
    case HUD_CHOICE:
        --value; /* ImGui combo indices start at zero. */
        changed = ov->combo(d->label, &value, d->choices, d->max);
        ++value;
        break;
    default:
        changed = ov->slider_int(d->label, &value, d->min, d->max);
        if (changed && value >= d->min && value <= d->max) value = d->min + ((value - d->min + d->step / 2) / d->step) * d->step;
        break;
    }
    ov->end_disabled();
    if (available && changed && value >= d->min && value <= d->max && value != original) {
        UiEvent e = { .kind = UI_HUD_OPTION, .a = (int)i, .b = value };
        if (ui_post(&e)) hud_option_set(draft, i, value);
    }
}

static void draw_options(const OvApi* ov, const DbfSnapshot* s)
{
    if (!s) {
        ov->text_disabled("Waiting for the first update from the game");
        return;
    }
    DbfSettings draft = s->options;
    const char* group = "";
    for (unsigned i = 0; i < hud_option_count(); ++i) {
        const HudOption* d = hud_option_descriptor(i);
        if (strcmp(group, d->group) != 0) {
            group = d->group;
            if (ov->version >= 6 && ov->size >= offsetof(OvApi, heading) + sizeof ov->heading && ov->heading)
                ov->heading(group);
            else
                ov->text_colored(ov->theme(OV_THEME_ACCENT), group);
        }
        draw_option(ov, &draft, i);
    }
}

void ui_settings_draw(const OvApi* ov, const DbfSnapshot* s)
{
    if (ov == NULL) return;
    if (s && s->settings_save_failed) ov->text("Could not save settings.ini. Your previous settings are active.");
    if (!ov->begin_tab_bar("dbf-tabs")) return;
    if (ov->begin_tab_item("Status")) {
        ui_status_draw(ov, s);
        ov->end_tab_item();
    }
    if (ov->checkbox && ov->combo && ov->slider_int && ov->begin_disabled && ov->end_disabled &&
        ov->begin_tab_item("SETTINGS")) {
        draw_options(ov, s);
        ov->end_tab_item();
    }
    editor_tabs(ov, s);
    ov->end_tab_bar();
}
