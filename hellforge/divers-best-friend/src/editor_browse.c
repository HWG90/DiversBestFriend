#include "editor_browse.h"
#include "hud_options.h"
#include "settings_editor.h"
#include <string.h>

bool editor_browse_available(const OvApi* ov)
{
    return ov && ov->size >= offsetof(OvApi, heading) + sizeof ov->heading &&
           ov->heading && ov->begin_child && ov->end_child && ov->same_line && ov->content_region_avail &&
           ov->push_color && ov->pop_color && ov->theme && ov->selectable && ov->input_text &&
           ov->set_cursor_screen_pos && ov->selectable_ex &&
           ov->text_size && ov->item_rect && ov->draw_text && ov->set_next_item_width && ov->set_keyboard_focus_here && ov->want_text_input && ov->is_item_active && ov->key_pressed && ov->key_down &&
           ov->text && ov->textf && ov->text_disabled && ov->text_wrapped && ov->separator &&
           ov->checkbox && ov->combo && ov->slider_int && ov->small_button && ov->begin_disabled &&
           ov->end_disabled && ov->push_id_int && ov->pop_id && ov->begin_table && ov->end_table &&
           ov->table_setup_column && ov->table_headers_row && ov->table_next_row && ov->table_next_column;
}

typedef struct {
    bool dirty;
    int original, value;
} Edit;

static Edit edits[HUD_OPTION_COUNT];
static bool submitted;
static uint64_t submitted_tick;
static const char* feedback;
static int selected;
static const char* category;
static char search[96];
static bool search_active, search_id;
enum Pane { CATEGORIES, OPTIONS };
static enum Pane pane;

bool editor_browse_escape(void)
{
    if (!search_active && !search[0]) return false;
    search_active = false;
    search[0] = 0;
    /* A fresh widget ID drops ImGui's active edit buffer, including its Escape restore. */
    search_id = !search_id;
    pane = OPTIONS;
    return true;
}

static int live_value(const DbfSnapshot* s, unsigned i)
{
    return hud_option_get(&s->options, hud_option_key(i));
}

int editor_change_count(const DbfSnapshot* s)
{
    if (!s) return 0;
    int count = 0;
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i) {
        Edit* edit = &edits[i];
        if (edit->dirty && edit->value == live_value(s, i)) edit->dirty = false;
        count += edit->dirty;
    }
    if (!count) {
        submitted = false;
        feedback = NULL;
    }
    return count;
}

void editor_discard_changes(void)
{
    memset(edits, 0, sizeof edits);
    submitted = false;
    feedback = NULL;
}

static void stage(const DbfSnapshot* s, unsigned i, int value)
{
    int live = live_value(s, i);
    edits[i] = (Edit){ value != live, live, value };
    feedback = NULL;
}

void editor_reset_defaults(const DbfSnapshot* s)
{
    if (!s) return;
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i)
        stage(s, i, hud_option_descriptor(i)->initial);
}

bool editor_apply_changes(const OvApi* ov, const DbfSnapshot* s)
{
    (void)ov;
    if (!editor_change_count(s) || (submitted && submitted_tick == s->tick)) return false;
    UiEvent events[HUD_OPTION_COUNT];
    int count = 0;
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i) {
        if (!edits[i].dirty) continue;
        if (edits[i].original != live_value(s, i)) {
            feedback = "A saved value changed. Review the conflict in Review before applying.";
            return false;
        }
        events[count++] = (UiEvent){ .kind = UI_HUD_OPTION, .a = (int)i, .b = edits[i].value };
    }
    if (!ui_post_batch(events, count)) {
        feedback = "Settings queue is busy. Retry Apply.";
        return false;
    }
    submitted = true;
    submitted_tick = s->tick;
    feedback = NULL;
    return true;
}

static char folded(char c)
{
    return c >= 'A' && c <= 'Z' ? (char)(c + ('a' - 'A')) : c;
}

static bool contains(const char* text, const char* query)
{
    for (; *text; ++text) {
        size_t n = 0;
        while (query[n] && folded(text[n]) == folded(query[n])) ++n;
        if (!query[n]) return true;
    }
    return false;
}

static bool matches(const HudOption* d)
{
    if (!search[0]) return !category || strcmp(category, d->group) == 0;
    return contains(d->key, search) || contains(d->label, search) || contains(d->group, search);
}

static void value_text(const OvApi* ov, const HudOption* d, int value)
{
    if (d->widget == HUD_TOGGLE) ov->text(value ? "On" : "Off");
    else if (d->widget == HUD_CHOICE && value >= d->min && value <= d->max)
        ov->text(d->choices[value - d->min]);
    else ov->textf("%d", value);
}

/* Descriptors are grouped in display order. Index zero always searches every group. */
static int category_list(const char** names, int* current)
{
    int count = 1;
    names[0] = "All settings";
    *current = 0;
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i) {
        const char* group = hud_option_descriptor(i)->group;
        if (count > 1 && !strcmp(names[count - 1], group)) continue;
        if (category && !strcmp(category, group)) *current = count;
        names[count++] = group;
    }
    return count;
}

static void choose_category(const char** names, int index)
{
    category = index ? names[index] : NULL;
    search[0] = 0;
    selected = -1;
    pane = CATEGORIES;
}

static bool navigation_allowed(const OvApi* ov)
{
    return (!ov->is_focused || ov->is_focused()) && !ov->want_text_input() && !editor_capturing() &&
           !search_active && !ov->key_down(0x10) && !ov->key_down(0x11) && !ov->key_down(0x12);
}

static void navigate(const OvApi* ov, const char** names, int count, int current)
{
    if (ov->key_pressed(0x09)) {
        pane = pane == OPTIONS ? CATEGORIES : OPTIONS;
        return;
    }
    int delta = ov->key_pressed(0x28) - ov->key_pressed(0x26);
    if (pane == CATEGORIES) {
        int next = current + delta;
        if (delta && next >= 0 && next < count) choose_category(names, next);
        if (ov->key_pressed(0x0d) || ov->key_pressed(0x27)) pane = OPTIONS;
    } else if (delta) {
        for (int i = selected + delta; i >= 0 && i < HUD_OPTION_COUNT; i += delta) {
            if (matches(hud_option_descriptor((unsigned)i))) { selected = i; break; }
        }
    }
}

static void begin_pane(const OvApi* ov, enum Pane which, const char* id, float width, float height)
{
    ov->push_color(OV_COL_BORDER, ov->theme(which == pane ? OV_THEME_ACCENT : OV_THEME_LINE));
    ov->begin_child(id, width, height, 1);
    ov->pop_color(1);
}

static void setting_row(const OvApi* ov, const DbfSnapshot* s, DbfSettings* effective,
                        unsigned i, bool columns, bool keys, bool reveal)
{
    const HudOption* d = hud_option_descriptor(i);
    int value = hud_option_get(effective, d->key);
    const char* requirement = hud_option_requirement(effective, i);
    bool focused = pane == OPTIONS && selected == (int)i;
    ov->push_id_int((int)i);
    if (columns) {
        ov->table_next_row();
        ov->table_next_column();
    }
    /* Give the wrapped label a navigation target. Focusing it scrolls the row into
     * view without opening its combo or putting its slider into text-entry mode. */
    if (focused) ov->push_color(OV_COL_TEXT, ov->theme(OV_THEME_ACCENT));
    ov->text_wrapped(d->label);
    if (focused) ov->pop_color(1);
    float x0, y0, x1, y1;
    ov->item_rect(&x0, &y0, &x1, &y1);
    ov->set_cursor_screen_pos(x0, y0);
    if (reveal && focused) ov->set_keyboard_focus_here();
    if (ov->selectable_ex("##row", 0, x1 - x0, y1 - y0, 0)) {
        selected = (int)i;
        pane = OPTIONS;
    }
    if (columns) ov->table_next_column();
    ov->begin_disabled(requirement != NULL);
    int changed;
    if (d->widget == HUD_TOGGLE) changed = ov->checkbox("Enabled", &value);
    else if (d->widget == HUD_CHOICE) {
        ov->set_next_item_width(-1);
        value -= d->min;
        changed = ov->combo("##value", &value, d->choices, d->max - d->min + 1);
        value += d->min;
    } else {
        ov->set_next_item_width(-1);
        changed = ov->slider_int("##value", &value, d->min, d->max);
        if (changed) {
            value = d->min + (value - d->min + d->step / 2) / d->step * d->step;
            if (value > d->max) value = d->max;
        }
    }
    if (!requirement && (changed || ov->is_item_active())) {
        selected = (int)i;
        pane = OPTIONS;
    }
    ov->end_disabled();
    if (requirement) ov->text_wrapped(requirement);
    if (!requirement && keys && focused) {
        int delta = ov->key_pressed(0x27) - ov->key_pressed(0x25);
        if (delta) {
            value += delta * d->step;
            if (value > d->max) value = d->max;
            if (value < d->min) value = d->min;
            changed = 1;
        } else if (d->widget == HUD_TOGGLE && ov->key_pressed(0x0d)) {
            value = !value;
            changed = 1;
        }
    }
    if (changed && !requirement) {
        stage(s, i, value);
        hud_option_set(effective, i, value);
    }
    if (edits[i].dirty) {
        ov->text_disabled("Staged");
        ov->same_line();
        if (ov->small_button("Undo") || (keys && focused && ov->key_pressed(0x2e))) {
            stage(s, i, live_value(s, i));
            hud_option_set(effective, i, live_value(s, i));
        }
    }
    ov->pop_id();
}

void editor_browse(const OvApi* ov, const DbfSnapshot* s, bool focus_search)
{
    if (!ov || !s) return;
    editor_change_count(s);
    if (feedback) ov->text_wrapped(feedback);
    if (focus_search) pane = OPTIONS;
    float width, height, em;
    ov->content_region_avail(&width, &height);
    float ignored;
    ov->text_size(0, 0, "M", &ignored, &em);
    bool narrow = width < 32 * em;
    const char* groups[HUD_OPTION_COUNT + 1];
    int current;
    int n = category_list(groups, &current);
    if (narrow) {
        ov->text_disabled("Category");
        ov->set_next_item_width(-1);
        int shown = search[0] ? 0 : current;
        if (ov->combo("##category", &shown, groups, n)) {
            current = shown;
            choose_category(groups, current);
        }
    } else {
        begin_pane(ov, CATEGORIES, "##categories", em * 9, height);
        ov->heading("Categories");
        for (int j = 0; j < n; ++j) {
            if (ov->selectable(groups[j], (search[0] ? 0 : current) == j)) {
                current = j;
                choose_category(groups, current);
            }
        }
        ov->end_child();
        ov->same_line();
    }
    begin_pane(ov, OPTIONS, "##options", 0, 0);
    ov->set_next_item_width(-1);
    if (focus_search) ov->set_keyboard_focus_here();
    ov->input_text(search_id ? "##SearchB" : "##SearchA", search, sizeof search);
    search_active = ov->is_item_active() != 0;
    if (search_active) pane = OPTIONS;
    else if (!search[0]) {
        float x0, y0, x1, y1;
        ov->item_rect(&x0, &y0, &x1, &y1);
        float padding = (y1 - y0) * .15f;
        ov->draw_text(x0 + 2 * padding, y0 + padding, ov->theme(OV_THEME_TEXT_DIM),
                      0, y1 - y0 - 2 * padding, "Search   Ctrl+F");
    }
    bool keys = !focus_search && navigation_allowed(ov);
    int prior_selection = selected;
    enum Pane before = pane;
    if (keys) navigate(ov, groups, n, current);
    int results[HUD_OPTION_COUNT], count = 0;
    for (int i = 0; i < HUD_OPTION_COUNT; ++i)
        if (matches(hud_option_descriptor((unsigned)i))) results[count++] = i;
    if (search[0]) ov->textf("%d matching option%s", count, count == 1 ? "" : "s");
    if (!count) {
        selected = -1;
        ov->text_wrapped("No matching options.");
    } else if (selected < 0 || !matches(hud_option_descriptor((unsigned)selected))) selected = results[0];
    DbfSettings effective = s->options;
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i)
        if (edits[i].dirty) hud_option_set(&effective, i, edits[i].value);
    ov->begin_child("##settings-rows", 0, 0, 0); /* keep search visible while scrolling */
    for (int row = 0; row < count;) {
        unsigned first = (unsigned)results[row];
        const char* group = hud_option_descriptor(first)->group;
        ov->heading(group);
        ov->push_id_int((int)first);
        bool columns = !narrow && ov->begin_table("##inline", 2);
        do {
            setting_row(ov, s, &effective, (unsigned)results[row++], columns, keys && before == pane,
                        keys && (selected != prior_selection || pane != before));
        } while (row < count && !strcmp(group, hud_option_descriptor((unsigned)results[row])->group));
        if (columns) ov->end_table();
        ov->pop_id();
    }
    ov->end_child();
    ov->end_child();
}

void editor_changes(const OvApi* ov, const DbfSnapshot* s)
{
    if (!ov || !s) return;
    editor_change_count(s);
    if (feedback) ov->text_wrapped(feedback);
    /* An inline Undo should move a row between sections on the next draw only. */
    bool was_pending[HUD_OPTION_COUNT];
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i) was_pending[i] = edits[i].dirty;
    bool any = false;
    for (int section = 0; section < 2; ++section) {
        bool pending = section == 0, table = false;
        for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i) {
            const HudOption* d = hud_option_descriptor(i);
            int live = live_value(s, i);
            if (pending != was_pending[i] || (!pending && live == d->initial)) continue;
            if (!table) {
                any = true;
                ov->heading(pending ? "Pending edits" : "Saved overrides");
                table = ov->begin_table(pending ? "##pending" : "##saved", pending ? 5 : 4);
                if (!table) break;
                ov->table_setup_column("Setting");
                ov->table_setup_column("Default");
                ov->table_setup_column("Saved");
                if (pending) ov->table_setup_column("Staged");
                ov->table_setup_column("Action");
                ov->table_headers_row();
            }
            ov->table_next_row();
            ov->table_next_column(); ov->text_disabled(d->group); ov->text_wrapped(d->label);
            ov->table_next_column(); value_text(ov, d, d->initial);
            ov->table_next_column(); value_text(ov, d, live);
            if (pending) { ov->table_next_column(); value_text(ov, d, edits[i].value); }
            ov->table_next_column();
            ov->push_id_int((int)i);
            if (pending) {
                if (edits[i].original != live) {
                    ov->text_wrapped("Saved value changed");
                    if (ov->small_button("Keep staged")) stage(s, i, edits[i].value);
                }
                if (ov->small_button("Undo edit")) stage(s, i, live);
            } else if (ov->small_button("Reset")) stage(s, i, d->initial);
            ov->pop_id();
        }
        if (table) ov->end_table();
    }
    if (!any) ov->text_disabled("All settings use their defaults.");
}
