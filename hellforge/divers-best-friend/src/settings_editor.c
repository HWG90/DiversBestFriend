#include <ctype.h>
#include <string.h>
#include "text.h"
#include "addresses_25480438.h"
#include "hud_options.h"
#include "settings_editor.h"
#include "editor_catalog_icons.h"

static const char* const actions[] = {"Next stratagem", "Previous stratagem", "Confirm", "Slot 1", "Slot 2", "Slot 3", "Slot 4"};
_Static_assert(sizeof actions / sizeof actions[0] == BIND_COUNT, "all actions have editor labels");

/* Render-thread state only. Capture changes the text draft, never the live bindings. */
static struct {
    int action;
    bool initialized, capturing, armed;
    char text[32];
    Binding saved;
} editor;
static uint64_t changed_rows, hidden_rows;

bool editor_apply(DbfSettings* s, const UiEvent* e)
{
    if (!s || !e) return false;
    if (e->kind == UI_HUD_OPTION) return hud_option_set(s, (unsigned)e->a, e->b);
    if (e->kind == UI_BINDING) {
        unsigned packed = (unsigned)e->b;
        if (packed >> 16 > BIND_PAD) return false;
        Binding b = {.kind = (uint8_t)(packed >> 16), .code = (uint16_t)packed};
        return settings_set_binding(s, (unsigned)e->a, b);
    }
    if (e->kind != UI_BLACKLIST || !e->changed_rows || dbf_blacklist_kind_count > 64 ||
        (dbf_blacklist_kind_count < 64 && e->changed_rows >> dbf_blacklist_kind_count)) return false;
    for (int i = 0; i < dbf_blacklist_kind_count; ++i) {
        uint64_t bit = UINT64_C(1) << i;
        if (e->changed_rows & bit)
            settings_set_blacklisted(s, dbf_blacklist_kinds[i].kind, (e->hidden_rows & bit) != 0);
    }
    return true;
}

static int apply_button(const OvApi* ov, const char* label)
{
    if (ov->version >= 6 && ov->size >= offsetof(OvApi, button_primary) + sizeof ov->button_primary && ov->button_primary)
        return ov->button_primary(label);
    return ov->button(label);
}

static void capture(const OvApi* ov, uint16_t pad)
{
    if (ov->is_focused && !ov->is_focused()) { editor.capturing = false; return; }
    int vk = 0;
    for (int k = 1; k <= 254; ++k) {
        if (ov->key_down(k)) { vk = k; break; }
    }
    /* The host reports mouse buttons separately while it owns the window. */
    static const int mouse_vk[] = {1, 2, 4, 5, 6};
    if (!vk && ov->mouse_down) {
        for (int i = 0; i < 3; ++i) if (ov->mouse_down(i)) { vk = mouse_vk[i]; break; }
    }
    float wheel = ov->mouse_wheel ? ov->mouse_wheel() : 0;
    if (!editor.armed) {
        editor.armed = !vk && !pad && wheel == 0;
        return;
    }
    if (vk == 27) { editor.capturing = false; return; }
    Binding b = {0};
    if (vk) {
        b.kind = BIND_KEY;
        b.code = (uint16_t)vk;
        for (int i = 0; i < 5; ++i)
            if (vk == mouse_vk[i]) { b.kind = BIND_MOUSE; b.code = (uint16_t)(i + 1); break; }
    } else if (wheel != 0) {
        b.kind = wheel > 0 ? BIND_WHEEL_UP : BIND_WHEEL_DOWN;
    } else if (pad && !(pad & (pad - 1)) && !(pad & 0x0c00)) {
        b.kind = BIND_PAD;
        b.code = pad;
    } else return;
    bind_describe(&b, editor.text, sizeof editor.text);
    editor.capturing = false;
}

static void bindings(const OvApi* ov, const DbfSnapshot* snap, bool combo, const char* apply_label)
{
    if (editor.capturing) {
        ov->text_disabled(editor.armed ? "Press a key, mouse button or controller button, or scroll. Esc cancels."
                                      : "Release held inputs to start capture.");
        capture(ov, snap->editor_pad);
        return;
    }
    if (combo && ov->combo("Action", &editor.action, actions, BIND_COUNT)) editor.initialized = false;
    Binding current = snap->options.bind[editor.action];
    if (!editor.initialized || current.kind != editor.saved.kind || current.code != editor.saved.code) {
        bind_describe(&current, editor.text, sizeof editor.text);
        editor.saved = current;
        editor.initialized = true;
    }
    char label[48] = "Current binding: ";
    bind_describe(&current, label + strlen(label), sizeof label - strlen(label));
    ov->text(label);
    ov->input_text("New binding", editor.text, sizeof editor.text);
    ov->text_disabled("Examples: key:f8, mouse4, wheel_up, pad:lb");
    if (ov->button("CAPTURE")) { editor.capturing = true; editor.armed = false; }
    ov->same_line();
    if (ov->button("CLEAR")) strcpy(editor.text, "none");
    Binding b = {0};
    bool valid = settings_parse_binding(editor.text, &b);
    if (!valid) ov->text_disabled("Enter a valid binding or use Capture.");
    ov->begin_disabled(!valid || (b.kind == current.kind && b.code == current.code));
    if (apply_button(ov, apply_label) && valid) {
        UiEvent e = {.kind = UI_BINDING, .a = editor.action, .b = b.kind * 65536 + b.code};
        if (!ui_post(&e)) ov->text("Input queue full. Apply again.");
    }
    ov->end_disabled();
}

/* The Editor browser at d8a8b46 keeps object selection beside its fields. */
static void binding_page(const OvApi* ov, const DbfSnapshot* s)
{
    if (!ov->selectable || !ov->begin_table || !ov->end_table || !ov->table_next_column) {
        if (ov->combo) bindings(ov, s, true, "APPLY BINDING");
        return;
    }
    if (!ov->begin_table("dbf-binding-editor", 2)) return;
    ov->table_next_column();
    for (int i = 0; i < BIND_COUNT; ++i) {
        if (ov->selectable(actions[i], editor.action == i) && i != editor.action) {
            editor.action = i;
            editor.initialized = editor.capturing = false;
        }
    }
    ov->table_next_column();
    ov->text(actions[editor.action]);
    bindings(ov, s, false, "APPLY BINDING");
    ov->end_table();
}

static bool matches(const char* label, unsigned kind, const char* search)
{
    if (!*search) return true;
    DbfLine id;
    dbf_line_begin(&id, NULL);
    dbf_line_add_uint(&id, kind);
    if (!strcmp(id.text, search)) return true;
    for (; *label; ++label) {
        size_t i = 0;
        while (search[i] && label[i] && tolower((unsigned char)label[i]) == tolower((unsigned char)search[i])) ++i;
        if (!search[i]) return true;
    }
    return false;
}

static void blacklist(const OvApi* ov, const DbfSettings* settings, bool searchable)
{
    if (dbf_blacklist_kind_count > 64) { ov->text("Blacklist table exceeds editor capacity."); return; }
    static char search[48];
    bool visible = false;
    if (searchable && ov->input_text) {
        if (ov->set_keyboard_focus_here && ov->key_down && ov->key_pressed &&
            ov->key_down(0x11) && ov->key_pressed('F')) ov->set_keyboard_focus_here();
        ov->input_text("Search by name or kind", search, sizeof search);
    }
    ov->text_disabled("Checked stratagems are excluded from selection.");
    for (int i = 0; i < dbf_blacklist_kind_count; ++i) {
        unsigned kind = dbf_blacklist_kinds[i].kind;
        uint64_t bit = UINT64_C(1) << i;
        int saved = settings->blacklist_kind[kind] || (kind == DBF_VAL_HIDE_SOS_KIND && settings->hide_sos) ||
                    (kind == DBF_VAL_HIDE_EAGLE_REARM_KIND && settings->hide_eagle_rearm);
        /* Keep a failed save available for retry. A published matching value
         * acknowledges the edit and clears its draft bit. */
        if (((hidden_rows & bit) != 0) == saved) changed_rows &= ~bit;
        int hidden = changed_rows & bit ? (hidden_rows & bit) != 0 : saved;
        const char* label = dbf_blacklist_kinds[i].name;
        if (kind == 71) label = "Cargo container (71)";
        if (kind == 138) label = "Cargo container (138)";
        if (searchable && ov->input_text && !matches(label, kind, search)) continue;
        visible = true;
        if (searchable && ov->cursor_screen_pos && ov->dummy && ov->text_line_height) {
            float x, y;
            float size = ov->text_line_height();
            ov->cursor_screen_pos(&x, &y);
            editor_stratagem_icon(ov, dbf_kind_name(kind), x, y, size);
            ov->dummy(size, size); /* Same gutter for mission-only rows without artwork. */
            ov->same_line();
        }
        ov->push_id_int((int)kind);
        if (ov->checkbox(label, &hidden)) {
            if (hidden) hidden_rows |= bit;
            else hidden_rows &= ~bit;
            if (hidden != saved) changed_rows |= bit;
            else changed_rows &= ~bit;
        }
        ov->pop_id();
    }
    if (!visible) ov->text_disabled("No matching stratagems.");
    ov->begin_disabled(!changed_rows);
    if (apply_button(ov, searchable ? "APPLY BLACKLIST" : "APPLY") && changed_rows) {
        UiEvent e = {.kind = UI_BLACKLIST, .changed_rows = changed_rows, .hidden_rows = hidden_rows};
        if (!ui_post(&e)) ov->text("Input queue full. Apply again.");
    }
    ov->same_line();
    if (ov->button("DISCARD")) changed_rows = 0;
    ov->end_disabled();
}

bool editor_capturing(void)
{
    return editor.capturing;
}

void editor_page(const OvApi* ov, const DbfSnapshot* s, bool blacklist_page)
{
    if (!s || blacklist_page) editor.capturing = false;
    if (!ov || !s || !ov->button || !ov->same_line || !ov->begin_disabled || !ov->end_disabled) return;
    if (blacklist_page) {
        if (ov->checkbox && ov->push_id_int && ov->pop_id) blacklist(ov, &s->options, true);
    } else if (ov->input_text && ov->key_down) binding_page(ov, s);
}

void editor_tabs(const OvApi* ov, const DbfSnapshot* s)
{
    if (!s || !ov->button || !ov->begin_disabled || !ov->end_disabled) return;
    if (ov->combo && ov->input_text && ov->key_down && ov->same_line && ov->begin_tab_item("CONTROLS")) {
        bindings(ov, s, true, "APPLY");
        ov->end_tab_item();
    } else editor.capturing = false;
    if (ov->checkbox && ov->push_id_int && ov->pop_id && ov->same_line && ov->begin_tab_item("BLACKLIST")) {
        blacklist(ov, &s->options, false);
        ov->end_tab_item();
    }
}
