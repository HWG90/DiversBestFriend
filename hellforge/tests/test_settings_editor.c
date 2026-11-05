#include <string.h>
#include "addresses_25480438.h"
#include "fake_ov.h"
#include "hud_options.h"
#include "settings_editor.h"
#include "test.h"

static DbfSnapshot snap;
static OvApi ov;
static const char *tab = "CONTROLS", *button, *typed, *row;
static int vk, action, pushed_id, edited_kind, mouse = -1;
static float wheel;
static bool focused = true, disabled, direct;
static const char* selected_action;
static int visible_rows, icon_slots, tabs_opened;
static void cursor(float* x, float* y) { *x = 12; *y = 20; }
static float line_height(void) { return 16; }
static void reserve_icon(float w, float h)
{
    CHECK(w == 16 && h == 16, "blacklist icon fits its row");
    ++icon_slots;
}
static int select_action(const char* label, int selected)
{
    return selected_action && !strcmp(label, selected_action);
}
static int tab_item(const char* label) { ++tabs_opened; return !strcmp(tab,label); }
static void nothing(void) {}
static void push(int id) { pushed_id = id; }
static void disable(int flag) { disabled = flag; }
static void enable(void) { disabled = false; }
static int action_combo(const char* label, int* value, const char* const* items, int count)
{
    if (*value == action) return 0;
    *value = action;
    return 1;
}
static int edit_text(const char* label, char* text, size_t cap)
{
    if (!typed) return 0;
    snprintf(text, cap, "%s", typed);
    return 1;
}
static int click(const char* label) { return button && !disabled && !strcmp(button,label); }
static int down(int key) { return vk == key; }
static int mouse_down(int key) { return mouse == key; }
static float scroll(void) { return wheel; }
static int focus(void) { return focused; }
static int toggle(const char* label, int* value)
{
    ++visible_rows;
    if (!row || strcmp(label,row) || edited_kind != pushed_id) return 0;
    *value = !*value;
    return 1;
}
static void frame(const char* clicked)
{
    button = clicked;
    visible_rows = icon_slots = 0;
    if (direct) editor_page(&ov, &snap, !strcmp(tab, "BLACKLIST"));
    else editor_tabs(&ov, &snap);
    typed = row = NULL;
}
static bool commit_one(void)
{
    UiEvent e[2];
    return ui_drain(e, 2) == 1 && editor_apply(&snap.options, e);
}
static void capture_start(void)
{
    frame("CAPTURE");
    mouse = 0;
    frame(NULL); /* Held initiating click cannot bind itself. */
    mouse = -1;
    frame(NULL);
}
static void check_capture(int key, int mouse_button, float delta, uint16_t pad, int kind, int code)
{
    capture_start();
    vk = key; mouse = mouse_button; wheel = delta; snap.editor_pad = pad;
    frame(NULL);
    vk = 0; mouse = -1; wheel = 0; snap.editor_pad = 0;
    frame(direct ? "APPLY BINDING" : "APPLY");
    CHECK(commit_one() && snap.options.bind[action].kind == kind && snap.options.bind[action].code == code,
          "capture submits the intended physical input after release");
}
int main(void)
{
    snap_init();
    settings_defaults(&snap.options);
    ov = *fake_ov_api();
    ov.begin_tab_item = tab_item; ov.end_tab_item = nothing;
    ov.button = click; ov.input_text = edit_text; ov.combo = action_combo;
    ov.key_down = down; ov.mouse_down = mouse_down; ov.mouse_wheel = scroll; ov.is_focused = focus;
    ov.push_id_int = push; ov.pop_id = nothing; ov.begin_disabled = disable; ov.end_disabled = enable;
    ov.checkbox = toggle; ov.same_line = nothing;
    UiEvent e;
    for (action = 0; action < BIND_COUNT; ++action) {
        typed = "key:q";
        frame("APPLY");
        CHECK(commit_one() && snap.options.bind[action].kind == BIND_KEY && snap.options.bind[action].code == 'Q',
              "typed binding applies to the selected action");
    }
    action = BIND_SLOT2;
    check_capture('Z',-1,0,0,BIND_KEY,'Z');
    check_capture(5,-1,0,0,BIND_MOUSE,4);
    check_capture(0,2,0,0,BIND_MOUSE,3);
    check_capture(0,-1,-1,0,BIND_WHEEL_DOWN,0);
    check_capture(0,-1,1,0,BIND_WHEEL_UP,0);
    check_capture(0,-1,0,BIND_PAD_RB,BIND_PAD,BIND_PAD_RB);
    capture_start(); vk = 27; frame(NULL); vk = 0; frame("APPLY");
    CHECK(!ui_drain(&e,1), "Escape cancels capture");
    capture_start(); focused = false; frame(NULL); focused = true; frame("APPLY");
    CHECK(!ui_drain(&e,1), "focus loss cancels capture");
    typed = "pad:no_such_button"; frame("APPLY");
    CHECK(!ui_drain(&e,1), "invalid input stays in the editor");
    frame("CLEAR"); frame("APPLY");
    CHECK(commit_one() && snap.options.bind[action].kind == BIND_NONE, "clear applies an unbound action");

    tab = "BLACKLIST";
    snap.options.hide_sos = true;
    row = "SOS Beacon"; edited_kind = DBF_VAL_HIDE_SOS_KIND; frame(NULL);
    row = "Cargo container (138)"; edited_kind = 138; frame(NULL);
    CHECK(!ui_drain(&e,1) && snap.options.hide_sos, "multiple blacklist rows are draft edits");
    frame("APPLY");
    CHECK(commit_one() && !snap.options.hide_sos && !snap.options.blacklist_kind[145] &&
          snap.options.blacklist_kind[138] && !snap.options.blacklist_kind[71],
          "atomic blacklist batch clears the legacy alias and distinguishes equal labels");
    row = "Eagle Rearm"; edited_kind = DBF_VAL_HIDE_EAGLE_REARM_KIND; frame(NULL); frame("DISCARD"); frame("APPLY");
    CHECK(!ui_drain(&e,1), "discard leaves the original blacklist active");
    e = (UiEvent){.kind=UI_BLACKLIST,.changed_rows=UINT64_MAX,.hidden_rows=UINT64_MAX};
    CHECK(!editor_apply(&snap.options,&e) && !snap.options.blacklist_kind[5], "invalid batch refused whole");
    e = (UiEvent){.kind=UI_BINDING,.a=BIND_NEXT,.b=BIND_PAD*65536+3};
    CHECK(!editor_apply(&snap.options,&e), "multi-bit pad binding refused");
    e.b = BIND_MOUSE*65536+6;
    CHECK(!editor_apply(&snap.options,&e), "out of range mouse binding refused");
    CHECK(hud_option_get(&snap.options,"auto_terminal_complete") == 1 && hud_option_get(&snap.options,"terminal_input") == 1,
          "R50 terminal defaults are available to runtime");
    direct = true;
    int prior_tabs = tabs_opened;
    ov.selectable = select_action;
    tab = "CONTROLS";
    selected_action = "Slot 4";
    typed = "pad:lb";
    frame("APPLY BINDING");
    CHECK(commit_one() && snap.options.bind[BIND_SLOT4].code == BIND_PAD_LB,
          "editor action list edits the selected binding");
    selected_action = NULL;
    action = BIND_SLOT4;
    check_capture(0x75, -1, 0, 0, BIND_KEY, 0x75); /* F6 normally cycles shell pages. */
    check_capture(0x78, -1, 0, 0, BIND_KEY, 0x78); /* F9 normally applies shell settings. */
    typed = "key:t"; frame(NULL);
    capture_start();
    CHECK(editor_capturing(), "shell shortcuts yield to capture");
    editor_page(&ov, NULL, false);
    CHECK(!editor_capturing() && !ui_drain(&e, 1), "leaving Controls cancels capture without posting");
    frame("APPLY BINDING");
    CHECK(commit_one() && snap.options.bind[action].code == 'T', "binding draft survives navigation away");
    typed = "key:u"; frame(NULL);
    capture_start();
    tab = "BLACKLIST";
    ov.cursor_screen_pos = cursor; ov.text_line_height = line_height; ov.dummy = reserve_icon;
    typed = "cArGo"; frame(NULL);
    CHECK(visible_rows == 2 && icon_slots == 2, "name filter is case-insensitive and includes both cargo kinds");
    row = "Cargo container (71)"; edited_kind = 71; frame(NULL);
    editor_page(&ov, NULL, false);
    typed = "145"; frame(NULL);
    CHECK(visible_rows == 1, "exact numeric search selects the kind");
    row = "SOS Beacon"; edited_kind = 145; frame(NULL);
    typed = "unmatched"; frame("APPLY BLACKLIST");
    CHECK(!visible_rows && !icon_slots && commit_one() && snap.options.blacklist_kind[71] && snap.options.hide_sos,
          "Apply includes drafts hidden by a subsequent search");
    CHECK(!editor_capturing() && snap.options.bind[action].code == 'T',
          "applying Blacklist leaves the binding draft local");
    tab = "CONTROLS"; frame("APPLY BINDING");
    CHECK(commit_one() && snap.options.bind[action].code == 'U',
          "Controls can submit its own draft after Blacklist applies");
    CHECK(tabs_opened == prior_tabs, "direct pages leave navigation to the caller");
    direct = false; tab = "BLACKLIST"; frame(NULL);
    CHECK(!icon_slots && visible_rows == dbf_blacklist_kind_count, "legacy tab still lists every kind after editor search");
    TEST_MAIN_END
}
