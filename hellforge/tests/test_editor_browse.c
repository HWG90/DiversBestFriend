#include <string.h>
#include <stdarg.h>
#include "editor_browse.h"
#include "editor_icons.h"
#include "fake_ov.h"
#include "hud_options.h"
#include "test.h"

static OvApi ov;
static DbfSnapshot s;
static int key, modifier, editing, focuses, children;
static const char* child_id;
static bool input_in_options, hint_in_options;
static const char *query, *clicked, *headings[8];
static int clicked_category = -1, clicked_section = -1, section_rows, category_rows;
static int heading_count, category_pick = -1, category_combos, controls, focused_id, id;
static float region_width = 900, rows_width = 900;
static int column_setups, submitted_extents, glyph_parts;
static float column_weights[2];
static void setup_column(const char* label, int stretch, float weight)
{
    CHECK(stretch && weight >= .35f && weight <= .65f, "settings columns have bounded stretch weights");
    column_weights[column_setups++ % 2] = weight;
}
static bool disabled, row_focus_requested;
static int combo_edit = -1;
static bool slider_disabled;
static char result_count[64];
static int pressed(int k) { return key == k; }
static int held(int k) { return modifier == k; }
static int text_active(void) { return editing; }
static int active;
static const char* dragged;
static bool splitter_active;
static float drag_x;
static int hit_splitter(const char* label, float w, float h)
{
    splitter_active = dragged && !strcmp(dragged, label);
    CHECK(w > 0 && h >= 0, "divider hit target has positive width and bounded height");
    return 0;
}
static void mouse(float* x, float* y) { *x = drag_x; *y = 0; }
static int hovered(void) { return 0; }
static void line(float x0, float y0, float x1, float y1, uint32_t color, float thickness) {}

static int item_active(void) { return splitter_active || active; }
static void nothing(void) {}
static void number(int n) { (void)n; }
static void color(int slot, uint32_t c) { (void)slot; (void)c; }
static void focus(void) { ++focuses; row_focus_requested = true; }
static void size(float* w, float* h) { *w = child_id && !strcmp(child_id, "##settings-rows") ? rows_width : region_width; *h = 500; }
static void child(const char* id, float w, float h, int border) { ++children; child_id = id; }
static void end_child(void) { child_id = NULL; }
static void width(float w) {}
static void extent(float width, float height) { ++submitted_extents; }
static void glyph_rect(float x0, float y0, float x1, float y1, uint32_t color, float rounding)
{
    CHECK(x0 >= 10 && y0 >= 20 && x1 <= 34 && y1 <= 44 && x1 > x0 && y1 > y0,
          "navigation glyph stays inside its icon slot");
    CHECK(color == fake_ov_theme_color(OV_THEME_GOLD), "navigation glyph uses the host gold token");
    ++glyph_parts;
}
static void glyph_circle(float x, float y, float radius, uint32_t color, float thickness)
{
    CHECK(x-radius >= 10 && y-radius >= 20 && x+radius <= 34 && y+radius <= 44,
          "round glyph stays inside its icon slot");
    CHECK(color == fake_ov_theme_color(OV_THEME_GOLD), "round glyph uses the host gold token");
    ++glyph_parts;
}
static void rect(float* x, float* y, float* right, float* bottom)
{ *x = 4; *y = 4; *right = 200; *bottom = 32; }
static void draw_hint(float x, float y, uint32_t color, int font, float size, const char* text)
{
    if (child_id && !strcmp(child_id, "##options") && !strcmp(text, "Search   Ctrl+F")) hint_in_options = true;
}
static void title(const char* label)
{
    if (heading_count < 8) headings[heading_count++] = label;
}
static void wrapped(const char* text)
{
    fake_ov_api()->text_wrapped(text);
    if (!child_id || strcmp(child_id, "##settings-rows")) return;
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i) {
        const char* group = hud_option_descriptor(i)->group;
        if (!strcmp(text, group)) {
            if (!heading_count || strcmp(headings[heading_count - 1], group)) title(group);
            break;
        }
    }
}
static void push_id(int value) { id = value; }
static void begin_disabled(int flag) { disabled = flag != 0; }
static void cursor(float x, float y) {}
static int row(const char* label, int selected, float w, float h, int span)
{
    if (!strcmp(label, "##group")) {
        bool navigation = child_id && !strcmp(child_id, "##categories");
        if (navigation) ++category_rows; else ++section_rows;
        int* target = navigation ? &clicked_category : &clicked_section;
        if (*target == id) { *target = -1; return 1; }
    }
    if (row_focus_requested) focused_id = id;
    row_focus_requested = false;
    return 0;
}
static int click(const char* label) { return clicked && !strcmp(clicked, label); }
static int select_row(const char* label, int selected) { return click(label); }
static int input(const char* label, char* buffer, size_t n)
{
    row_focus_requested = false;
    splitter_active = false;
    input_in_options = child_id && !strcmp(child_id, "##options");
    if (!query) return 0;
    snprintf(buffer, n, "%s", query);
    query = NULL;
    return 1;
}
static int toggle(const char* label, int* value) { ++controls; return 0; }
static int combo(const char* label, int* value, const char* const* items, int n)
{
    if (!strcmp(label, "##category")) {
        ++category_combos;
        if (category_pick < 0) return 0;
        *value = category_pick;
        category_pick = -1;
        return 1;
    }
    ++controls;
    if (id == combo_edit) {
        *value = 2; /* Native wheel */
        combo_edit = -1;
        return 1;
    }
    return 0;
}
static int slider(const char* label, int* value, int min, int max) { ++controls; slider_disabled = disabled; return 0; }
static void formatted(const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    vsnprintf(result_count, sizeof result_count, fmt, args);
    va_end(args);
}
static bool panel_focus = true;
static void frame(int vk)
{
    key = vk;
    heading_count = controls = children = column_setups = section_rows = category_rows = 0;
    hint_in_options = false;
    submitted_extents = 0;
    result_count[0] = 0;
    fake_ov_reset();
    editor_browse_focused(&ov, &s, false, panel_focus);
    key = 0;
}

int main(void)
{
    snap_init();
    settings_defaults(&s.options);
    fake_ov_reset();
    ov = *fake_ov_api();
    ov.key_pressed = pressed; ov.key_down = held; ov.want_text_input = text_active;
    ov.is_item_active = item_active; ov.set_keyboard_focus_here = focus; ov.input_text = input;
    ov.heading = title; ov.content_region_avail = size; ov.begin_child = child; ov.end_child = end_child;
    ov.set_next_item_width = width; ov.item_rect = rect; ov.draw_text = draw_hint;
    ov.push_color = color; ov.pop_color = number; ov.selectable = select_row; ov.same_line = nothing;
    ov.begin_disabled = begin_disabled; ov.end_disabled = nothing; ov.push_id_int = push_id; ov.pop_id = nothing;
    ov.checkbox = toggle; ov.combo = combo; ov.slider_int = slider; ov.textf = formatted;
    ov.dummy = extent; ov.text_wrapped = wrapped; ov.small_button = click; ov.table_setup_column_ex = setup_column;
    ov.invisible_button = hit_splitter; ov.mouse_pos = mouse;
    ov.is_item_hovered = hovered; ov.draw_line = line;
    ov.cursor_screen_pos = size; ov.set_cursor_screen_pos = cursor; ov.selectable_ex = row;

    CHECK(editor_browse_available(&ov) && !editor_browse_available(fake_ov_api()),
          "legacy fake stays on the original path");
    frame(0);
    CHECK(input_in_options && hint_in_options, "empty Search field shows Ctrl+F inside Options");
    CHECK(controls == 3 && section_rows == 7 && category_rows == 8,
          "overview shows seven collapsible groups with only Selection initially expanded");
    CHECK(submitted_extents == section_rows + category_rows,
          "every group row submits its final cursor extent, including the last collapsed section");
    OvApi glyph = ov;
    glyph.draw_rect_filled = glyph_rect;
    glyph.draw_circle = glyph_circle;
    const char* names[] = {"All settings", "SELECTION", "APPEARANCE", "LIST SELECT",
                          "HUD LAYOUT", "COOLDOWN DISPLAY", "TERMINALS", "ADVANCED"};
    for (unsigned i = 0; i < sizeof names / sizeof *names; ++i) {
        glyph_parts = 0;
        editor_icon(&glyph, names[i], 10, 20, 24);
        CHECK(glyph_parts > 0, "each settings group has a navigation glyph");
    }
    glyph_parts = 0;
    editor_icon(&glyph, "unknown", 10, 20, 24);
    editor_icon(NULL, "SELECTION", 10, 20, 24);
    glyph.draw_rect_filled = NULL;
    editor_icon(&glyph, "SELECTION", 10, 20, 24);
    CHECK(glyph_parts == 0, "unknown icons and absent drawing callbacks are harmless");
    CHECK(fake_ov_find("text_disabled:STRATAGEMS", 0) >= 0 &&
          fake_ov_find("text_disabled:HUD", 0) >= 0 &&
          fake_ov_find("text_disabled:AUTOMATION", 0) >= 0, "navigation groups related categories");
    clicked_section = 3; frame(0);
    CHECK(controls == 12 && fake_ov_find("text_wrapped:Wheel size (%)", 0) >= 0,
          "expanding Appearance reveals its nine settings");
    clicked_section = 3; frame(0);
    CHECK(controls == 3, "collapsing Appearance hides its fields");
    query = " "; frame(0);
    CHECK(controls == HUD_OPTION_COUNT && heading_count == 7,
          "global search opens all matching groups");
    CHECK(fake_ov_find("text_wrapped:Choose Native wheel mode.", 0) >= 0,
          "search retains exact prerequisites beside unavailable controls");
    CHECK(column_setups == 14 && column_weights[0] + column_weights[1] == 1,
          "all visible groups explicitly size label and control columns");
    dragged = "##setting-divider"; drag_x = -1000; frame(0);
    dragged = NULL; splitter_active = false; frame(0);
    CHECK(column_weights[0] == .35f, "dragging the divider clamps the label column minimum");
    dragged = "##setting-divider"; drag_x = 10000; frame(0);
    dragged = NULL; splitter_active = false; frame(0);
    CHECK(column_weights[0] == .65f, "dragging the divider preserves the control column minimum");
    rows_width = 300; frame(0);
    CHECK(column_setups == 0 && controls == HUD_OPTION_COUNT,
          "actual settings pane width stacks every normal option even in a wide outer window");
    rows_width = 900;
    editor_browse_escape();
    region_width = 360; category_pick = 6; frame(0);
    CHECK(category_combos == 1 && controls == 2 && heading_count == 1 && !strcmp(headings[0], "TERMINALS"),
          "narrow layout replaces the sidebar with a category selector and stacks its controls");
    query = "wheel size (%)"; frame(0);
    CHECK(controls == 1 && !strcmp(result_count, "1 matching option") && !strcmp(headings[0], "APPEARANCE"),
          "global search counts and groups results outside the active category");
    query = "native_opacity"; frame(0);
    CHECK(slider_disabled && fake_ov_find("text_wrapped:Choose Native wheel mode.", 0) >= 0,
          "disabled control and prerequisite stay together in narrow search");
    frame(0x27);
    CHECK(editor_change_count(&s) == 0, "keyboard cannot edit a disabled setting");
    query = "selection_mode_ordered"; combo_edit = 3; frame(0);
    query = "native_opacity"; frame(0);
    CHECK(!slider_disabled && fake_ov_find("text_wrapped:Choose Native wheel mode.", 0) < 0 &&
          s.options.selection_mode_ordered == 1, "staged mode immediately unlocks dependent controls");
    editor_discard_changes();
    query = "missing search"; frame(0);
    CHECK(!controls && !strcmp(result_count, "0 matching options"), "empty results show a zero count");
    editor_browse_escape(); category_pick = 0; frame(0);
    region_width = 900;
    children = 0; focuses = 0; hint_in_options = false;
    active = 1;
    editor_browse(&ov, &s, true);
    active = 0;
    CHECK(children == 3 && focuses == 1 && input_in_options && !hint_in_options, "Ctrl+F focuses the pinned search in the settings pane");
    CHECK(editor_browse_escape(), "Escape consumes even an empty active search");
    clicked_category = 1; frame(0);
    frame(0x09); frame('Q'); frame('E');
    frame(0x27); /* enter the selected category with Right */
    frame(0x28);
    CHECK(controls == 3 && focused_id == 1, "Tab/Q/E leave Browse untouched; arrows enter and navigate the selected category");
    panel_focus = false;
    frame(0x28); frame(0x0d);
    CHECK(focused_id == 1 && editor_change_count(&s) == 0, "another panel blocks Browse arrows and Enter");
    panel_focus = true;
    frame(0x0d);
    CHECK(editor_change_count(&s) == 1, "Enter stages the selected toggle");
    editing = 1; frame(0x2e); editing = 0;
    modifier = 0x11; frame(0x2e); modifier = 0;
    CHECK(editor_change_count(&s) == 1, "text entry and modified keys leave the draft alone");
    frame(0x2e);
    CHECK(editor_change_count(&s) == 0, "Delete reverts only the selected draft");
    query = "DoCk_GaP"; frame(0);
    CHECK(controls == 1 && fake_ov_find("text_wrapped:Dock gap above stamina", 0) >= 0, "search finds a settings key across categories");
    panel_focus = false; frame(0x27);
    CHECK(editor_change_count(&s) == 0, "another panel cannot adjust a Browse slider with Right");
    panel_focus = true; frame(0x27);
    CHECK(editor_change_count(&s) == 1, "right arrow adjusts a slider by its descriptor step");
    CHECK(editor_browse_escape() && !editor_browse_escape(), "first Escape clears the query, next can close");
    UiEvent events[UI_QUEUE_SLOTS] = {0};
    CHECK(ui_drain(events, UI_QUEUE_SLOTS) == 0, "editing never posts an event before Apply");
    s.options.dock_gap += 4;
    CHECK(!editor_apply_changes(&ov, &s), "a newer saved value requires explicit conflict resolution");
    s.options.enabled = false;
    heading_count = 0;
    editor_changes(&ov, &s);
    CHECK(heading_count == 2 && !strcmp(headings[0], "Pending edits") && !strcmp(headings[1], "Saved overrides"),
          "Review separates pending edits from saved overrides and lists pending first");
    clicked = "Keep staged"; editor_changes(&ov, &s); clicked = NULL;
    CHECK(editor_apply_changes(&ov, &s), "resolved conflict can be applied");
    CHECK(ui_drain(events, UI_QUEUE_SLOTS) == 1 && events[0].b == 26,
          "resolved slider retains its original staged value");
    s.settings_save_failed = true; ++s.tick;
    CHECK(editor_change_count(&s) == 1 && editor_apply_changes(&ov, &s), "failed persistence can retry");
    CHECK(!editor_apply_changes(&ov, &s), "same snapshot cannot queue duplicate Apply");
    CHECK(ui_drain(events, UI_QUEUE_SLOTS) == 1, "retry queues exactly one edit");
    s.settings_save_failed = false;
    s.options.dock_gap = 26; ++s.tick;
    CHECK(editor_change_count(&s) == 0, "published saved values acknowledge edits");

    s.options.enabled = false;
    editor_reset_defaults(&s);
    CHECK(editor_change_count(&s) == 2, "reset stages only nondefaults");
    s.options.icon_size = 110;
    CHECK(ui_post_batch(events, UI_QUEUE_SLOTS - 1), "fill queue leaving a single slot");
    CHECK(!editor_apply_changes(&ov, &s) && editor_change_count(&s) == 2, "full queue retains all edits");
    CHECK(ui_drain(events, UI_QUEUE_SLOTS) == UI_QUEUE_SLOTS - 1, "no partial batch was posted");
    CHECK(editor_apply_changes(&ov, &s) && ui_drain(events, UI_QUEUE_SLOTS) == 2, "queue retry posts both edits");
    for (int i = 0; i < 2; ++i) hud_option_set(&s.options, (unsigned)events[i].a, events[i].b);
    CHECK(s.options.enabled && s.options.dock_gap == 24 && s.options.icon_size == 110,
          "Apply preserves unrelated changes published after staging defaults");
    editor_reset_defaults(&s); editor_discard_changes();
    CHECK(editor_change_count(&s) == 0 && s.options.icon_size == 110, "footer Discard releases the draft");
    TEST_MAIN_END
}
