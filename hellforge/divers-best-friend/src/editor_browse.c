#include "editor_browse.h"
#include "hud_options.h"
#include <string.h>

bool editor_browse_available(const OvApi* ov)
{
    return ov && ov->size >= offsetof(OvApi, heading) + sizeof ov->heading &&
           ov->heading && ov->begin_child && ov->end_child && ov->same_line && ov->content_region_avail &&
           ov->push_color && ov->pop_color && ov->theme && ov->selectable && ov->input_text &&
           ov->set_keyboard_focus_here && ov->want_text_input && ov->is_item_active && ov->key_pressed && ov->key_down &&
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
enum Pane { CATEGORIES, OPTIONS, DETAILS };
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
            feedback = "A saved value changed. Review the conflict in Changes before applying.";
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

static void move_category(int delta)
{
    const char* groups[HUD_OPTION_COUNT + 1] = {NULL};
    int n = 1, current = 0;
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i) {
        const char* group = hud_option_descriptor(i)->group;
        if (n > 1 && !strcmp(groups[n - 1], group)) continue;
        if (category && !strcmp(category, group)) current = n;
        groups[n++] = group;
    }
    int next = current + delta;
    if (next >= 0 && next < n) {
        category = groups[next];
        search[0] = 0;
        selected = -1;
    }
}

static bool navigation_allowed(const OvApi* ov)
{
    return (!ov->is_focused || ov->is_focused()) && !ov->want_text_input() &&
           !search_active && !ov->key_down(0x10) && !ov->key_down(0x11) && !ov->key_down(0x12);
}

static void navigate(const OvApi* ov)
{
    if (ov->key_pressed(0x09)) {
        pane = (enum Pane)((pane + 1) % 3);
        return;
    }
    int delta = ov->key_pressed(0x28) - ov->key_pressed(0x26);
    bool enter = ov->key_pressed(0x0d) || ov->key_pressed(0x27);
    if (pane == CATEGORIES) {
        if (delta) move_category(delta);
        if (enter) pane = OPTIONS;
    } else if (pane == OPTIONS) {
        if (delta) {
            for (int i = selected + delta; i >= 0 && i < HUD_OPTION_COUNT; i += delta) {
                if (matches(hud_option_descriptor((unsigned)i))) { selected = i; break; }
            }
        }
        if (enter && selected >= 0) pane = DETAILS;
        if (ov->key_pressed(0x25)) pane = CATEGORIES;
    }
}

static void begin_pane(const OvApi* ov, enum Pane which, const char* id, float width, float height)
{
    ov->push_color(OV_COL_BORDER, ov->theme(which == pane ? OV_THEME_ACCENT : OV_THEME_LINE));
    ov->begin_child(id, width, height, 1);
    ov->pop_color(1);
}

static void details(const OvApi* ov, const DbfSnapshot* s, unsigned i, bool keys)
{
    const HudOption* d = hud_option_descriptor(i);
    DbfSettings effective = s->options;
    for (unsigned j = 0; j < HUD_OPTION_COUNT; ++j)
        if (edits[j].dirty) hud_option_set(&effective, j, edits[j].value);
    int value = hud_option_get(&effective, d->key);
    bool available = hud_option_available(&effective, i);
    ov->text_disabled(d->group);
    ov->heading(d->label);
    ov->begin_disabled(!available);
    ov->push_id_int((int)i);
    int changed;
    if (d->widget == HUD_TOGGLE) changed = ov->checkbox("Enabled", &value);
    else if (d->widget == HUD_CHOICE) {
        value -= d->min;
        changed = ov->combo("##value", &value, d->choices, d->max - d->min + 1);
        value += d->min;
    } else {
        changed = ov->slider_int("##value", &value, d->min, d->max);
        value = d->min + (value - d->min + d->step / 2) / d->step * d->step;
        if (value > d->max) value = d->max;
    }
    if (ov->is_item_active()) pane = DETAILS;
    if (keys && pane == DETAILS && available) {
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
    if (available && changed) stage(s, i, value);
    if (keys && pane == DETAILS && ov->key_pressed(0x2e)) stage(s, i, live_value(s, i));
    ov->pop_id();
    ov->end_disabled();
    if (!available) ov->text_wrapped("Unavailable with the current settings.");
    ov->separator();
    ov->text_disabled("Saved"); ov->same_line(); value_text(ov, d, live_value(s, i));
    ov->text_disabled("Default"); ov->same_line(); value_text(ov, d, d->initial);
    if (edits[i].dirty) {
        ov->text_disabled("Staged"); ov->same_line(); value_text(ov, d, edits[i].value);
        if (ov->small_button("Undo edit")) stage(s, i, live_value(s, i));
    }
}

void editor_browse(const OvApi* ov, const DbfSnapshot* s, bool focus_search)
{
    if (!ov || !s) return;
    editor_change_count(s);
    if (feedback) ov->text_wrapped(feedback);
    if (focus_search) ov->set_keyboard_focus_here();
    ov->input_text(search_id ? "Search##b" : "Search##a", search, sizeof search);
    search_active = ov->is_item_active() != 0;
    bool keys = !focus_search && navigation_allowed(ov);
    enum Pane before = pane;
    if (keys) navigate(ov);
    float width, height;
    ov->content_region_avail(&width, &height);
    begin_pane(ov, CATEGORIES, "##categories", width * .18f, height);
    ov->heading("Categories");
    if (ov->selectable("All settings", !category || search[0])) {
        category = NULL;
        pane = CATEGORIES;
        search[0] = 0;
    }
    const char* previous = NULL; /* descriptors are grouped in display order */
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i) {
        const char* group = hud_option_descriptor(i)->group;
        if (previous && !strcmp(previous, group)) continue;
        previous = group;
        if (ov->selectable(group, !search[0] && category && !strcmp(group, category))) {
            category = group;
            pane = CATEGORIES;
            search[0] = 0;
        }
    }
    ov->end_child();
    ov->same_line();
    begin_pane(ov, OPTIONS, "##options", width * .29f, height);
    ov->heading("Options");
    if (selected >= 0 && !matches(hud_option_descriptor((unsigned)selected))) selected = -1;
    for (int i = 0; i < HUD_OPTION_COUNT; ++i) {
        const HudOption* d = hud_option_descriptor((unsigned)i);
        if (!matches(d)) continue;
        if (selected < 0) selected = i;
        if (ov->selectable(d->label, selected == i)) { selected = i; pane = OPTIONS; }
    }
    if (selected < 0) ov->text_wrapped("No matching options.");
    ov->end_child();
    ov->same_line();
    begin_pane(ov, DETAILS, "##details", 0, height);
    if (selected >= 0) details(ov, s, (unsigned)selected, keys && before == pane);
    ov->end_child();
}

void editor_changes(const OvApi* ov, const DbfSnapshot* s)
{
    if (!ov || !s) return;
    editor_change_count(s);
    if (feedback) ov->text_wrapped(feedback);
    if (!ov->begin_table("##settings-changes", 5)) return;
    const char* columns[] = { "Setting", "Default", "Saved", "Staged", "Review" };
    for (int c = 0; c < 5; ++c) ov->table_setup_column(columns[c]);
    ov->table_headers_row();
    bool any = false;
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i) {
        const HudOption* d = hud_option_descriptor(i);
        int live = live_value(s, i);
        if (live == d->initial && !edits[i].dirty) continue;
        any = true;
        ov->table_next_row();
        ov->table_next_column(); ov->text_wrapped(d->label);
        ov->table_next_column(); value_text(ov, d, d->initial);
        ov->table_next_column(); value_text(ov, d, live);
        ov->table_next_column();
        if (edits[i].dirty) value_text(ov, d, edits[i].value);
        else ov->text_disabled("-");
        ov->table_next_column();
        ov->push_id_int((int)i);
        if (edits[i].dirty) {
            if (edits[i].original != live) {
                ov->text_wrapped("Saved value changed");
                if (ov->small_button("Keep staged")) stage(s, i, edits[i].value);
            }
            if (ov->small_button("Undo edit")) stage(s, i, live);
        } else if (ov->small_button("Reset")) stage(s, i, d->initial);
        ov->pop_id();
    }
    ov->end_table();
    if (!any) ov->text_disabled("All settings use their defaults.");
}
