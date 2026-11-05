#include <string.h>
#include "editor_browse.h"
#include "fake_ov.h"
#include "hud_options.h"
#include "test.h"

static OvApi ov;
static DbfSnapshot s;
static int key, modifier, editing, focuses, children;
static const char* child_id;
static bool input_in_options, hint_in_options;
static const char *query, *clicked, *heading;
static int pressed(int k) { return key == k; }
static int held(int k) { return modifier == k; }
static int text_active(void) { return editing; }
static int active;
static int item_active(void) { return active; }
static void nothing(void) {}
static void number(int n) { (void)n; }
static void color(int slot, uint32_t c) { (void)slot; (void)c; }
static void focus(void) { ++focuses; }
static void size(float* w, float* h) { *w = 900; *h = 500; }
static void child(const char* id, float w, float h, int border) { ++children; child_id = id; }
static void end_child(void) { child_id = NULL; }
static void width(float w) {}
static void rect(float* x, float* y, float* right, float* bottom)
{ *x = 4; *y = 4; *right = 200; *bottom = 32; }
static void draw_hint(float x, float y, uint32_t color, int font, float size, const char* text)
{
    hint_in_options = child_id && !strcmp(child_id, "##options") && !strcmp(text, "Search   Ctrl+F");
}
static void title(const char* label) { heading = label; }
static int click(const char* label) { return clicked && !strcmp(clicked, label); }
static int select_row(const char* label, int selected) { return click(label); }
static int input(const char* label, char* buffer, size_t n)
{
    input_in_options = child_id && !strcmp(child_id, "##options");
    if (!query) return 0;
    snprintf(buffer, n, "%s", query);
    query = NULL;
    return 1;
}
static int toggle(const char* label, int* value) { return 0; }
static int combo(const char* label, int* value, const char* const* items, int n) { return 0; }
static int slider(const char* label, int* value, int min, int max) { return 0; }
static void formatted(const char* fmt, ...) {}
static void frame(int vk)
{
    key = vk;
    heading = NULL;
    editor_browse(&ov, &s, false);
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
    ov.begin_disabled = number; ov.end_disabled = nothing; ov.push_id_int = number; ov.pop_id = nothing;
    ov.checkbox = toggle; ov.combo = combo; ov.slider_int = slider; ov.textf = formatted;
    ov.small_button = click;

    CHECK(editor_browse_available(&ov) && !editor_browse_available(fake_ov_api()),
          "legacy fake stays on the original path");
    frame(0);
    CHECK(input_in_options && hint_in_options, "empty Search field shows Ctrl+F inside Options");
    children = 0; hint_in_options = false;
    active = 1;
    editor_browse(&ov, &s, true);
    active = 0;
    CHECK(children == 3 && focuses == 1 && input_in_options && !hint_in_options, "three panes and explicit Ctrl+F focus");
    CHECK(editor_browse_escape(), "Escape consumes even an empty active search");
    frame(0x25); /* options -> categories */
    frame(0x28); /* All -> SELECTION */
    frame(0x09); /* options */
    frame(0x28);
    CHECK(!strcmp(heading, "Sound feedback"), "arrows select within the active category");
    frame(0x27); /* details */
    frame(0x0d);
    CHECK(editor_change_count(&s) == 1, "Enter stages the selected toggle");
    editing = 1; frame(0x2e); editing = 0;
    modifier = 0x11; frame(0x2e); modifier = 0;
    CHECK(editor_change_count(&s) == 1, "text entry and modified keys leave the draft alone");
    frame(0x2e);
    CHECK(editor_change_count(&s) == 0, "Delete reverts only the selected draft");
    query = "DoCk_GaP"; frame(0);
    CHECK(!strcmp(heading, "Dock gap above stamina"), "search finds a settings key across categories");
    frame(0x27);
    CHECK(editor_change_count(&s) == 1, "right arrow adjusts a slider by its descriptor step");
    CHECK(editor_browse_escape() && !editor_browse_escape(), "first Escape clears the query, next can close");
    UiEvent events[UI_QUEUE_SLOTS] = {0};
    CHECK(ui_drain(events, UI_QUEUE_SLOTS) == 0, "editing never posts an event before Apply");
    s.options.dock_gap += 4;
    CHECK(!editor_apply_changes(&ov, &s), "a newer saved value requires explicit conflict resolution");
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
